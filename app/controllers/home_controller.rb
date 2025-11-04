class HomeController < ApplicationController
  include ActionView::Helpers::NumberHelper

  # require both normal Devise authentication and completion of 2FA
  before_action :authenticate_user!, :require_2fa
  load_and_authorize_resource except: %i[index new create]
  # Ensure @home is set for show/edit/update/destroy and payment actions
  before_action :set_home, only: %i[show edit update destroy pay_single_deposit pay_all_deposits]

  def index
    homes_for_list = Home.all.order(created_at: :desc)
    @accounts_count = Account.count
    @account_types = Account.distinct.pluck(:account_type)

    @per_page = 20
    @page = (params[:page] || 1).to_i
    @total_count = homes_for_list.count
    @total_pages = (@total_count / @per_page.to_f).ceil
    @start_count = ((@page - 1) * @per_page) + 1
    @end_count = [@page * @per_page, @total_count].min

    @homes = homes_for_list.offset((@page - 1) * @per_page).limit(@per_page)

    # Prepare hashes for per-home data
    @totals_deposits = Hash.new(0)
    @total_deposit_count = Hash.new(0)
    @successful_transactions_count = Hash.new(0)
    @deposit_interest = Hash.new(0)
    totals_deposits_over_time = Hash.new(0)

    # Prepare hashes for money in (credits) and money out (transaction costs) over time
    credits_over_time = Hash.new(0)
    transaction_costs_over_time = Hash.new(0)

    # Initialize success and failed transaction counts
    @success_count = Transaction.where(status: 'success').count
    @failed_count = Transaction.where(status: 'failed').count

    # Helper for spreadsheet parsing
    def parse_spreadsheet(home)
      return { deposits: [], deposit_sum: 0, deposit_count: 0, interest: 0 } unless home.document.attached?

      Tempfile.create(['uploaded_file', ".#{home.document.filename.extension}"]) do |tempfile|
        content = home.document.download.force_encoding('UTF-8')
        tempfile.write(content)
        tempfile.rewind
        spreadsheet = case home.document.filename.extension
                      when 'csv' then Roo::CSV.new(tempfile.path)
                      when 'xls' then Roo::Excel.new(tempfile.path)
                      when 'xlsx' then Roo::Excelx.new(tempfile.path)
                      end
        return { deposits: [], deposit_sum: 0, deposit_count: 0, interest: 0 } unless spreadsheet

        header = spreadsheet.row(1).map(&:to_s)
        deposits = []
        count_key = header.find { |h| h.to_s.strip.downcase == 'count' }
        (2..spreadsheet.last_row).each do |i|
          row = [header, spreadsheet.row(i)].transpose.to_h
          next unless row['type'] && row['amount']

          deposits << row if row['type'].to_s.strip.downcase == 'deposit'
        end
        deposit_sum = deposits.sum { |d| d['amount'].to_f }
        deposit_count = if count_key
                          deposits.map { |d| d[count_key].to_i }.uniq.sum
                        else
                          deposits.size
                        end
        client = home.client
        interest_rate = client&.applied_interest_rate.to_f
        interest = deposit_sum * (interest_rate / 100.0)
        { deposits: deposits, deposit_sum: deposit_sum, deposit_count: deposit_count, interest: interest }
      end
    rescue StandardError
      { deposits: [], deposit_sum: 0, deposit_count: 0, interest: 0 }
    end

    # Compute per-home and per-date totals
    @homes.each do |home|
      result = parse_spreadsheet(home)
      @totals_deposits[home.id] = result[:deposit_sum]
      @total_deposit_count[home.id] = result[:deposit_count]
      @deposit_interest[home.id] = result[:interest]

      # Count successful transactions for this home
      @successful_transactions_count[home.id] = if home.processed_deposits.is_a?(Array)
                                                  home.processed_deposits.count { |d| d['status'].to_s.strip.downcase == 'success' }
                                                else
                                                  0
                                                end

      date = home.created_at.to_date
      totals_deposits_over_time[date] += result[:deposit_sum]

      # Add client credits to credits_over_time
      client = home.client
      credits_over_time[date] += client.credit.to_f if client&.credit
    end

    @total_deposits_sum = @totals_deposits.values.sum.to_f

    # Calculate transaction costs over time from successful transactions
    successful_transactions = Transaction.where(status: 'success', is_latest: true)
    successful_transactions.each do |transaction|
      date = transaction.created_at.to_date
      transaction_costs_over_time[date] += transaction.total_cost.to_f
    end

    # Build time-series for chart
    all_dates = (totals_deposits_over_time.keys + credits_over_time.keys + transaction_costs_over_time.keys).uniq.sort

    if all_dates.empty?
      @totals_deposits_over_time = {}
      @credits_over_time = {}
      @transaction_costs_over_time = {}
    else
      min_date = all_dates.first
      max_date = all_dates.last
      date_range = (min_date..max_date).to_a

      @totals_deposits_over_time = date_range.to_h { |d| [d.strftime('%Y-%m-%d'), totals_deposits_over_time[d].to_f] }
      @credits_over_time = date_range.to_h { |d| [d.strftime('%Y-%m-%d'), credits_over_time[d].to_f] }
      @transaction_costs_over_time = date_range.to_h { |d| [d.strftime('%Y-%m-%d'), transaction_costs_over_time[d].to_f] }
    end

    # Collect recent deposits (limit 5)
    @recent_deposits = Transaction.order(created_at: :desc).limit(5).map do |transaction|
      {
        date: transaction.created_at,
        amount: transaction.amount,
        transaction_id: transaction.transaction_id,
        transaction_cost: transaction.transaction_cost,
        interest_rate: transaction.interest_rate || 0.0,
        total_cost: transaction.total_cost,
        status: transaction.status
      }
    end

    # Chart series with all three metrics (Money in, MOney out, Deposits)
    @chart_series = [
      { name: 'Deposits', data: @totals_deposits_over_time },
      { name: 'Money In (Credits)', data: @credits_over_time },
      { name: 'Money Out (Costs)', data: @transaction_costs_over_time }
    ]
  end

  # Display all transactions that have interest_rate stored (not nil)

  def new
    @home = Home.new
  end

  def create
    @home = current_user.homes.build(home_params)
    @home.user_id = current_user.id
    @home.client_id = current_user.client_id # Ensure client_id is set from user

    respond_to do |format|
      if @home.save
        format.html { redirect_to home_path(@home), notice: 'Home was successfully created.' }
      else
        format.html { render :new, status: :unprocessable_content }
      end
    end
  end

  def show
    @file = @home
    return unless @file.document.attached?

    # Check if this file has already been processed
    if @home.processed_deposits.present? && @home.processed_deposits.is_a?(Array) && @home.processed_deposits.any?
      # Use existing processed deposits with their unique IDs
      @deposits = @home.processed_deposits

      # Calculate totals from stored data
      @total_deposits = @deposits.sum { |d| d['amount'].to_f }
      @total_deposit_count = @deposits.count

      client = @home.client || current_user.client
      interest_rate = client&.applied_interest_rate.to_f
      @deposit_interest = @total_deposits * (interest_rate / 100.0)
      @total_cost = @total_deposits + @deposit_interest

      return
    end

    # Process the file for the first time
    Tempfile.create(['uploaded_file', ".#{@file.document.filename.extension}"]) do |tempfile|
      content = @file.document.download.force_encoding('UTF-8')
      tempfile.write(content)
      tempfile.rewind

      spreadsheet = case @file.document.filename.extension
                    when 'csv' then Roo::CSV.new(tempfile.path)
                    when 'xls' then Roo::Excel.new(tempfile.path)
                    when 'xlsx' then Roo::Excelx.new(tempfile.path)
                    end

      header = spreadsheet.row(1)
      @deposits = []

      # Get client and generate prefix for transaction IDs
      client = @home.client || current_user.client

      (2..spreadsheet.last_row).each do |i|
        row = [header, spreadsheet.row(i)].transpose.to_h
        next unless row['type'] && row['amount'] && row['phone number']

        case row['type']&.strip&.downcase
        when 'deposit'
          @deposits << row
        end
      end

      # Number/count the deposits
      @deposits.each do |deposit|
        deposit['count'] = @deposits.count(deposit)
      end

      # Assign unique transaction IDs to each deposit (progressive across all forms)
      # Get the starting ID number for this batch
      client_initials = if client&.name.present?
                          client.name.split.map { |word| word[0] }.join.upcase
                        else
                          'MALPAY'
                        end

      # Find the highest existing transaction ID number for this client
      max_number = 0
      Home.where(client_id: client&.id).find_each do |home|
        next unless home.processed_deposits.is_a?(Array)

        home.processed_deposits.each do |deposit|
          if deposit['transaction_id'] =~ /^#{client_initials}-(\d+)$/
            number = Regexp.last_match(1).to_i
            max_number = number if number > max_number
          end
        end
      end

      # Assign sequential IDs to each deposit in this batch
      @deposits.each_with_index do |deposit, index|
        next_number = max_number + index + 1
        deposit['transaction_id'] = "#{client_initials}-#{next_number.to_s.rjust(4, '0')}"
      end

      # Save the processed deposits with their unique IDs to prevent re-processing
      @home.update(processed_deposits: @deposits)

      # Total number of deposits in distinct counts, only for type 'deposit'
      @total_deposit_count = @deposits.select { |d| d['type'].to_s.strip.downcase == 'deposit' }
        .map { |d| d['count'].to_i }
        .count

      # Calculate total deposits
      @total_deposits = @deposits.sum { |d| d['amount'].to_f }

      # Get interest rate for client and calculate interest on total deposits
      interest_rate = client&.applied_interest_rate.to_f
      @deposit_interest = @total_deposits * (interest_rate / 100.0)

      # Total cost of the transaction will be the totals deposits + interest
      @total_cost = @total_deposits + @deposit_interest
    end
  rescue StandardError => e
    flash.now[:alert] = "Error processing file: #{e.message}"
    @deposits = []
    @total_deposits = 0
  end

  def edit; end

  def update
    @home.user_id = current_user.id
    respond_to do |format|
      if @home.update(home_params)
        format.html { redirect_to home_path(@home), notice: 'Home was successfully updated.' }
      else
        format.html { render :edit, status: :unprocessable_content }
      end
    end
  end

  # Pay a single deposit transaction
  def pay_single_deposit
    deposit_transaction_id = params[:deposit_transaction_id] || params[:transaction_id] || params.dig(:home, :deposit_transaction_id)

    # Ensure processed_deposits is present and find the deposit
    deposits = @home.processed_deposits.is_a?(Array) ? @home.processed_deposits : []
    deposit = deposits.find { |d| d['transaction_id'] == deposit_transaction_id }

    if deposit.nil?
      respond_to do |format|
        format.html { redirect_to home_path(@home), alert: 'Deposit not found.' }
        format.json { render json: { error: 'Deposit not found' }, status: :not_found }
      end
      return
    end

    # Prevent double-acting on an already-successful transaction (success only)
    existing_success = Transaction.where(home_id: @home.id, transaction_id: deposit_transaction_id, is_latest: true, status: 'success').first
    if existing_success
      respond_to do |format|
        format.html { redirect_to home_path(@home), alert: 'This transaction has already been completed successfully.' }
        format.json { render json: { error: 'Already completed' }, status: :unprocessable_entity }
      end
      return
    end

    # Allow retry if previous is failed, but prevent duplicate OTP triggers for already pending transaction
    existing_pending = Transaction.find_by(home_id: @home.id, transaction_id: deposit_transaction_id, status: 'pending', is_latest: true)
    if existing_pending
      respond_to do |format|
        format.html { redirect_to verify_otp_path, notice: 'OTP already sent. Please enter the code to confirm this payment.' }
        format.json { render json: { pending: true, message: 'OTP already sent to your email.' }, status: :ok }
      end
      return
    end

    client = @home.client || current_user.client
    if client.nil?
      respond_to do |format|
        format.html { redirect_to home_path(@home), alert: 'Client not found for this transaction.' }
        format.json { render json: { error: 'Client not found' }, status: :unprocessable_entity }
      end
      return
    end

    interest_rate = client&.applied_interest_rate.to_f
    deposit_amount = deposit['amount'].to_f

    if client.fixed?
      transaction_cost = client.effective_commission_value.to_f
    else
      interest_rate = client.applied_interest_rate.to_f
      transaction_cost = deposit_amount * (interest_rate / 100.0)
    end

    total_cost = deposit_amount + transaction_cost

    # Create a pending transaction record and trigger 2FA before finalizing
    new_attributes = {
      home_id: @home.id,
      transaction_id: deposit_transaction_id,
      client_id: client&.id,
      user_id: current_user.id,
      amount: deposit_amount,
      interest_rate: interest_rate,
      transaction_cost: transaction_cost,
      applied_commission_type: client.commission_type,
      applied_commission_value: client.fixed_commission_amount,
      total_cost: total_cost,
      deposit_data: deposit,
      status: 'pending'
    }
    begin
      # If there's an existing 'latest' transaction, we'll create a revision placeholder
      latest_transaction = Transaction.where(home_id: @home.id, transaction_id: deposit_transaction_id, is_latest: true).first

      transaction_record = if latest_transaction
                             latest_transaction.create_revision(new_attributes)
                           else
                             Transaction.new(new_attributes)
                           end

      transaction_record.save!
      # Store pending transaction id in session so the 2FA verify step can finalize it
      session[:pending_transaction_id] = transaction_record.id
      session[:pending_transaction_home_id] = @home.id

      # Trigger OTP to user (email and optional SMS)
      current_user.generate_otp!
      UserMailer.with(user: current_user).send_otp.deliver_later
      if current_user.phone_number.present?
        begin
          SmsSender.send_otp(current_user.phone_number, current_user.otp_code)
        rescue StandardError => e
          Rails.logger.warn("Failed to send SMS OTP for transaction #{deposit_transaction_id}: #{e.message}")
        end
      end

      respond_to do |format|
        format.html { redirect_to verify_otp_path, notice: 'OTP sent. Please enter the code to confirm this payment.' }
        format.json { render json: { pending: true, message: 'OTP sent to your email.' }, status: :ok }
      end
    rescue ActiveRecord::RecordInvalid => e
      error_message = e.record&.errors&.full_messages&.join(', ').presence || e.message
      respond_to do |format|
        format.html { redirect_to home_path(@home), alert: "Error creating pending transaction: #{error_message}" }
        format.json { render json: { error: error_message }, status: :unprocessable_entity }
      end
    end
  end

  # Pay all pending deposits at once (now creates pending transactions and requires 2FA to finalize)
  def pay_all_deposits
    params[:status] || 'success'

    client = @home.client || current_user.client
    if client.nil?
      respond_to do |format|
        format.html { redirect_to home_path(@home), alert: 'Client not found for this transaction.' }
        format.json { render json: { error: 'Client not found' }, status: :unprocessable_entity }
      end
      return
    end

    # Use the client's applied interest rate as the baseline (same as single-pay flow)
    interest_rate = client&.applied_interest_rate.to_f

    pending_ids = []
    recorded_count = 0

    @home.processed_deposits.each do |deposit|
      # Skip if already successful (completed transactions cannot be changed)
      existing_success = Transaction.where(
        home_id: @home.id,
        transaction_id: deposit['transaction_id'],
        is_latest: true,
        status: 'success'
      ).first
      next if existing_success

      # Prevent duplicate OTP triggers for already pending transaction
      existing_pending = Transaction.find_by(home_id: @home.id, transaction_id: deposit['transaction_id'], status: 'pending', is_latest: true)
      next if existing_pending

      deposit_amount = deposit['amount'].to_f

      # Compute transaction cost using the exact same logic as pay_single_deposit
      transaction_cost = if client.fixed?
                           client.effective_commission_value.to_f
                         else
                           # keep interest_rate as derived above
                           (deposit_amount * (interest_rate / 100.0)).round(2)
                         end

      total_cost = deposit_amount + transaction_cost

      # Use the same applied_commission fields as pay_single_deposit
      new_attributes = {
        home_id: @home.id,
        transaction_id: deposit['transaction_id'],
        client_id: client&.id,
        user_id: current_user.id,
        amount: deposit_amount,
        interest_rate: interest_rate,
        transaction_cost: transaction_cost,
        applied_commission_type: client.commission_type,
        applied_commission_value: client.fixed_commission_amount,
        total_cost: total_cost,
        deposit_data: deposit,
        status: 'pending'
      }

      begin
        latest_transaction = Transaction.where(home_id: @home.id, transaction_id: deposit['transaction_id'], is_latest: true).first

        transaction = if latest_transaction
                        latest_transaction.create_revision(new_attributes)
                      else
                        Transaction.new(new_attributes)
                      end

        transaction.save!
        pending_ids << transaction.id
        recorded_count += 1

        # update deposit snapshot to pending (store same snapshot fields as single-pay)
        deposit['status'] = 'pending'
        deposit['transaction_cost'] = transaction_cost
        deposit['applied_interest_rate'] = interest_rate
        deposit['applied_commission_type'] = client.commission_type
        deposit['applied_commission_value'] = client.fixed_commission_amount
        deposit['transaction_processed_at'] = Time.current.iso8601
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error "Failed creating pending transaction for #{deposit['transaction_id']}: #{e.record&.errors&.full_messages&.join(', ') || e.message}"
        next
      end
    end

    # persist processed_deposits if we changed them
    if recorded_count.positive?
      @home.processed_deposits = @home.processed_deposits
      @home.save!

      # Store pending transaction ids in session for finalization by 2FA
      session[:pending_transaction_ids] = pending_ids
      session[:pending_transaction_home_id] = @home.id

      # Trigger OTP to user
      current_user.generate_otp!
      UserMailer.with(user: current_user).send_otp.deliver_later
      if current_user.phone_number.present?
        begin
          SmsSender.send_otp(current_user.phone_number, current_user.otp_code)
        rescue StandardError => e
          Rails.logger.warn("Failed to send SMS OTP for batch: #{e.message}")
        end
      end

      respond_to do |format|
        format.html { redirect_to verify_otp_path, notice: "OTP sent to confirm processing of #{recorded_count} transactions." }
        format.json { render json: { pending: true, count: recorded_count, message: 'OTP sent to your email.' }, status: :ok }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace('twofa-modal', partial: 'home/twofa_modal', locals: { pending_type: 'batch', transaction_id: nil, count: recorded_count })
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to home_path(@home), alert: 'No transactions available to process.' }
        format.json { render json: { error: 'No transactions available' }, status: :unprocessable_entity }
        format.turbo_stream { render turbo_stream: turbo_stream.replace('twofa-modal', partial: 'home/twofa_modal_error', locals: { error: 'No transactions available' }) }
      end
    end
  end

  def destroy
    @home.destroy
    respond_to do |format|
      format.html { redirect_to root_path, notice: 'Home was successfully deleted.' }
    rescue ActiveRecord::RecordNotFound
      format.html { redirect_to root_path, alert: 'Home not found.' }
    end
  end

  private

  def set_home
    @home = Home.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: 'Home not found.'
  end

  def home_params
    params.require(:home).permit(:name, :credit, :document, :client_id, :user_id, :unique_id)
  end
end
