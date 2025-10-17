class AddUniqueIdToHome < ActiveRecord::Migration[8.0]
  def change
    add_column :homes, :unique_id, :string
  end
end
