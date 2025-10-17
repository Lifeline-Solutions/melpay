class AddProcessedDepositsToHomes < ActiveRecord::Migration[8.0]
  def change
    add_column :homes, :processed_deposits, :jsonb, default: []
  end
end

