class AddUserPassToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :user_pass, :string
    add_index :users, :user_pass, unique: true
  end
end

