class ClientsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_client, only: %i[show edit update approve_kyc reject_kyc]

  def index
    @clients = Client.all
    # Pagination setup
    @per_page = 20
    @page = (params[:page] || 1).to_i

    @total_count = @clients.count
    @total_pages = (@total_count / @per_page.to_f).ceil
    @start_count = ((@page - 1) * @per_page) + 1
    @end_count = [@page * @per_page, @total_count].min

    # Paginate
    @clients = @clients.offset((@page - 1) * @per_page).limit(@per_page)
  end

  def show
    @client_accounts = @client.accounts
  end

  def new
    @client = Client.new
  end

  def create
    @client = Client.new(client_params)
    if @client.save
      redirect_to @client, notice: 'Client created successfully. KYC status is pending.'
    else
      render :new
    end
  end

  def edit; end

  def update
    if @client.update(client_params)
      redirect_to @client, notice: 'Client updated.'
    else
      render :edit
    end
  end

  def approve_kyc
    @client.update(kyc_status: 'approved', kyc_verified_at: Time.current)
    redirect_to @client, notice: 'KYC approved.'
  end

  def reject_kyc
    @client.update(kyc_status: 'rejected')
    redirect_to @client, alert: "Client '#{@client}' KYC rejected."
  end

  private

  def set_client
    @client = Client.find(params[:id])
  end

  def client_params
    params.require(:client).permit(:name, :email, :phone)
  end
end
