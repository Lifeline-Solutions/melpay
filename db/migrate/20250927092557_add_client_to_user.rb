class AddClientToUser < ActiveRecord::Migration[8.0]
  def change
    add_reference :users, :client, null: true, foreign_key: true, type: :uuid
  end
end
