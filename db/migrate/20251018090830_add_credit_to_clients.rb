class AddCreditToClients < ActiveRecord::Migration[8.0]
  def change
    add_column :clients, :credit, :float
  end
end
