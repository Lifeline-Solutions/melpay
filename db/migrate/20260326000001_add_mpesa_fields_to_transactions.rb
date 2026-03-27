class AddMpesaFieldsToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :mpesa_conversation_id, :string
    add_column :transactions, :mpesa_originator_conversation_id, :string
    add_column :transactions, :mpesa_result_code, :integer
    add_column :transactions, :mpesa_result_desc, :string
    add_column :transactions, :mpesa_transaction_receipt, :string

    add_index :transactions, :mpesa_conversation_id
    add_index :transactions, :mpesa_originator_conversation_id
  end
end
