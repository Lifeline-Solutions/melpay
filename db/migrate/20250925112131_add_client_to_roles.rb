class AddClientToRoles < ActiveRecord::Migration[8.0]
  def change
    add_reference :roles, :client, null: true, foreign_key: true, type: :uuid
  end
end
