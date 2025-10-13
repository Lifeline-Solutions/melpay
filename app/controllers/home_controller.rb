class HomeController < ApplicationController
  before_action :authenticate_user!
  load_and_authorize_resource except: %i[index new create]
  before_action :set_home, only: %i[show edit update destroy]

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
    @recent_deposits = []
    Home.order(created_at: :desc).limit(20).each do |home|
      result = parse_spreadsheet(home)
      result[:deposits].each do |row|
        @recent_deposits << {
          date: row['date'] || home.created_at,
          description: row['description'] || '',
          amount: row['amount']
        }
      end
    end
    @recent_deposits = @recent_deposits.sort_by do |d|
      d[:date].to_time
    rescue StandardError
      Time.zone.now
    end.reverse.first(5)

    @chart_series = [
      { name: 'Deposits', data: @totals_deposits_over_time }
    ]
  end

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

      (2..spreadsheet.last_row).each do |i|
        row = [header, spreadsheet.row(i)].transpose.to_h
        next unless row['type'] && row['amount']

        case row['type']&.strip&.downcase
        when 'deposit'
          @deposits << row
        end
      end
      # Number/count the deposits
      @deposits.each do |deposit|
        deposit['count'] = @deposits.count(deposit)
      end
      # Total number of deposits in distinct counts, only for type 'deposit'
      @total_deposit_count = @deposits.select { |d| d['type'].to_s.strip.downcase == 'deposit' }
        .map { |d| d['count'].to_i }
        .count

      # Calculate total deposits
      @total_deposits = @deposits.sum { |d| d['amount'].to_f }

      # Get interest rate for client and calculate interest on total deposits
      client = @home.client || current_user.client
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
    params.require(:home).permit(:name, :document, :client_id, :user_id)
  end
end
