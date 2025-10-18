class AddCreditToHomes < ActiveRecord::Migration[8.0]
  def change
    add_column :homes, :credit, :float
  end
end
