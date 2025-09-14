class UsersController < ApplicationController
  before_action :authenticate_user!
  def index
    @per_page = 10
    @page = (params[:page] || 1).to_i

    @users = if params[:query].present?
               User.left_joins(:client, :roles)
                 .where('users.email ILIKE :query OR users.first_name ILIKE :query OR
                         users.last_name ILIKE :query OR clients.name ILIKE :query OR roles.name ILIKE :query',
                        query: "%#{params[:query]}%").distinct
             else
               User.order('created_at DESC').distinct
             end
    @total_pages = (@users.count / @per_page.to_f).ceil
    @users = @users.offset((@page - 1) * @per_page).limit(@per_page)
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:first_name, :last_name, :client_id, role_ids: [])
  end

  def filtered_user_params
    if current_user.has_role?(:admin)
      user_params
    else
      user_params.tap do |params|
        if params[:role_ids].present? && (admin_role = Role.find_by(name: 'admin'))
          params[:role_ids] -= [admin_role.id.to_s]
        end
      end
    end
  end
end
