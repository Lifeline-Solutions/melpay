# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

client = Client.find_or_create_by!(name: 'howel')
Role.find_or_create_by!(name: 'admin')

user = User.find_or_initialize_by(email: 'admin@craftsilicon.com')
user.password = 'password'
user.confirmed_at = DateTime.now
user.confirmation_sent_at = DateTime.now
user.first_name = 'Jay'
user.last_name = 'Admin'
user.client = client
user.save!
user.add_role(:admin)
