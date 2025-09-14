class UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user, only: [:edit, :update]
  def index
    @users = User.all

    # Pagination setup
    @per_page = 20
    @page = (params[:page] || 1).to_i

    @total_count = @users.count
    @total_pages = (@total_count / @per_page.to_f).ceil
    @start_count = ((@page - 1) * @per_page) + 1
    @end_count   = [@page * @per_page, @total_count].min

    # Paginate
    @users = @users.offset((@page - 1) * @per_page).limit(@per_page)
  end

  def show
    @user = User.find(params[:id])
  end

  def edit
  end

  def update
    if @user.update(user_params)
      redirect_to @user, notice: "Profile updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def user_params
    params.require(:user).permit(:first_name, :last_name, :phone_number, :email)
  end

  private

  def set_user
    @user = current_user
  end
end
