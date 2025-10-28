class AddInterestRateToTransactions < ActiveRecord::Migration[8.0]
  def change
    add_column :transactions, :interest_rate, :float
  end
end
