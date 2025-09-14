class RolesController < ApplicationController
  before_action :authenticate_user!
  def index
    @roles = Role.all
  end

  def new
    @role = Role.new
  end

  def create
    @role = Role.new(role_params)
    respond_to do |format|
      if @role.save
        format.html { redirect_to home_index_path, notice: 'Role was successfully created.' }
      else
        format.html { render :new, status: :unprocessable_content }
      end
    end
  end

  private

  def role_params
    params.require(:role).permit(:name)
  end
end
