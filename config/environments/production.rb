require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local
  # Use vips for variant processing in production to reduce memory usage
  config.active_storage.variant_processor = :vips

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Fallback: if the 'cache' database isn't configured (which would raise during Solid Cache initialization),
  # remap Solid Cache to use the primary database to allow the app to boot. This prevents health check failures.
  begin
    cache_db_config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: 'cache')
    if cache_db_config.blank?
      config.after_initialize do
        Rails.logger.warn("[startup] 'cache' database config missing; falling back to :primary for Solid Cache")
        SolidCache::Record.connects_to database: { writing: :primary } if defined?(SolidCache::Record)
      end
    else
      # Normal mapping (SolidCache defaults to :cache). Explicit reinforcement for clarity.
      config.after_initialize do
        SolidCache::Record.connects_to database: { writing: :cache } if defined?(SolidCache::Record)
      end
    end
  rescue StandardError => e
    config.after_initialize do
      Rails.logger.warn("[startup] Failed evaluating cache DB config (#{e.class}: #{e.message}); using :primary fallback for Solid Cache")
      SolidCache::Record.connects_to database: { writing: :primary } if defined?(SolidCache::Record)
    end
  end

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "example.com" }

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
  # Raise error when a before_action's only/except options reference missing actions
  config.action_mailer.default_url_options = { host: 'malpayment.com', protocol: 'https' }
  config.action_controller.raise_on_missing_callback_actions = true
  config.active_storage.variant_processor = :mini_magick
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.perform_caching = false
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = {
    address: 'lim108.truehost.cloud',
    port: 465, # Port 465 uses implicit SSL/TLS (SMTPS)
    domain: 'malpayment.com',
    user_name: 'noreply@malpayment.com',
    password: 'Aw1}Pj&sjFxT)uc8',
    authentication: :plain,
    ssl: true, # Use implicit SSL for port 465 (SMTPS)
    # NOTE: Do NOT set enable_starttls_auto with ssl: true - they are mutually exclusive
    # Port 465 = implicit SSL (use ssl: true)
    # Port 587 = explicit STARTTLS (use enable_starttls_auto: true)
    openssl_verify_mode: 'none'
  }

end
