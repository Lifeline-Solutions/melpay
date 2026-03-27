---
name: Mpesa B2C Integration
description: M-Pesa B2C disbursement feature — what was built, how it works, and what's pending
type: project
---

## What was implemented

M-Pesa B2C (Business to Customer) disbursement was integrated into the `feat/Mpesa-sandbox` branch. When a transaction is finalised as `success` after OTP verification, the app now automatically initiates a Safaricom B2C payment to the recipient's phone number from the uploaded spreadsheet.

### Files created
- `db/migrate/20260326000001_add_mpesa_fields_to_transactions.rb` — adds `mpesa_conversation_id`, `mpesa_originator_conversation_id`, `mpesa_result_code`, `mpesa_result_desc`, `mpesa_transaction_receipt` to the transactions table
- `app/services/mpesa_b2c_service.rb` — OAuth token fetch + B2C API call; SecurityCredential is generated as `Base64(PartyA + Passkey + Timestamp)` (passkey-based, no certificate required)
- `app/controllers/mpesa_callbacks_controller.rb` — handles Safaricom's async `POST /mpesa/b2c/result` and `POST /mpesa/b2c/timeout` callbacks; skips CSRF/auth; updates transaction mpesa fields via `update_columns`

### Files modified
- `config/routes.rb` — added `POST mpesa/b2c/result` and `POST mpesa/b2c/timeout` routes
- `app/models/transaction.rb` — `prevent_direct_updates` now allows mpesa tracking columns to be updated directly (needed for callback reconciliation)
- `app/controllers/two_factor_controller.rb` — after credit deduction on success, calls private `initiate_mpesa_b2c(final_transaction)` for both single and batch flows
- `.env` — added `MPESA_CONSUMER_KEY`, `MPESA_CONSUMER_SECRET`, `MPESA_INITIATOR_NAME`, `MPESA_PARTY_A`, `MPESA_PASSKEY`, `MPESA_ENVIRONMENT`, `MPESA_CALLBACK_BASE_URL`

## Key design decisions

- **B2C fires after credit deduction** — transaction is already finalised in our system before B2C is called; B2C errors are rescued/logged and never roll back the transaction
- **Passkey-based SecurityCredential** — Safaricom changed from certificate-based encryption; credential is now `Base64(ShortCode + Passkey + Timestamp)` with `Timestamp` also included in the request payload
- **Phone number source** — comes from the `"phone number"` column in the uploaded spreadsheet, stored inside `transaction.deposit_data["phone number"]`
- **Async callbacks** — Safaricom POSTs result asynchronously; `mpesa_conversation_id` stored on transaction for reconciliation; `mpesa_result_code = 0` means success, `-1` means timeout
- **No automatic reversal** — if B2C fails (result_code != 0), it is logged but does not revert the internal transaction or refund credit; manual admin intervention required

## Pending / still needed

- `MPESA_CALLBACK_BASE_URL` in `.env` must be set to a public ngrok URL before testing (app runs locally in WSL containers)
- `MPESA_CONSUMER_KEY` and `MPESA_CONSUMER_SECRET` are already set in `.env` with sandbox values
- `rails db:migrate` must be run to apply the mpesa columns migration
- Sandbox credentials in use: initiator=testapi, Party A=600984, passkey=bfb279f9...
