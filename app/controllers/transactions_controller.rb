class TransactionsController < ApplicationController
  before_action :authenticate_user!
  load_and_authorize_resource

  def index
    @per_page = 20
    @page = (params[:page] || 1).to_i
    @page = 1 if @page < 1

    scope = Transaction.accessible_by(current_ability).order(created_at: :desc)
    scope = scope.where(client_id: current_user.client_id) unless current_user.has_role?(:super_admin)

    scope = apply_transaction_search(scope, params[:search]) if params[:search].present?

    @total_count = scope.count
    @total_pages = [(@total_count / @per_page.to_f).ceil, 1].max

    # If the current page is now out of range (e.g. a search narrowed the
    # results while on page 5), clamp back into range instead of returning empty.
    @page = @total_pages if @page > @total_pages

    @transactions = scope.offset((@page - 1) * @per_page).limit(@per_page)
  end

  def new
    # authorize! :create, Transaction is handled by load_and_authorize_resource
    @transaction = Transaction.new
  end

  def create
    @transaction = Transaction.new(transactions_params)

    # Set client_id for non-super admins based on ability rules
    @transaction.client_id = current_user.client_id unless current_user.has_role?(:super_admin)

    # For account managers, set user_id to their own ID
    @transaction.user_id = current_user.id if current_user.has_role?(:account_manager)

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
    params.require(:transaction).permit(:status, :amount, :transaction_cost, :total_cost, :interest_rate, :transaction_id, :home_id, :user_id, :client_id)
  end

  def transactions_list
    @transactions = Transaction.accessible_by(current_ability).order(created_at: :desc)
  end

  def apply_transaction_search(scope, term)
    sanitized = term.to_s.strip
    return scope if sanitized.blank?

    table = Transaction.arel_table
    quoted = "%#{sanitized.downcase}%"

    searchable_columns = %w[
      status amount transaction_cost total_cost interest_rate
      transaction_id home_id user_id client_id
      created_at updated_at
    ]

    conditions = searchable_columns.map do |col|
      "CAST(#{table.name}.#{ActiveRecord::Base.connection.quote_column_name(col)} AS TEXT) ILIKE :q"
    end

    scope.where(conditions.join(' OR '), q: quoted)
  end
end
