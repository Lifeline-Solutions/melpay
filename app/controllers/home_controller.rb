class HomeController < ApplicationController
  include ActionView::Helpers::NumberHelper

  before_action :authenticate_user!
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
    @deposit_interest = Hash.new(0)
    totals_deposits_over_time = Hash.new(0)

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
      date = home.created_at.to_date
      totals_deposits_over_time[date] += result[:deposit_sum]
    end

    @total_deposits_sum = @totals_deposits.values.sum.to_f

    # Build time-series for chart
    all_dates = totals_deposits_over_time.keys.uniq.sort
    if all_dates.empty?
      @totals_deposits_over_time = {}
    else
      min_date = all_dates.first
      max_date = all_dates.last
      date_range = (min_date..max_date).to_a
      @totals_deposits_over_time = date_range.to_h { |d| [d.strftime('%Y-%m-%d'), totals_deposits_over_time[d].to_f] }
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

    @chart_series = [
      { name: 'Deposits', data: @totals_deposits_over_time }
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
      redirect_to home_path(@home), alert: 'Deposit not found.'
      return
    end

    # Prevent double-acting on an already-successful persisted Transaction
    existing_transaction = Transaction.find_by(home_id: @home.id, transaction_id: deposit_transaction_id, status: 'success', is_latest: true)
    if existing_transaction
      redirect_to home_path(@home), alert: 'This transaction has already been completed successfully.'
      return
    end

    latest_transaction = Transaction.where(home_id: @home.id, transaction_id: deposit_transaction_id, is_latest: true).first

    client = @home.client || current_user.client
    if client.nil?
      redirect_to home_path(@home), alert: 'Client not found for this transaction.'
      return
    end

    interest_rate = client&.applied_interest_rate.to_f
    deposit_amount = deposit['amount'].to_f
    transaction_cost = deposit_amount * (interest_rate / 100.0)
    total_cost = deposit_amount + transaction_cost

    # Decide requested status and compute final status based on available credit
    requested_status = params[:status].presence || 'success'
    can_pay = requested_status == 'success' && (client.credit || 0) >= total_cost
    final_status = can_pay ? 'success' : 'failed'

    new_attributes = {
      home_id: @home.id,
      transaction_id: deposit_transaction_id,
      client_id: client&.id,
      user_id: current_user.id,
      amount: deposit_amount,
      interest_rate: interest_rate,
      transaction_cost: transaction_cost,
      total_cost: total_cost,
      deposit_data: deposit,
      status: final_status
    }

    transaction_record = nil
    begin
      client.with_lock do
        # Create revision or new transaction while home row is locked
        if latest_transaction
          transaction_record = latest_transaction.create_revision(new_attributes)
          Rails.logger.info "Creating revision for transaction #{deposit_transaction_id}. Previous version ID: #{latest_transaction.id}"
        else
          transaction_record = Transaction.new(new_attributes)
          Rails.logger.info "Creating new transaction #{deposit_transaction_id}"
        end

        # Save transaction, raise if validation fails to rollback
        transaction_record.save!

        # If success, subtract total_cost from client.credit (do NOT allow negative)
        if transaction_record.status == 'success'
          # Double-check available balance (race-safety): raise if not enough
          raise ActiveRecord::RecordInvalid, transaction_record if (client.credit || 0) < total_cost

          client.credit = (client.credit || 0) - total_cost
          client.save!
        end

        # Update the deposit status in processed_deposits and persist snapshot values
        deposits.each do |d|
          next unless d['transaction_id'] == deposit_transaction_id

          d['status'] = transaction_record.status
          # Persist snapshot values at the time of transaction
          d['transaction_cost'] = transaction_cost
          d['applied_interest_rate'] = interest_rate
          d['transaction_processed_at'] = Time.current.iso8601
        end
        @home.processed_deposits = deposits
        @home.save!
      end
    rescue ActiveRecord::RecordInvalid => e
      error_message = e.record&.errors&.full_messages&.join(', ').presence || e.message
      redirect_to home_path(@home), alert: "Error: #{error_message}"
      return
    end

    # At this point transaction_record is persisted
    if transaction_record.status == 'success'
      redirect_to home_path(@home), notice: "Payment completed successfully! Transaction ID: #{deposit_transaction_id}"
    else
      redirect_to home_path(@home), alert: "Payment failed and has been recorded. Transaction ID: #{deposit_transaction_id}"
    end
  end

  # Pay all pending deposits at once
  def pay_all_deposits
    status = params[:status] || 'success'
    success_count = 0
    failed_count = 0
    recorded_count = 0
    revised_count = 0

    client = @home.client || current_user.client
    if client.nil?
      redirect_to home_path(@home), alert: 'Client not found for this transaction.'
      return
    end

    interest_rate = client&.applied_interest_rate.to_f

    @home.processed_deposits.each do |deposit|
      # Skip if already successful (completed transactions cannot be changed)
      existing_transaction = Transaction.find_by(
        home_id: @home.id,
        transaction_id: deposit['transaction_id'],
        status: 'success',
        is_latest: true
      )

      if existing_transaction
        Rails.logger.info "Skipping already successful transaction: #{deposit['transaction_id']}"
        next
      end

      # Find the latest version of this transaction (if any)
      latest_transaction = Transaction.where(
        home_id: @home.id,
        transaction_id: deposit['transaction_id'],
        is_latest: true
      ).first

      deposit_amount = deposit['amount'].to_f
      transaction_cost = deposit_amount * (interest_rate / 100.0)

      new_attributes = {
        home_id: @home.id,
        transaction_id: deposit['transaction_id'],
        client_id: client&.id,
        user_id: current_user.id,
        amount: deposit_amount,
        interest_rate: interest_rate,
        transaction_cost: transaction_cost,
        total_cost: deposit_amount + transaction_cost,
        deposit_data: deposit,
        status: status
      }

      # Decide final status based on remaining credit: process those we can pay, record failed for others
      can_pay = status == 'success' && (client.credit || 0) >= new_attributes[:total_cost]
      final_status = can_pay ? 'success' : 'failed'
      new_attributes[:status] = final_status

      is_revision = false
      begin
        # Use a row lock on client so checking and subtracting credit is atomic per-deposit
        client.with_lock do
          if latest_transaction
            transaction = latest_transaction.create_revision(new_attributes)
            is_revision = true
          else
            transaction = Transaction.new(new_attributes)
            is_revision = false
          end

          transaction.save!

          if transaction.status == 'success'
            # subtract cost (we already checked can_pay)
            client.credit = (client.credit || 0) - transaction.total_cost
            client.save!
          end

          # update deposit status and persist snapshot values
          deposit['status'] = transaction.status
          deposit['transaction_cost'] = transaction_cost
          deposit['applied_interest_rate'] = interest_rate
          deposit['transaction_processed_at'] = Time.current.iso8601
        end

        recorded_count += 1
        revised_count += 1 if is_revision
        if final_status == 'success'
          success_count += 1
        else
          failed_count += 1
        end

        Rails.logger.info "#{is_revision ? 'Revised' : 'Recorded'} transaction #{deposit['transaction_id']} with status: #{final_status}"
      rescue ActiveRecord::RecordInvalid => e
        error_message = e.record&.errors&.full_messages&.join(', ').presence || e.message
        Rails.logger.error "Error #{deposit['transaction_id']}: #{error_message}"
      end
    end

    # persist processed_deposits and ensure home saved
    @home.processed_deposits = @home.processed_deposits
    @home.save if recorded_count.positive?

    message = "Processed #{recorded_count} transactions"
    message += " (#{revised_count} revisions)" if revised_count.positive?
    message += ": #{success_count} successful" if success_count.positive?
    message += ", #{failed_count} failed" if failed_count.positive?

    redirect_to home_path(@home), notice: message
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
