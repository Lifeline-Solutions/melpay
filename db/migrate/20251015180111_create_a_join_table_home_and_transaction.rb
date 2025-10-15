class CreateAJoinTableHomeAndTransaction < ActiveRecord::Migration[8.0]
  def change
    create_join_table :homes, :transactions do |t|
      t.references :homes, null: false, foreign_key: true, type: :uuid
      t.references :transactions, null: false, foreign_key: true, type: :uuid
      t.timestamps
    end
  end
end
