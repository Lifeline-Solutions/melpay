require_relative "boot"

# Sanitize invalid DATABASE_URL placeholders before ActiveRecord reads it
begin
  db_url = ENV['DATABASE_URL'].to_s
  if !db_url.empty?
    invalid_placeholder = db_url.include?('${')
    invalid_scheme = !(db_url.start_with?('postgres://') || db_url.start_with?('postgresql://'))
    ENV.delete('DATABASE_URL') if invalid_placeholder || invalid_scheme
  end
rescue => _e
  # If anything goes wrong, just remove the variable to fall back to database.yml
  ENV.delete('DATABASE_URL')
end

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Melpay
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])
    config.time_zone = 'Africa/Nairobi'


    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
    config.active_job.queue_adapter = :sidekiq

  end
end
