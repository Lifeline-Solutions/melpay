class TransactionsController < ApplicationController
  before_action :authenticate_user!

  def index
    @per_page = 20
    @page = (params[:page] || 1).to_i
    @page = 1 if @page < 1

    scope = Transaction.order(created_at: :desc)
    @total_count = scope.count
    @total_pages = (@total_count / @per_page.to_f).ceil

    @transactions = scope.offset((@page - 1) * @per_page).limit(@per_page)
    # Now @transactions contains at most 20 records; use @page/@total_pages for nav
  end

  def new
    @transaction = Transaction.new
  end

  def create
    @transaction = Transaction.new(transactions_params)
    respond_to do |format|
      if @transaction.save
        format.html { redirect_to transactions_path, notice: 'Transaction was successfully created.' }
      else
        format.html { render :new, status: :unprocessable_content }
      end
    end
  end

  private

  def set_transaction
    @transaction = Transaction.find(params[:id])
  end

  def transactions_params
    params.require(:transaction).permit(:status)
  end

  def transactions_list
    @transactions = Transaction.order(created_at: :desc)
  end
end
