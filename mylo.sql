CREATE TABLE "users" (
  "id" varchar,
  "email" string,
  "phone" string,
  "first_name" string,
  "last_name" string,
  "password_digest" string,
  "role" integer,
  "status" integer,
  "address" string,
  "id_type" string,
  "id_number" string,
  "created_at" datetime,
  "updated_at" datetime
);

CREATE TABLE "api_keys" (
  "id" varchar,
  "key" string,
  "permissions" integer,
  "status" integer,
  "last_used_at" datetime,
  "created_at" datetime,
  "updated_at" datetime,
  "user_id" varchar
);

CREATE TABLE "transactions" (
  "id" varchar,
  "reference" string,
  "amount" integer,
  "currency" string,
  "transaction_type" integer,
  "status" integer,
  "payment_method" integer,
  "metadata" json,
  "completed_at" datetime,
  "created_at" datetime,
  "updated_at" datetime,
  "user_id" varchar
);

CREATE TABLE "payouts" (
  "id" varchar,
  "reference" string,
  "amount" integer,
  "currency" string,
  "recipient_type" integer,
  "narration" string,
  "status" integer,
  "callback_url" string,
  "completed_at" datetime,
  "created_at" datetime,
  "updated_at" datetime,
  "user_id" varchar
);

CREATE TABLE "collections" (
  "id" varchar,
  "reference" string,
  "amount" integer,
  "currency" string,
  "payment_methods" text,
  "expires_at" datetime,
  "status" integer,
  "callback_url" string,
  "metadata" json,
  "completed_at" datetime,
  "created_at" datetime,
  "updated_at" datetime,
  "user_id" varchar
);

CREATE TABLE "remittances" (
  "id" varchar,
  "reference" string,
  "amount" integer,
  "source_currency" string,
  "destination_currency" string,
  "exchange_rate" decimal,
  "fee" decimal,
  "total_amount" decimal,
  "payout_method" integer,
  "status" integer,
  "narration" string,
  "callback_url" string,
  "payout_code" string,
  "expires_at" datetime,
  "completed_at" datetime,
  "created_at" datetime,
  "updated_at" datetime,
  "user_id" varchar
);

CREATE TABLE "recipients" (
  "id" varchar,
  "first_name" string,
  "last_name" string,
  "phone" string,
  "email" string,
  "recipient_type" integer,
  "country_code" string,
  "bank_details" json,
  "mobile_money_details" json,
  "airtime_details" json,
  "created_at" datetime,
  "updated_at" datetime,
  "user_id" varchar
);

CREATE TABLE "customers" (
  "id" varchar,
  "name" string,
  "phone" string,
  "email" string,
  "status" integer,
  "created_at" datetime,
  "updated_at" datetime,
  "user_id" varchar
);

CREATE TABLE "webhooks" (
  "id" varchar,
  "url" string,
  "events" text,
  "secret_key" string,
  "status" integer,
  "created_at" datetime,
  "updated_at" datetime,
  "user_id" varchar
);

CREATE TABLE "webhook_events" (
  "id" varchar,
  "event_type" string,
  "payload" json,
  "status" integer,
  "response" json,
  "retry_count" integer,
  "next_retry_at" datetime,
  "created_at" datetime,
  "updated_at" datetime,
  "webhook_id" varchar,
  "transaction_id" varchar
);

CREATE TABLE "agents" (
  "id" varchar,
  "agent_code" string,
  "name" string,
  "address" text,
  "phone" string,
  "country_code" string,
  "latitude" decimal,
  "longitude" decimal,
  "services" text,
  "operating_hours" json,
  "created_at" datetime,
  "updated_at" datetime
);

ALTER TABLE "users" ADD CONSTRAINT "fk_rails_api_keys_users" FOREIGN KEY ("id") REFERENCES "api_keys" ("user_id");

ALTER TABLE "users" ADD CONSTRAINT "fk_rails_transactions_users" FOREIGN KEY ("id") REFERENCES "transactions" ("user_id");

ALTER TABLE "users" ADD CONSTRAINT "fk_rails_payouts_users" FOREIGN KEY ("id") REFERENCES "payouts" ("user_id");

ALTER TABLE "users" ADD CONSTRAINT "fk_rails_collections_users" FOREIGN KEY ("id") REFERENCES "collections" ("user_id");

ALTER TABLE "users" ADD CONSTRAINT "fk_rails_remittances_users" FOREIGN KEY ("id") REFERENCES "remittances" ("user_id");

ALTER TABLE "users" ADD CONSTRAINT "fk_rails_recipients_users" FOREIGN KEY ("id") REFERENCES "recipients" ("user_id");

ALTER TABLE "users" ADD CONSTRAINT "fk_rails_customers_users" FOREIGN KEY ("id") REFERENCES "customers" ("user_id");

ALTER TABLE "users" ADD CONSTRAINT "fk_rails_webhooks_users" FOREIGN KEY ("id") REFERENCES "webhooks" ("user_id");

ALTER TABLE "webhooks" ADD CONSTRAINT "fk_rails_webhook_events_webhooks" FOREIGN KEY ("id") REFERENCES "webhook_events" ("webhook_id");

ALTER TABLE "transactions" ADD CONSTRAINT "fk_rails_webhook_events_transactions" FOREIGN KEY ("id") REFERENCES "webhook_events" ("transaction_id");
