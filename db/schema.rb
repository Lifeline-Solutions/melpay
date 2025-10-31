# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2025_10_28_135417) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accounts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "account_number"
    t.string "account_type"
    t.decimal "balance"
    t.uuid "client_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_accounts_on_client_id"
  end

  create_table "active_storage_attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.uuid "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "clients", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.float "credit"
    t.decimal "custom_interest_rate", precision: 5, scale: 2
    t.string "email"
    t.string "kyc_reference_id"
    t.string "kyc_status"
    t.datetime "kyc_verified_at"
    t.string "name"
    t.string "phone"
    t.datetime "updated_at", null: false
  end

  create_table "homes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "client_id", null: false
    t.datetime "created_at", null: false
    t.string "name"
    t.jsonb "processed_deposits", default: []
    t.string "unique_id"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["client_id"], name: "index_homes_on_client_id"
    t.index ["user_id"], name: "index_homes_on_user_id"
  end

  create_table "homes_transactions", id: false, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "home_id", null: false
    t.uuid "homes_id", null: false
    t.bigint "transaction_id", null: false
    t.uuid "transactions_id", null: false
    t.datetime "updated_at", null: false
    t.index ["homes_id"], name: "index_homes_transactions_on_homes_id"
    t.index ["transactions_id"], name: "index_homes_transactions_on_transactions_id"
  end

  create_table "roles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.uuid "resource_id"
    t.string "resource_type"
    t.datetime "updated_at", null: false
    t.index ["name", "resource_type", "resource_id"], name: "index_roles_on_name_and_resource_type_and_resource_id"
    t.index ["resource_type", "resource_id"], name: "index_roles_on_resource"
  end

  create_table "system_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "global_interest_rate", precision: 5, scale: 2, default: "2.0", null: false
    t.datetime "updated_at", null: false
  end

  create_table "transactions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2
    t.uuid "client_id"
    t.datetime "created_at", null: false
    t.jsonb "deposit_data", default: {}
    t.uuid "home_id"
    t.float "interest_rate"
    t.boolean "is_latest", default: true
    t.uuid "previous_transaction_id"
    t.string "status"
    t.decimal "total_cost", precision: 10, scale: 2
    t.decimal "transaction_cost", precision: 10, scale: 2
    t.string "transaction_id"
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.index ["client_id"], name: "index_transactions_on_client_id"
    t.index ["home_id"], name: "index_transactions_on_home_id"
    t.index ["previous_transaction_id"], name: "index_transactions_on_previous_transaction_id"
    t.index ["transaction_id", "is_latest"], name: "index_transactions_on_transaction_id_and_is_latest"
    t.index ["transaction_id"], name: "index_transactions_on_transaction_id"
    t.index ["user_id"], name: "index_transactions_on_user_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "client_id"
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.string "first_name"
    t.datetime "invitation_accepted_at"
    t.datetime "invitation_created_at"
    t.integer "invitation_limit"
    t.datetime "invitation_sent_at"
    t.string "invitation_token"
    t.integer "invitations_count", default: 0
    t.bigint "invited_by_id"
    t.string "invited_by_type"
    t.string "last_name"
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.datetime "locked_at"
    t.string "otp_code"
    t.datetime "otp_sent_at"
    t.string "phone_number"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "sign_in_count", default: 0, null: false
    t.string "unconfirmed_email"
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_users_on_client_id"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["invitation_token"], name: "index_users_on_invitation_token", unique: true
    t.index ["invited_by_id"], name: "index_users_on_invited_by_id"
    t.index ["invited_by_type", "invited_by_id"], name: "index_users_on_invited_by"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  create_table "users_roles", id: false, force: :cascade do |t|
    t.uuid "role_id"
    t.uuid "user_id"
    t.index ["role_id"], name: "index_users_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_users_roles_on_user_id_and_role_id"
    t.index ["user_id"], name: "index_users_roles_on_user_id"
  end

  add_foreign_key "accounts", "clients"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "homes", "clients"
  add_foreign_key "homes", "users"
  add_foreign_key "homes_transactions", "homes", column: "homes_id"
  add_foreign_key "homes_transactions", "transactions", column: "transactions_id"
  add_foreign_key "users", "clients"
end
