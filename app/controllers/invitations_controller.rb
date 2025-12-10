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
    params.require(:user).permit(:email, :first_name, :last_name, :client_id)
  end

  def assign_role(user)
    # Get the role from the select_tag :role parameter (root level, not nested under user)
    role = params[:role]

    if role.present?
      # Only super_admin can assign super_admin role
      if role == 'super_admin'
        if current_user.has_role?(:super_admin)
          user.add_role(role)
        else
          # Downgrade to admin if current user doesn't have permission
          user.add_role(:admin)
          Rails.logger.warn "User #{current_user.email} attempted to assign super_admin role without permission"
        end
      # Admin can assign admin, auditor, and account_manager roles
      elsif current_user.has_role?(:admin) || current_user.has_role?(:super_admin)
        user.add_role(role)
      else
        # Default to account_manager if user doesn't have permission for other roles
        user.add_role(:account_manager)
        Rails.logger.warn "User #{current_user.email} attempted to assign #{role} role without permission"
      end
    else
      # Assign a default role if none is selected
      user.add_role(:account_manager)
    end
  end
end
