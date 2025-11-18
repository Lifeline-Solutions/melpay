# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# ruby

# ruby

Role.find_or_create_by!(name: 'super_admin')
Role.find_or_create_by!(name: 'admin')
Role.find_or_create_by!(name: 'auditor')
Role.find_or_create_by!(name: 'account_manager')

client = Client.find_or_create_by!(name: 'Solidus') do |c|
  c.email = 'admin@solidus.com'
  c.user_pass = 'Great'
  c.credit = 10000
end

user = User.find_or_initialize_by(email: 'abolger254@gmail.com')
user.assign_attributes(
  password: user.encrypted_password.present? ? user.password : 'password',
  confirmed_at: user.confirmed_at || DateTime.now,
  confirmation_sent_at: user.confirmation_sent_at || DateTime.now,
  first_name: user.first_name.presence || 'Jay',
  last_name: user.last_name.presence || 'Admin',
  client: user.client || client
)
user.save!
user.add_role(:super_admin) unless user.has_role?(:super_admin)
