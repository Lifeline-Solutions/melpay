class TransactionsController < ApplicationController
  before_action :authenticate_user!
  def index; end

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
end
