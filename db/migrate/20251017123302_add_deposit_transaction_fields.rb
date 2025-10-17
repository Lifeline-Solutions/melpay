class AddDepositTransactionFields < ActiveRecord::Migration[8.0]
  def change
    add_column :transactions, :home_id, :uuid
    add_column :transactions, :client_id, :uuid
    add_column :transactions, :user_id, :uuid
    add_column :transactions, :transaction_id, :string
    add_column :transactions, :amount, :decimal, precision: 10, scale: 2
    add_column :transactions, :transaction_cost, :decimal, precision: 10, scale: 2
    add_column :transactions, :total_cost, :decimal, precision: 10, scale: 2
    add_column :transactions, :deposit_data, :jsonb, default: {}

    add_index :transactions, :home_id
    add_index :transactions, :client_id
    add_index :transactions, :user_id
    add_index :transactions, :transaction_id
  end
end
