class AddCommissionTypeToSystemSettingsAndClients < ActiveRecord::Migration[8.1]
  def change
    # Add columns to the system_settings table
    add_column :system_settings, :commission_type, :string, default: 'percentage'
    add_column :system_settings, :fixed_commission_amount, :decimal, precision: 10, scale: 2
    
    # Add columns to the clients table
    add_column :clients, :commission_type, :string
    add_column :clients, :fixed_commission_amount, :decimal, precision: 10, scale: 2
    
    # Add columns to the transactions table to store what was actually used
    add_column :transactions, :applied_commission_type, :string
    add_column :transactions, :applied_commission_value, :decimal, precision: 10, scale: 2
  end
end
