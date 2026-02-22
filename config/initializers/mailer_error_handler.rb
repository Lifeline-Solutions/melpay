# Custom error handler for ActionMailer delivery failures
# This ensures all mail delivery errors are captured by Sentry

module MailerErrorHandler
  extend ActiveSupport::Concern

  included do
    rescue_from Net::SMTPAuthenticationError, Net::SMTPServerBusy,
                Net::SMTPSyntaxError, Net::SMTPFatalError,
                Net::SMTPUnknownError, Net::OpenTimeout,
                Net::ReadTimeout, Errno::ECONNREFUSED,
                SocketError do |exception|

      # Get the action name from the message metadata if available
      mailer_action = message&.action_name || 'unknown'

      # Capture to Sentry with rich context
      Sentry.capture_exception(exception,
        level: :error,
        tags: {
          error_type: 'mail_delivery_error',
          mailer: self.class.name,
          action: mailer_action
        },
        extra: {
          mailer_class: self.class.name,
          mailer_action: mailer_action,
          delivery_method: ActionMailer::Base.delivery_method,
          smtp_address: ENV['SMTP_ADDRESS'],
          smtp_port: ENV['SMTP_PORT'],
          recipient: params[:user]&.email,
          exception_class: exception.class.name,
          exception_message: exception.message,
          backtrace: exception.backtrace&.first(10)
        }
      )

      # Log the error
      Rails.logger.error(
        "Mail delivery failed in #{self.class.name}##{mailer_action}: " \
        "#{exception.class} - #{exception.message}"
      )

      # Re-raise so the job can be retried
      raise exception
    end
  end
end

# Include in ApplicationMailer after it's loaded
Rails.application.config.after_initialize do
  ApplicationMailer.include(MailerErrorHandler) if defined?(ApplicationMailer)
end

