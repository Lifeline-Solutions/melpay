class AddPreviousTransactionIdToTransactions < ActiveRecord::Migration[8.0]
  def change
    add_column :transactions, :previous_transaction_id, :uuid
    add_column :transactions, :is_latest, :boolean, default: true
    add_index :transactions, :previous_transaction_id
    add_index :transactions, [:transaction_id, :is_latest]
  end
end
