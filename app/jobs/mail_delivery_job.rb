# Delivers every mail of the CMS (`ApplicationMailer.delivery_job`) and
# records how it went (spec, decision 5; docs/reference/mail.md).
#
#   - Sent: `MailSettings.record_success!` with the fingerprint the mail was
#     queued under (`params[:fingerprint]`, `ApplicationMailer.queue`), which
#     verifies the settings only when it is still the current one. A mail the
#     mailer decided not to build, or not to send, records nothing.
#   - A connection failure (`MailFailure::CONNECTION_ERRORS`: refused,
#     unreachable, a timeout, an unknown host) is likely to pass: retried
#     three times with backoff (`ATTEMPTS` is four in all), and recorded once,
#     after the last. A failure is never recorded per attempt: one blip that
#     the next attempt gets through must not put "Last send failed" on the
#     dashboard.
#   - Any other failure of the delivery (a refused login, a refused sender,
#     a TLS mismatch, a reply nobody expected) will not pass by waiting:
#     recorded at once, and the job ends there.
#   - An error raised BEFORE the delivery is no mail failure (plan ruling
#     T2b, `MailFailure.delivery?`): a record deleted since the mail was
#     queued (`ActiveJob::DeserializationError`), a template or a mailer that
#     raises. It is raised on as Active Job always does: the job fails with
#     its backtrace, its log line and `Rails.error`, and nothing is recorded,
#     so the dashboard does not tell the owner to check settings that are fine.
#
# The handlers are `rescue_from`s, and Active Job tries the LAST declared
# first: `retry_on` comes after the catch-all so a connection error is
# retried. A recorded failure raises nothing, so a failed mail is no failed
# job and Solid Queue's failed list does not fill with mails the dashboard
# already shows. What is logged of one is Action Mailer's "Failed delivery"
# line (and, for a retry, Active Job's "Retrying"/"Stopped retrying"), with
# the server's reply already scrubbed of the login by `SmtpDelivery`.
class MailDeliveryJob < ActionMailer::MailDeliveryJob
  ATTEMPTS = 4

  rescue_from(StandardError) do |error|
    raise error unless MailFailure.delivery?(error)

    ApplicationMailer.record_failed(error)
  end

  retry_on(*MailFailure::CONNECTION_ERRORS, attempts: ATTEMPTS, wait: :polynomially_longer) do |_job, error|
    raise error unless MailFailure.delivery?(error)

    ApplicationMailer.record_failed(error)
  end

  def perform(mailer, mail_method, delivery_method, args:, kwargs: nil, params: nil)
    message = super
    ApplicationMailer.record_sent(message, fingerprint: params&.dig(:fingerprint))
    message
  end
end
