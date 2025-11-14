class CreateLoginEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :login_events, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :ip
      t.string :user_agent
      t.string :session_id

      t.timestamps
    end
  end
end
