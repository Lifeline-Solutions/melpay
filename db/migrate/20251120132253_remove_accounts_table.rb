class RemoveAccountsTable < ActiveRecord::Migration[8.1]
  def up
    # Remove foreign key constraints first
    remove_foreign_key :accounts, :clients if foreign_key_exists?(:accounts, :clients)
    
    # Remove the table
    drop_table :accounts
  end

  def down
    create_table "accounts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
      t.string "account_number"
      t.string "account_type"
      t.decimal "balance"
      t.uuid "client_id", null: false
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.index ["client_id"], name: "index_accounts_on_client_id"
    end

    add_foreign_key "accounts", "clients"
  end
end
