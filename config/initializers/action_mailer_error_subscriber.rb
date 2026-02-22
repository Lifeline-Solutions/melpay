# Subscribe to ActionMailer delivery errors
# This ensures all email delivery failures are captured and reported

ActiveSupport::Notifications.subscribe('deliver.action_mailer') do |_name, _start, _finish, _id, payload|
  if payload[:exception_object].present?
    exception = payload[:exception_object]

    # Capture to Sentry
    Sentry.capture_exception(exception,
      level: :error,
      tags: {
        component: 'action_mailer',
        mailer: payload[:mailer],
        action: payload[:action]
      },
      extra: {
        mailer: payload[:mailer],
        action: payload[:action],
        subject: payload[:subject],
        to: payload[:to],
        from: payload[:from],
        delivery_method: payload[:delivery_method],
        exception_class: exception.class.name,
        exception_message: exception.message
      }
    )
  end
end

# Also subscribe to process errors
ActiveSupport::Notifications.subscribe('process.action_mailer') do |_name, _start, _finish, _id, payload|
  if payload[:exception_object].present?
    exception = payload[:exception_object]

    Sentry.capture_exception(exception,
      level: :error,
      tags: {
        component: 'action_mailer_process',
        mailer: payload[:mailer],
        action: payload[:action]
      },
      extra: {
        mailer: payload[:mailer],
        action: payload[:action],
        params: payload[:params],
        exception_class: exception.class.name,
        exception_message: exception.message
      }
    )
  end
end

