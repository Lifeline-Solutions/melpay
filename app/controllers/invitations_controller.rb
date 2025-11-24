class InvitationsController < Devise::InvitationsController
  before_action :authenticate_user!
  before_action :authorize_invitation, only: %i[new create]

  def new
    @user = User.new
    self.resource = @user
    @resource_name = :user
  end

  def create
    # Check if the email is blank
    if invite_params[:email].blank?
      flash.now[:alert] = 'Email cannot be blank.'
      render :new
      return
    end

    # Check if a user with the same details already exists
    existing_user = User.find_by(
      email: invite_params[:email],
      first_name: invite_params[:first_name],
      last_name: invite_params[:last_name],
      client_id: invite_params[:client_id]
    )

    if existing_user
      flash[:alert] = 'User already exists.'
      redirect_to new_user_invitation_path
    else
      invited_user = nil
      User.invite!(invite_params, current_user) do |u|
        assign_role(u)
        invited_user = u
      end

      if invited_user.present? && invited_user.errors.blank?
        redirect_to users_path, notice: 'User has been invited successfully.'
      else
        flash[:alert] = 'There was an error inviting the user.'
        redirect_to new_user_invitation_path
      end
    end
  end

  private

  def authorize_invitation
    authorize! :invite, User
  end

  def invite_params
    params.require(:user).permit(:email, :first_name, :last_name, :client_id, roles: [])
  end

  def assign_role(user)
    return unless params[:role].present?

    role = params[:role]

    if current_user.has_role?(:admin)
      user.add_role(role)
    elsif current_user.has_role?(:project_manager)
      user.add_role(role) unless role == 'admin'
    else
      user.add_role(role) unless %w[admin project_manager].include?(role)
    end
  end
end
