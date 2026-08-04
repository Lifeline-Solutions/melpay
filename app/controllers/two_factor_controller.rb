class TwoFactorController < ApplicationController
  before_action :authenticate_user!

  def send_otp
    current_user.generate_otp!
    # For Emails
    UserMailer.with(user: current_user).send_otp.deliver_now

    # For SMS (optional)
    if current_user.phone_number.present?
      begin
        SmsSender.send_otp(current_user.phone_number, current_user.otp_code)
      rescue StandardError => e
        Rails.logger.warn("Failed to send SMS OTP: #{e.message}")
      end
    end

    respond_to do |format|
      format.html { redirect_to verify_otp_path, notice: 'OTP sent.' }
      format.json { render json: { message: 'OTP sent.' }, status: :ok }
    end
  end

  def verify; end

  def check
    if current_user.otp_valid?(params[:otp_code])
      session[:two_factor_authenticated] = true

      # Support batch pending ids
      pending_ids = session.delete(:pending_transaction_ids)
      pending_home_id = session.delete(:pending_transaction_home_id)

      if pending_ids.present?
        # Finalize multiple pending transactions
        success_count = 0
        failed_count = 0
        begin
          # Group by home/client where possible; we can finalize each in sequence
          pending_ids.each do |pid|
            transaction = Transaction.find_by(id: pid, user_id: current_user.id)
            next unless transaction

            client = transaction.client || current_user.client
            home = Home.find_by(id: pending_home_id) || transaction.home
            unless client && home
              Rails.logger.warn "Skipping pending #{pid}: missing client/home"
              next
            end

            client.with_lock do
              # If this transaction has ever succeeded, leave it as-is and skip creating a new revision
              if Transaction.where(home_id: home.id, transaction_id: transaction.transaction_id, status: 'success').exists?
                Rails.logger.info "Skipping finalization for #{transaction.transaction_id}: already successful"
                next
              end

              latest_transaction = Transaction.where(home_id: home.id, transaction_id: transaction.transaction_id, is_latest: true).first
              final_attrs = transaction.attributes.slice('home_id', 'transaction_id', 'client_id', 'user_id', 'amount', 'interest_rate', 'transaction_cost', 'total_cost',
                                                         'deposit_data', 'applied_commission_type', 'applied_commission_value')
              # Backfill commission fields if missing on the pending snapshot
              final_attrs['applied_commission_type'] ||= client.effective_commission_type
              final_attrs['applied_commission_value'] ||= client.effective_commission_value
              # Determine status by balance
              final_attrs['status'] = (client.credit || 0) >= transaction.total_cost.to_f ? 'success' : 'failed'

              final_transaction = if latest_transaction && latest_transaction.id != transaction.id
                                    latest_transaction.create_revision(final_attrs)
                                  else
                                    transaction.create_revision(final_attrs)
                                  end

              final_transaction.save!

              if final_transaction.status == 'success'
                # ensure balance
                raise ActiveRecord::RecordInvalid, final_transaction if (client.credit || 0) < final_transaction.total_cost.to_f

                client.credit = (client.credit || 0) - final_transaction.total_cost.to_f
                client.save!
                success_count += 1

                # Initiate M-Pesa B2C disbursement to the deposit's phone number
                initiate_mpesa_b2c(final_transaction)
              else
                failed_count += 1
              end

              # update home's processed_deposits snapshot
              deposits = home.processed_deposits.is_a?(Array) ? home.processed_deposits : []
              deposits.each do |d|
                next unless d['transaction_id'] == final_transaction.transaction_id

                d['status'] = final_transaction.status
                d['transaction_cost'] = final_transaction.transaction_cost
                d['applied_interest_rate'] = final_transaction.interest_rate
                d['applied_commission_type'] = final_transaction.applied_commission_type
                d['applied_commission_value'] = final_transaction.applied_commission_value
                d['transaction_processed_at'] = Time.current.iso8601
              end
              home.processed_deposits = deposits
              home.save!
            end
          end

          current_user.clear_otp!
          respond_to do |format|
            format.html { redirect_to home_path(pending_home_id), notice: "Processed #{success_count} successful, #{failed_count} failed" }
            format.json { render json: { success: true, processed_success: success_count, processed_failed: failed_count }, status: :ok }
          end
          return
        rescue ActiveRecord::RecordInvalid => e
          current_user.clear_otp!
          message = e.record&.errors&.full_messages&.join(', ').presence || e.message
          respond_to do |format|
            format.html { redirect_to home_path(pending_home_id), alert: "Error finalizing batch transactions: #{message}" }
            format.json { render json: { success: false, error: message }, status: :unprocessable_entity }
          end
          return
        end
      end

      # Existing single pending id flow follows
      pending_id = session.delete(:pending_transaction_id)
      # pending_home_id was already read (and removed from session) above

      if pending_id.present?
        transaction = Transaction.find_by(id: pending_id, user_id: current_user.id)

        if transaction.nil?
          current_user.clear_otp!
          respond_to do |format|
            format.html { redirect_to home_index_path, alert: 'Pending transaction not found or already processed.' }
            format.json { render json: { success: false, error: 'Pending transaction not found' }, status: :not_found }
          end
          return
        end

        # Retrieve associated client and home
        client = transaction.client || current_user.client
        home = Home.find_by(id: pending_home_id) || transaction.home

        unless client && home
          current_user.clear_otp!
          respond_to do |format|
            format.html { redirect_to home_index_path, alert: 'Unable to find client/home for pending transaction.' }
            format.json { render json: { success: false, error: 'Client or home not found' }, status: :unprocessable_entity }
          end
          return
        end

        # Finalize the pending transaction inside a client lock
        begin
          final_transaction = nil
          client.with_lock do
            # If this transaction has ever succeeded, do nothing and return success (idempotent)
            if Transaction.where(home_id: home.id, transaction_id: transaction.transaction_id, status: 'success').exists?
              # Clear OTP outside the lock, then respond below
              final_transaction = nil
            else
              # Create a revision (this will mark previous is_latest = false)
              latest_transaction = Transaction.where(home_id: home.id, transaction_id: transaction.transaction_id, is_latest: true).first

              # Build final attributes based on pending transaction snapshot
              final_attrs = transaction.attributes.slice('home_id', 'transaction_id', 'client_id', 'user_id', 'amount', 'interest_rate', 'transaction_cost', 'total_cost',
                                                         'deposit_data', 'applied_commission_type', 'applied_commission_value')
              # Backfill commission fields if missing on the pending snapshot
              final_attrs['applied_commission_type'] ||= client.effective_commission_type
              final_attrs['applied_commission_value'] ||= client.effective_commission_value
              # Determine status by balance
              final_attrs['status'] = (client.credit || 0) >= transaction.total_cost.to_f ? 'success' : 'failed'

              final_transaction = if latest_transaction && latest_transaction.id != transaction.id
                                    latest_transaction.create_revision(final_attrs)
                                  else
                                    # If the pending transaction is already the latest, create a revision from it
                                    transaction.create_revision(final_attrs)
                                  end

              final_transaction.save!

              if final_transaction.status == 'success'
                # Double-check balance
                raise ActiveRecord::RecordInvalid, final_transaction if (client.credit || 0) < final_transaction.total_cost.to_f

                client.credit = (client.credit || 0) - final_transaction.total_cost.to_f
                client.save!

                # Initiate M-Pesa B2C disbursement to the deposit's phone number
                initiate_mpesa_b2c(final_transaction)
              end

              # Update home's processed_deposits snapshot for this transaction
              deposits = home.processed_deposits.is_a?(Array) ? home.processed_deposits : []
              deposits.each do |d|
                next unless d['transaction_id'] == (final_transaction&.transaction_id || transaction.transaction_id)

                if final_transaction
                  d['status'] = final_transaction.status
                  d['transaction_cost'] = final_transaction.transaction_cost
                  d['applied_interest_rate'] = final_transaction.interest_rate
                  d['applied_commission_type'] = final_transaction.applied_commission_type
                  d['applied_commission_value'] = final_transaction.applied_commission_value
                end
                d['transaction_processed_at'] = Time.current.iso8601
              end
              home.processed_deposits = deposits
              home.save!
            end
          end

          current_user.clear_otp!

          respond_to do |format|
            if final_transaction
              format.html { redirect_to home_path(pending_home_id), notice: 'Transaction confirmed and processed.' }
              format.json do
                render json: {
                  success: true,
                  message: 'Transaction confirmed and processed.',
                  transaction_id: final_transaction.transaction_id,
                  status: final_transaction.status,
                  transaction_cost: final_transaction.transaction_cost,
                  total_cost: final_transaction.total_cost
                }, status: :ok
              end
            else
              # Already successful earlier: idempotent success response, no changes applied
              format.html { redirect_to home_path(pending_home_id), notice: 'This transaction was already completed successfully.' }
              format.json do
                render json: {
                  success: true,
                  message: 'Already completed successfully.'
                }, status: :ok
              end
            end
          end
          return
        rescue ActiveRecord::RecordInvalid => e
          message = e.record&.errors&.full_messages&.join(', ').presence || e.message
          current_user.clear_otp!
          respond_to do |format|
            format.html { redirect_to home_path(pending_home_id || transaction.home_id), alert: "Error finalizing transaction: #{message}" }
            format.json { render json: { success: false, error: message }, status: :unprocessable_entity }
          end
          return
        end
      end

      # No pending transaction - normal OTP (e.g., login) flow
      current_user.clear_otp!
      respond_to do |format|
        format.html { redirect_to home_index_path, notice: 'OTP verified.' }
        format.json { render json: { success: true, message: 'OTP verified' }, status: :ok }
      end
    else
      respond_to do |format|
        format.html do
          flash.now[:alert] = 'Invalid or expired OTP.'
          render :verify
        end
        format.json { render json: { success: false, error: 'Invalid or expired OTP' }, status: :unprocessable_entity }
      end
    end
  end

  def cancel_pending
    # Support batch cancelation
    pending_ids = session.delete(:pending_transaction_ids)
    pending_home_id = session.delete(:pending_transaction_home_id)

    if pending_ids.present?
      processed = 0
      pending_ids.each do |pid|
        transaction = Transaction.find_by(id: pid, user_id: current_user.id)
        next unless transaction

        client = transaction.client || current_user.client
        home = Home.find_by(id: pending_home_id) || transaction.home
        begin
          client.with_lock do
            # If there was ever a success for this transaction, do not alter history
            if Transaction.where(home_id: home.id, transaction_id: transaction.transaction_id, status: 'success').exists?
              Rails.logger.info "Skipping cancel for #{transaction.transaction_id}: already successful"
              next
            end

            latest_transaction = Transaction.where(home_id: home.id, transaction_id: transaction.transaction_id, is_latest: true).first
            final_attrs = transaction.attributes.slice('home_id', 'transaction_id', 'client_id', 'user_id', 'amount', 'interest_rate', 'transaction_cost', 'total_cost',
                                                       'deposit_data', 'applied_commission_type', 'applied_commission_value')
            # Backfill commission fields if missing on the pending snapshot
            final_attrs['applied_commission_type'] ||= client.effective_commission_type
            final_attrs['applied_commission_value'] ||= client.effective_commission_value
            final_attrs['status'] = 'failed'

            final_transaction = if latest_transaction && latest_transaction.id != transaction.id
                                  latest_transaction.create_revision(final_attrs)
                                else
                                  transaction.create_revision(final_attrs)
                                end

            final_transaction.save!

            deposits = home.processed_deposits.is_a?(Array) ? home.processed_deposits : []
            deposits.each do |d|
              next unless d['transaction_id'] == final_transaction.transaction_id

              d['status'] = final_transaction.status
              d['transaction_cost'] = final_transaction.transaction_cost
              d['applied_interest_rate'] = final_transaction.interest_rate
              d['applied_commission_type'] = final_transaction.applied_commission_type
              d['applied_commission_value'] = final_transaction.applied_commission_value
              d['transaction_processed_at'] = Time.current.iso8601
            end
            home.processed_deposits = deposits
            home.save!
          end
          processed += 1
        rescue StandardError => e
          Rails.logger.warn "Failed cancelling pending #{pid}: #{e.message}"
        end
      end

      render json: { success: true, message: "Cancelled #{processed} pending transactions", status: 'failed' }, status: :ok
      return
    end

    # Fallback to single pending id behavior
    pending_id = session.delete(:pending_transaction_id)
    session.delete(:pending_transaction_home_id)

    if pending_id.blank?
      render json: { success: false, error: 'No pending transaction' }, status: :unprocessable_entity
      return
    end

    transaction = Transaction.find_by(id: pending_id, user_id: current_user.id)
    if transaction.nil?
      render json: { success: false, error: 'Pending transaction not found' }, status: :not_found
      return
    end

    # mark as failed by creating a failed revision so history is preserved
    client = transaction.client || current_user.client
    home = transaction.home

    begin
      client.with_lock do
        # If ever succeeded, do not change history
        if Transaction.where(home_id: home.id, transaction_id: transaction.transaction_id, status: 'success').exists?
          render json: { success: true, message: 'Transaction already successful; no cancellation applied.' }, status: :ok
          return
        end

        latest_transaction = Transaction.where(home_id: home.id, transaction_id: transaction.transaction_id, is_latest: true).first
        final_attrs = transaction.attributes.slice('home_id', 'transaction_id', 'client_id', 'user_id', 'amount', 'interest_rate', 'transaction_cost', 'total_cost',
                                                   'deposit_data', 'applied_commission_type', 'applied_commission_value')
        # Backfill commission fields if missing on the pending snapshot
        final_attrs['applied_commission_type'] ||= client.effective_commission_type
        final_attrs['applied_commission_value'] ||= client.effective_commission_value
        final_attrs['status'] = 'failed'

        final_transaction = if latest_transaction && latest_transaction.id != transaction.id
                              latest_transaction.create_revision(final_attrs)
                            else
                              transaction.create_revision(final_attrs)
                            end

        final_transaction.save!

        # update processed_deposits snapshot
        deposits = home.processed_deposits.is_a?(Array) ? home.processed_deposits : []
        deposits.each do |d|
          next unless d['transaction_id'] == final_transaction.transaction_id

          d['status'] = final_transaction.status
          d['transaction_cost'] = final_transaction.transaction_cost
          d['applied_interest_rate'] = final_transaction.interest_rate
          d['applied_commission_type'] = final_transaction.applied_commission_type
          d['applied_commission_value'] = final_transaction.applied_commission_value
          d['transaction_processed_at'] = Time.current.iso8601
        end
        home.processed_deposits = deposits
        home.save!
      end

      render json: { success: true, message: 'Pending transaction cancelled and marked as failed', status: 'failed' }, status: :ok
    rescue StandardError => e
      render json: { success: false, error: e.message }, status: :internal_server_error
    end
  end

  private

  # Errors are rescued and logged — they must never bubble up and roll back the transaction.
  def initiate_mpesa_b2c(transaction)
    deposit_data = transaction.deposit_data || {}
    phone_number = deposit_data['phone number'].to_s.strip
    remarks = deposit_data['description'].to_s.strip.presence || 'Payment'

    if phone_number.blank?
      Rails.logger.warn "[MpesaB2c] No phone number on txn #{transaction.transaction_id} — skipping B2C"
      return
    end

    result = MpesaB2cService.new.pay(
      amount: transaction.amount.to_f,
      phone_number: phone_number,
      transaction_id: transaction.transaction_id,
      remarks: remarks
    )

    if result[:success]
      transaction.update_columns(
        mpesa_conversation_id: result[:conversation_id],
        mpesa_originator_conversation_id: result[:originator_conversation_id]
      )
      Rails.logger.info "[MpesaB2c] Initiated — txn #{transaction.transaction_id}, conversation #{result[:conversation_id]}"
    else
      Rails.logger.error "[MpesaB2c] Failed to initiate — txn #{transaction.transaction_id}: #{result[:error]}"
    end
  rescue StandardError => e
    Rails.logger.error "[MpesaB2c] Unexpected error for #{transaction&.transaction_id}: #{e.message}"
  end
end
