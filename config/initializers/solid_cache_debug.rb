# Debug initializer for Solid Cache / multi-DB boot issues.
# Set DISABLE_SOLID_CACHE=1 in the environment to bypass Solid Cache and use a simple memory store.
# This is useful while diagnosing production boot failures related to cache DB configuration.

if ENV['DISABLE_SOLID_CACHE'] == '1'
  Rails.logger.warn('[solid_cache_debug] DISABLE_SOLID_CACHE=1 detected; using :memory_store instead of :solid_cache_store') if defined?(Rails)
  Rails.application.config.cache_store = :memory_store if defined?(Rails)
else
  # Log detected DB configs for visibility at boot.
  begin
    if defined?(ActiveRecord::Base)
      configs = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env)
      names = configs.map(&:name)
      Rails.logger.info("[solid_cache_debug] DB configs available for #{Rails.env}: #{names.join(', ')}")
      cache_present = names.include?('cache')
      queue_present = names.include?('queue')
      Rails.logger.info("[solid_cache_debug] cache present? #{cache_present} | queue present? #{queue_present}")
    end
  rescue StandardError => e
    Rails.logger.warn("[solid_cache_debug] Failed to enumerate DB configs: #{e.class}: #{e.message}")
  end
end

