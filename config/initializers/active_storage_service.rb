# Ensure production always has a valid Active Storage service.
# We prefer the :local service and alias :production to it if anything expects that name.

if Rails.env.production?
  Rails.application.config.after_initialize do
    # Force the configured service to :local (matches config/storage.yml "local" entry)
    Rails.application.config.active_storage.service = :local

    begin
      # Load the service configurations Active Storage sees
      configs = Rails.application.config_for(:storage) rescue {}

      # If a :production config is missing but :local exists, alias it
      if !configs.key?("production") && configs.key?("local")
        configs["production"] = configs["local"]
      end

      # Re-apply configurations so Active Storage picks up the alias
      if defined?(ActiveStorage::Service) && ActiveStorage.const_defined?(:Service)
        ActiveStorage::Blob.services = ActiveStorage::Service::Registry.new(configs.transform_keys(&:to_sym))
      end
    rescue => e
      Rails.logger.warn("[startup] Failed to normalize Active Storage configs (#{e.class}: #{e.message})")
    end
  end
end

