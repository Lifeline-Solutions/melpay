class AddCustomInterestRateToClients < ActiveRecord::Migration[8.0]
  def change
    add_column :clients, :custom_interest_rate, :decimal, precision: 5, scale: 2
  end
end
