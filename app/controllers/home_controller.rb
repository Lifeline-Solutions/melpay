class HomeController < ApplicationController
  before_action :authenticate_user!
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
    # Ensure per-home totals are always present for the view table
    @totals_deposits = Hash.new(0)
    @totals_credits = Hash.new(0)
    @totals_returns = Hash.new(0)
    # Prepare time-series totals (for the chart)
    totals_deposits_over_time = Hash.new(0) # local until we build final @hash
    totals_credits_over_time = Hash.new(0)
    totals_returns_over_time = Hash.new(0)
    # parse_amount helper: strip currency chars and convert to float
    parse_amount = lambda do |value|
      value.to_s.gsub(/[^\d.-]/, '').to_f
    end

    # Compute per-home totals (for table) and per-date totals (for chart)
    Home.order(created_at: :asc).find_each do |home|
      # skip homes with no attached spreadsheet
      next unless home.document.attached?

      begin
        Tempfile.create(['uploaded_file', ".#{home.document.filename.extension}"]) do |tempfile|
          content = home.document.download
          content = content.force_encoding('UTF-8') if content.respond_to?(:force_encoding)
          tempfile.binmode
          tempfile.write(content)
          tempfile.rewind

          spreadsheet = case home.document.filename.extension&.downcase
                        when 'csv' then Roo::CSV.new(tempfile.path)
                        when 'xls' then Roo::Excel.new(tempfile.path)
                        when 'xlsx' then Roo::Excelx.new(tempfile.path)
                        end
          next unless spreadsheet

          header = begin
            spreadsheet.row(1).map { |h| h.to_s.strip }
          rescue StandardError
            []
          end
          deposits = []
          credits = []
          returns = []

          # protect against files with fewer rows
          last_row = [spreadsheet.last_row || 1, 1].max

          (2..last_row).each do |i|
            raw_row = spreadsheet.row(i)
            next if raw_row.nil?

            # build a hash mapping header -> value
            row = [header, raw_row].transpose.to_h.transform_keys(&:to_s)
            type = row['type'] || row['Type'] || row[:type]
            amount = row['amount'] || row['Amount'] || row[:amount]
            next unless type && amount

            case type.to_s.strip.downcase
            when 'deposit'
              deposits << parse_amount.call(amount)
            when 'credit'
              credits << parse_amount.call(amount)
            when 'return'
              returns << parse_amount.call(amount)
            end
          end

          # per-home totals (used in the table)
          deposit_sum = deposits.sum.to_f
          credit_sum = credits.sum.to_f
          return_sum = returns.sum.to_f

          @totals_deposits[home.id] = deposit_sum
          @totals_credits[home.id] = credit_sum
          @totals_returns[home.id] = return_sum

          # accumulate per-date totals (chart)
          date = home.created_at.to_date
          totals_deposits_over_time[date] += deposit_sum
          totals_credits_over_time[date] += credit_sum
          totals_returns_over_time[date] += return_sum
        end
      rescue StandardError => e
        Rails.logger.warn("Failed to parse Home##{home.id} spreadsheet: #{e.message}")
        # Ensure the per-home keys exist so view won't blow up
        @totals_deposits[home.id] ||= 0
        @totals_credits[home.id] ||= 0
        @totals_returns[home.id] ||= 0
        next
      end
    end

    # ------------------------------------------------------------------
    # Final totals for quick summary (optional)
    # ------------------------------------------------------------------
    @total_deposits_sum = @totals_deposits.values.sum.to_f
    @total_credits_sum = @totals_credits.values.sum.to_f
    @total_returns_sum = @totals_returns.values.sum.to_f

    # ------------------------------------------------------------------
    # Build final, ordered time-series and fill missing dates with zeros
    # ------------------------------------------------------------------
    all_dates = (totals_deposits_over_time.keys + totals_credits_over_time.keys + totals_returns_over_time.keys).uniq.sort

    if all_dates.empty?
      @totals_deposits_over_time = {}
      @totals_credits_over_time = {}
      @totals_returns_over_time = {}
    else
      min_date = all_dates.first
      max_date = all_dates.last
      date_range = (min_date..max_date).to_a

      # Chartkick works with date strings (ISO) or actual Date objects; we use ISO strings
      @totals_deposits_over_time = date_range.to_h { |d| [d.strftime('%Y-%m-%d'), totals_deposits_over_time[d].to_f] }
      @totals_credits_over_time = date_range.to_h { |d| [d.strftime('%Y-%m-%d'), totals_credits_over_time[d].to_f] }
      @totals_returns_over_time = date_range.to_h { |d| [d.strftime('%Y-%m-%d'), totals_returns_over_time[d].to_f] }
    end

    # Collect all deposits across homes for recent list
    @recent_deposits = []

    Home.order(created_at: :desc).limit(20).each do |home| # check recent homes first
      next unless home.document.attached?
      begin
        Tempfile.create(['uploaded_file', ".#{home.document.filename.extension}"]) do |tempfile|
          content = home.document.download.force_encoding('UTF-8')
          tempfile.write(content)
          tempfile.rewind

          spreadsheet = case home.document.filename.extension
                        when 'csv' then Roo::CSV.new(tempfile.path)
                        when 'xls' then Roo::Excel.new(tempfile.path)
                        when 'xlsx' then Roo::Excelx.new(tempfile.path)
                        end
          next unless spreadsheet

          header = spreadsheet.row(1).map(&:to_s)
          (2..spreadsheet.last_row).each do |i|
            row = [header, spreadsheet.row(i)].transpose.to_h
            next unless row['type'] && row['amount']

            if row['type'].to_s.strip.downcase == 'deposit'
              @recent_deposits << {
                date: row['date'] || home.created_at,
                description: row['description'] || "",
                amount: row['amount']
              }
            end
          end
        end
      rescue
        next
      end
    end

    # Sort deposits by date (most recent first) and limit to 5
    @recent_deposits = @recent_deposits.sort_by { |d| d[:date].to_time rescue Time.zone.now }.reverse.first(5)

    # series ready for Chartkick
    @chart_series = [
      { name: 'Deposits', data: @totals_deposits_over_time },
      { name: 'Credits', data: @totals_credits_over_time },
      { name: 'Returns', data: @totals_returns_over_time }
    ]
  end

  def new
    @home = Home.new
  end

  def create
    @home = current_user.homes.build(home_params)

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
      @credits = []
      @returns = []

      (2..spreadsheet.last_row).each do |i|
        row = [header, spreadsheet.row(i)].transpose.to_h
        next unless row['type'] && row['amount']

        case row['type']&.strip&.downcase
        when 'deposit'
          @deposits << row
        when 'credit'
          @credits << row
        when 'return'
          @returns << row
        end
      end

      @total_deposits = @deposits.sum { |d| d['amount'].to_f }
      @total_credits = @credits.sum { |c| c['amount'].to_f }
      @total_returns = @returns.sum { |r| r['amount'].to_f }
    end
  rescue StandardError => e
    flash.now[:alert] = "Error processing file: #{e.message}"
    @deposits = []
    @credits = []
    @returns = []
    @total_deposits = 0
    @total_credits = 0
    @total_returns = 0
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
    params.require(:home).permit(:name, :document)
  end
end
