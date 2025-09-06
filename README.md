# Onafriq Portal Payments Ruby on Rails App Overview

## Objective

Build a Ruby on Rails web portal where users can:
- Register and log in.
- View their wallet/accounts and balances.
- Make payments (mobile money, airtime, or bank payments) via the Onafriq Portal Payments API.
- View payment history and statuses.

---

## Core Features

1. **User Authentication**
    - Use Devise or similar for user registration/login.
    - Each user is mapped to an organization/account in Onafriq.

2. **Account Management**
    - Display user's wallets/accounts, balances, and currency information.
    - Show account activation status (based on Onafriq API).

3. **Payment Creation**
    - Form for single and bulk payment creation:
        - Mobile money / Airtime: phone number, amount, currency, description, etc.
        - Bank payments: account number, bank selection, account name, email.
    - Support bulk payments via "recipient_data".
    - Include fields for custom metadata, national ID, etc.
    - Option to send SMS notification.

4. **Payment History**
    - List all payments for the user (using Onafriq `/payments` endpoint).
    - Filter/search by status, amount, phone number, date, etc.

5. **Admin/Approval Workflow**
    - Support for maker/checker approval flows (if required).
    - Show payment status and last error.

---

## Implementation Steps

### 1. Rails Setup

```bash
rails new portal_payments_app --database=postgresql
cd portal_payments_app
```

Add authentication (e.g., Devise):

```bash
bundle add devise
rails generate devise:install
rails generate devise User
rails db:migrate
```

### 2. Model Design

- **User** (Devise-managed)
- **Account** (maps to Onafriq wallet)
- **Payment** (local cache of Onafriq payment objects, for history)

### 3. Onafriq API Integration

Create a service object for Onafriq API requests (use `httparty` or `faraday`):

```ruby
# app/services/onafriq_api.rb
class OnafriqApi
  include HTTParty
  base_uri 'https://api.onafriq.com/api'

  def initialize(api_key)
    @headers = { 'Authorization' => "Token #{api_key}", 'Content-Type' => 'application/json' }
  end

  def create_payment(payload)
    self.class.post('/payments', headers: @headers, body: payload.to_json)
  end

  def list_payments(params = {})
    self.class.get('/payments', headers: @headers, query: params)
  end

  # Add other endpoints as needed
end
```

### 4. Payment Form Example

```erb
<!-- app/views/payments/new.html.erb -->
<h1>Make a Payment</h1>
<%= form_with url: payments_path, method: :post do |f| %>
  <%= f.label :phonenumber %>
  <%= f.text_field :phonenumber %>

  <%= f.label :amount %>
  <%= f.number_field :amount, step: 0.01 %>

  <%= f.label :currency %>
  <%= f.text_field :currency %>

  <%= f.label :account %>
  <%= f.text_field :account %>

  <%= f.label :description %>
  <%= f.text_field :description %>

  <!-- Optional fields for bulk payments -->
  <%= f.fields_for :recipient_data do |r| %>
    <%= r.text_field :phonenumber %>
    <%= r.number_field :amount, step: 0.01 %>
    <!-- etc. -->
  <% end %>

  <%= f.submit "Send Payment" %>
<% end %>
```

### 5. Controller Example

```ruby name=app/controllers/payments_controller.rb
class PaymentsController < ApplicationController
  before_action :authenticate_user!

  def index
    api = OnafriqApi.new(current_user.api_key)
    @payments = api.list_payments
  end

  def new
    # Renders the payment form
  end

  def create
    api = OnafriqApi.new(current_user.api_key)
    payload = payment_params.to_h
    response = api.create_payment(payload)
    if response.success?
      # Save response to local DB if needed, redirect to payments list
      redirect_to payments_path, notice: "Payment created!"
    else
      flash.now[:alert] = response['error'] || "Payment failed"
      render :new
    end
  end

  private

  def payment_params
    params.require(:payment).permit(
      :phonenumber, :amount, :currency, :account, :description,
      :payment_type, :first_name, :last_name, :national_id, :national_id_type,
      :send_sms_message, :partner_transaction_id, recipient_data: [:phonenumber, :amount, :description]
    )
  end
end
```

---

## Notes

- **API Key Management:** Store Onafriq API keys securely (e.g., Rails credentials, per-user).
- **Error Handling:** Display last error/status for each payment.
- **Maker/Checker Workflow:** For approvals, add an admin role and approval UI.
- **Testing Accounts:** Use test currency codes (e.g., BXC) in development.
- **Filters:** Add search/filter UI for payment history.

---

## References

- [Onafriq Portal Payments API Docs](https://api.onafriq.com/api/payments)
- [Devise Authentication for Rails](https://github.com/heartcombo/devise)
- [HTTParty Gem](https://github.com/jnunemaker/httparty)

---

Ready for code samples or a deeper dive into any section? Let me know!


Another view from Readme, this is the complete Readme file.

# Enterprise Payments Platform with Multi-Tenancy & Beyonic API Integration

A Ruby on Rails application for global organizations, PSPs, and MTOs, enabling:
- Payouts via banks, mobile money, or airtime
- Remittance & Bulk Payments (cash-pickup, mobile money, banks)
- Collections via mobile money, banks, and agents
- Strict multi-tenancy: Each organization only sees its own data

Built with `devise` for authentication and the Beyonic API for payments.

---

## 1. Project Setup

### a. Rails Installation

```bash
gem install rails
rails new enterprise_payments --database=postgresql
cd enterprise_payments
```

### b. Add Gems

Edit your `Gemfile`:

```ruby
gem 'devise'
gem 'apartment'          # For multi-tenancy
gem 'beyonic'            # Beyonic API (https://github.com/beyonic/beyonic-ruby)
gem 'pg'
gem 'dotenv-rails'       # For managing secrets
```

```bash
bundle install
```

---

## 2. Devise & Multi-Tenancy Setup

### a. Devise for User Authentication

```bash
rails generate devise:install
rails generate devise User
rails db:migrate
```
Add fields to users (`rails generate migration AddFieldsToUsers ...` or edit migration):

- `first_name`, `last_name`, `role` (integer), `organisation_id` (references), etc.

### b. Organization Model

```bash
rails generate model Organisation name:string status:integer
rails db:migrate
```

### c. User Belongs to Organisation

Edit `app/models/user.rb`:

```ruby
class User < ApplicationRecord
  belongs_to :organisation
  enum role: { admin: 0, member: 1 }
  # devise modules ...
end
```

Edit `app/models/organisation.rb`:

```ruby
class Organisation < ApplicationRecord
  has_many :users
end
```

### d. Apartment Gem for Multi-Tenancy

Configure Apartment in `config/initializers/apartment.rb`:

```ruby
Apartment.configure do |config|
  config.excluded_models = %w{ User Organisation }
  config.tenant_names = -> { Organisation.pluck(:name) }
end
```

Wrap controllers that need scoping with Apartment:

```ruby
class ApplicationController < ActionController::Base
  around_action :switch_organisation

  def switch_organisation(&block)
    Apartment::Tenant.switch!(current_user.organisation.name, &block) if user_signed_in?
  end
end
```

---

## 3. Database Models

### a. Generate Models

Use Rails generators for each table:

```bash
rails generate model ApiKey key:string permissions:integer status:integer last_used_at:datetime user:references
rails generate model Transaction reference:string amount:integer currency:string transaction_type:integer status:integer payment_method:integer metadata:json completed_at:datetime user:references
# Repeat for: Payout, Collection, Remittance, Recipient, Customer, Webhook, WebhookEvent, Agent
```

Add all fields as per your schema, including foreign keys.

### b. Migration Example

Edit migration files as needed to match your provided SQL.

```ruby
create_table :api_keys, id: :uuid do |t|
  t.string :key
  t.integer :permissions
  t.integer :status
  t.datetime :last_used_at
  t.references :user, type: :uuid, foreign_key: true
  t.timestamps
end
```

Set primary keys to uuid if needed (`enable_extension "uuid-ossp"` in migration).

---

## 4. Controllers and Multi-Tenancy

- Scaffold controllers for each resource (`rails generate scaffold ...`)
- In each controller, scope queries by `current_user.organisation`

Example for Transactions:

```ruby
class TransactionsController < ApplicationController
  before_action :authenticate_user!

  def index
    @transactions = Transaction.where(user: current_user)
  end

  # Other CRUD actions...
end
```

---

## 5. Beyonic API Integration

### a. Add API Key

Create `.env`:

```
BEYONIC_API_KEY=your_actual_key_here
```

Load in `config/initializers/beyonic.rb`:

```ruby
Beyonic.api_key = ENV['BEYONIC_API_KEY']
```

### b. Service Object for Payments

Create `app/services/beyonic_payment_service.rb`:

```ruby name=app/services/beyonic_payment_service.rb
class BeyonicPaymentService
  def self.create_payment(params)
    Beyonic::Payment.create(
      phonenumber: params[:phonenumber],
      first_name: params[:first_name],
      last_name: params[:last_name],
      amount: params[:amount],
      currency: params[:currency],
      description: params[:description],
      payment_type: params[:payment_type] || "money",
      callback_url: params[:callback_url],
      metadata: params[:metadata]
      # Add any other params as needed
    )
  end
end
```

### c. Example Payment Controller Action

```ruby
def create
  result = BeyonicPaymentService.create_payment(payment_params)
  render json: result
end

private

def payment_params
  params.require(:payment).permit(:phonenumber, :first_name, :last_name, :amount, :currency, :description, :payment_type, :callback_url, metadata: {})
end
```

---

## 6. Webhooks & Callbacks

- Create a route for Beyonic callbacks (e.g. `/payments/callback`)
- Controller to update payment status on callback

```ruby
class PaymentsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:callback]

  def callback
    # Update Transaction with Beyonic status from params
    # params[:state], params[:id], etc.
  end
end
```

---

## 7. Multi-Tenancy Scoping

- All queries in controllers/models should scope by `current_user.organisation`
- Users should only see their organization’s data

---

## 8. Admin & Roles

- Use Devise roles (`admin`, `member`)
- Only `admin` can manage organisation users

---

## 9. Testing

- Write RSpec or Minitest tests for service objects, controllers, and multi-tenancy logic.

---

## 10. Deployment & Security

- Use environment variables for sensitive keys.
- Deploy on Heroku, AWS, or similar.
- Set up SSL, strong passwords, and do not expose API keys.

---

## 11. Further Improvements

- Add background jobs for bulk payments and webhook handling.
- Add UI for organizations to manage their users and payments.
- Audit logs for compliance.

---

## Example Directory Structure

```
app/
  controllers/
  models/
  services/
  views/
config/
db/
.env
Gemfile
```

---

## Summary

You now have a blueprint for a full-featured, multi-tenant enterprise payments platform in Rails, with Beyonic API integration for payouts, remittances, and collections. Each organization is fully isolated, and the system supports banks, cash-pickup, mobile money, and agents.

**For full code, see generated models, controllers, and service above.**  
**Customize as needed for your organization and workflow.**
