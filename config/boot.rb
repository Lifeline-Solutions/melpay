ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

# Early sanitize of invalid DATABASE_URL placeholders that DO may inject
begin
  db_url = ENV['DATABASE_URL'].to_s
  if !db_url.empty?
    invalid_placeholder = db_url.include?('${')
    invalid_scheme = !(db_url.start_with?('postgres://') || db_url.start_with?('postgresql://'))
    ENV.delete('DATABASE_URL') if invalid_placeholder || invalid_scheme
  end
rescue => _e
  ENV.delete('DATABASE_URL')
end

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.
