class AddAuditFieldsToVersions < ActiveRecord::Migration[8.1]
  def change
    add_column :versions, :ip, :string
    add_column :versions, :user_agent, :string
    add_column :versions, :request_id, :string
    add_column :versions, :whodunnit_uuid, :uuid
  end
end
