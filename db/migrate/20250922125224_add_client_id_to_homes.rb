class AddClientIdToHomes < ActiveRecord::Migration[8.0]
  def change
    add_reference :homes, :client, null: true, foreign_key: true, type: :uuid

  end
end
