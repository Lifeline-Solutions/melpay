class RolesController < ApplicationController
  before_action :authenticate_user!
  def new
    @role = Role.new
  end

  def create
    @role = Role.new(role_params)
    if @role.save
      redirect_to home_index_path, notice: 'Role was successfully created.'
    else
      render :new
    end
  end

  private

  def role_params
    params.require(:role).permit(:name)
  end
end
