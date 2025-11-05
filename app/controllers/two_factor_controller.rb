class TwoFactorController < ApplicationController
  before_action :authenticate_user!

  def send_otp
    current_user.generate_otp!
    # For Emails
    UserMailer.with(user: current_user).send_otp.deliver_later

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
              latest_transaction = Transaction.where(home_id: home.id, transaction_id: transaction.transaction_id, is_latest: true).first
              final_attrs = transaction.attributes.slice('home_id', 'transaction_id', 'client_id', 'user_id', 'amount', 'interest_rate', 'transaction_cost', 'total_cost',
                                                         'deposit_data')
              # Determine candidate status by balance
              candidate_status = (client.credit || 0) >= transaction.total_cost.to_f ? 'success' : 'failed'
              # Enforce success-only-once: if any historical success exists, force failed
              ever_success = Transaction.where(home_id: home.id, transaction_id: transaction.transaction_id, status: 'success').exists?
              final_attrs['status'] = ever_success ? 'failed' : candidate_status

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
      pending_home_id = session.delete(:pending_transaction_home_id)

      if pending_id.present?
        transaction = Transaction.find_by(id: pending_id, user_id: current_user.id)

        if transaction.nil?
          current_user.clear_otp!
          respond_to do |format|
            format.html { redirect_to root_path, alert: 'Pending transaction not found or already processed.' }
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
            format.html { redirect_to root_path, alert: 'Unable to find client/home for pending transaction.' }
            format.json { render json: { success: false, error: 'Client or home not found' }, status: :unprocessable_entity }
          end
          return
        end

        # Finalize the pending transaction inside a client lock
        begin
          final_transaction = nil
          client.with_lock do
            # Create a revision (this will mark previous is_latest = false)
            latest_transaction = Transaction.where(home_id: home.id, transaction_id: transaction.transaction_id, is_latest: true).first

            # Build final attributes based on pending transaction snapshot
            final_attrs = transaction.attributes.slice('home_id', 'transaction_id', 'client_id', 'user_id', 'amount', 'interest_rate', 'transaction_cost', 'total_cost',
                                                       'deposit_data')
            # Determine candidate status by balance
            candidate_status = (client.credit || 0) >= transaction.total_cost.to_f ? 'success' : 'failed'
            # Enforce success-only-once: if any historical success exists, force failed
            ever_success = Transaction.where(home_id: home.id, transaction_id: transaction.transaction_id, status: 'success').exists?
            final_attrs['status'] = ever_success ? 'failed' : candidate_status

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
            end

            # Update home's processed_deposits snapshot for this transaction
            deposits = home.processed_deposits.is_a?(Array) ? home.processed_deposits : []
            deposits.each do |d|
              next unless d['transaction_id'] == final_transaction.transaction_id

              d['status'] = final_transaction.status
              d['transaction_cost'] = final_transaction.transaction_cost
              d['applied_interest_rate'] = final_transaction.interest_rate
              d['transaction_processed_at'] = Time.current.iso8601
            end
            home.processed_deposits = deposits
            home.save!
          end

          current_user.clear_otp!

          respond_to do |format|
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
        format.html { redirect_to root_path, notice: 'OTP verified.' }
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
            latest_transaction = Transaction.where(home_id: home.id, transaction_id: transaction.transaction_id, is_latest: true).first
            final_attrs = transaction.attributes.slice('home_id', 'transaction_id', 'client_id', 'user_id', 'amount', 'interest_rate', 'transaction_cost', 'total_cost',
                                                       'deposit_data')
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
        latest_transaction = Transaction.where(home_id: home.id, transaction_id: transaction.transaction_id, is_latest: true).first
        final_attrs = transaction.attributes.slice('home_id', 'transaction_id', 'client_id', 'user_id', 'amount', 'interest_rate', 'transaction_cost', 'total_cost', 'deposit_data')
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
end
