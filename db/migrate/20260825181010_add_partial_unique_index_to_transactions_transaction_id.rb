class AddPartialUniqueIndexToTransactionsTransactionId < ActiveRecord::Migration[8.1]
  def change
    remove_index :transactions, name: 'index_transactions_on_transaction_id_and_is_latest'

    add_index :transactions, :transaction_id,
              unique: true,
              where: 'is_latest = true',
              name: 'index_transactions_on_transaction_id_when_latest'
  end
end
