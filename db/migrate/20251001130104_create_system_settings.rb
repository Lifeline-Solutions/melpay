class CreateSystemSettings < ActiveRecord::Migration[8.0]
  def change
    create_table "system_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
      t.decimal "global_interest_rate", precision: 5, scale: 2, default: 2.0, null: false
      t.timestamps
    end
  end
end
