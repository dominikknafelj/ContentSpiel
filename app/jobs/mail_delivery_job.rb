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
#   - Anything else (a refused login, a refused sender, a TLS mismatch, a
#     bug) will not pass by waiting: recorded at once and discarded.
#
# The handlers are `rescue_from`s, and Active Job tries the LAST declared
# first: `retry_on` comes after the catch-all so a connection error is
# retried and not discarded. Recording a failure answers the MailFailure and
# raises nothing, so the job ends there: a failed mail is no failed job, and
# Solid Queue's failed list does not fill with mails the dashboard already
# shows. The job's own log lines name the error's class and message; a
# connection error's message names the server and the port, never the login.
class MailDeliveryJob < ActionMailer::MailDeliveryJob
  ATTEMPTS = 4

  rescue_from(StandardError) { |error| ApplicationMailer.record_failed(error) }

  retry_on(*MailFailure::CONNECTION_ERRORS, attempts: ATTEMPTS, wait: :polynomially_longer) do |_job, error|
    ApplicationMailer.record_failed(error)
  end

  def perform(mailer, mail_method, delivery_method, args:, kwargs: nil, params: nil)
    message = super
    ApplicationMailer.record_sent(message, fingerprint: params&.dig(:fingerprint))
    message
  end
end
