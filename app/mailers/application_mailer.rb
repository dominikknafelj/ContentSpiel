# Every mail of the CMS: sent with the site's mail settings, by
# `MailDeliveryJob`, with its outcome recorded (spec docs/superpowers/specs/
# 2026-10-28-mail-design.md, decisions 4 to 6; docs/reference/mail.md).
#
# HOW A MAIL IS SENT. A caller queues it, and nothing else:
#
#   ApplicationMailer.queue(PasswordsMailer, :reset, user, origin: "...")
#
# which is `deliver_later` with the fingerprint of the settings as they are
# NOW as a mailer param (`params[:fingerprint]`). The job delivers it, and a
# success verifies the settings only when that fingerprint is still the
# current one: a mail queued under old settings never verifies new ones. The
# job's arguments are the mailer, the action, records as their Global IDs
# and the fingerprint (an HMAC that says nothing of the settings): never a
# setting, never the login. A plain `deliver_later` still works and is
# delivered and recorded, but verifies nothing.
#
# The test mail is the one sent at once, because its answer is the point:
# `ApplicationMailer.deliver_now_and_record(SomeMailer.test(...))` answers
# nil when it was sent, or the `MailFailure`.
#
# WITH WHAT. `mail` is where the settings are read, so in the job they are
# the settings at delivery time:
#   - From: the effective sender, name and address (`MailSettings#sender`).
#   - A server that is set: SMTP with the effective settings
#     (`MailSettings#smtp_options`), through `SmtpDelivery`, which tells a
#     refused sender from a refused recipient. Per message, so a change in
#     Settings needs no restart and `config.action_mailer.smtp_settings` is
#     not used.
#   - No server, outside production: the environment's own method stands in
#     (`:file` into tmp/mails in development, `:test` in test; plan Ruling 1)
#     and a send through it is a send that succeeded.
#   - Settings that are not complete: nothing is sent, and one log line says
#     so. The callers are meant to ask `MailSettings#ready?` first; this is
#     the floor under them, so a mail is never sent to localhost:25 or with
#     no From.
#   - In the TEST environment a server that is not this machine is never
#     dialled: the stand-in takes the mail (`config.x.mail.smtp_loopback_only`
#     in config/environments/test.rb). A test can put the site in `:working`
#     with smtp.example.test and read the mail it sent from `deliveries`; the
#     tests of the exchange itself point the settings at the local stub on
#     127.0.0.1 (test/support/smtp_stub.rb). No test reaches the network.
#
# A failure raises in every environment (`raise_delivery_errors` per
# message): it is recorded, not swallowed. Nothing on this path logs a
# setting: the log subscriber's info line is the message id, and the server's
# line is scrubbed before it is stored.
class ApplicationMailer < ActionMailer::Base
  self.delivery_job = MailDeliveryJob

  # The servers `config.x.mail.smtp_loopback_only` still dials: this machine.
  LOOPBACK = %w[127.0.0.1 ::1 localhost].freeze

  default from: -> { MailSettings.current.sender }
  layout "mailer"

  before_deliver :say_not_sent, if: -> { @mail_not_set_up }

  # Queues `mailer_class.action(*args, **kwargs)` with the fingerprint of the
  # settings it is queued under. Answers what `deliver_later` answers.
  def self.queue(mailer_class, action, *args, **kwargs)
    mailer_class.with(fingerprint: MailSettings.current.fingerprint).public_send(action, *args, **kwargs).deliver_later
  end

  # Delivers now and records the outcome: nil when it was sent (or there was
  # nothing to send), the MailFailure when the delivery failed. An error
  # raised before the delivery (the mailer's code, a template) is a bug and
  # is raised on, not recorded (`MailFailure.delivery?`, ruling T2b). For the test mail, which is
  # sent in the request: the timeouts (`MailSettings::OPEN_TIMEOUT`,
  # `READ_TIMEOUT`) bound how long that can take.
  def self.deliver_now_and_record(delivery)
    fingerprint = MailSettings.current.fingerprint
    record_sent(delivery.deliver_now, fingerprint: fingerprint)
    nil
  rescue StandardError => error
    raise unless MailFailure.delivery?(error)

    record_failed(error)
  end

  # A delivery's answer is the message that was handed to its method, or
  # nil when the action built none (`PasswordsMailer#reset` without an
  # address); a message whose `perform_deliveries` is off was not sent.
  # Either of those records nothing.
  def self.record_sent(message, fingerprint:)
    return unless message.is_a?(Mail::Message) && message.perform_deliveries

    MailSettings.record_success!(fingerprint: fingerprint)
  end

  # Records a failure after its last attempt; answers the MailFailure.
  def self.record_failed(error)
    MailFailure.from(error, MailSettings.current).tap do |failure|
      MailSettings.record_failure!(key: failure.key, line: failure.line)
    end
  end

  # WHERE THE LINK POINTS (safe-address spec, "Mail"). A mail is read outside
  # any request, so its link needs an origin from somewhere, and the
  # environment's `default_url_options` is not it: in production that is the
  # site's address only when one is configured, and elsewhere a literal.
  #
  # - The site's configured address (`PUBLIC_HOST`) whenever there is one,
  #   whatever `origin` says.
  # - Otherwise, IN DEVELOPMENT AND TEST ONLY (`request_origin_used?`), `origin`:
  #   the origin of the request that asked for the reset
  #   (`Admin::PasswordsController#create`), which is where the person was a
  #   moment ago. It is a String because the mail is delivered by a job. It
  #   is parsed as an address and nothing else of it is used: a value that
  #   is not an origin is no origin, and the mailer never logs it. (Active
  #   Job logs a job's arguments, so in development the origin is in the
  #   job's own lines and in the queue's row: an address, never a token.)
  # - Otherwise no mail: `mail` is not called, so Action Mailer delivers
  #   nothing, and the log says what to set. The line names no person and
  #   holds no token.
  #
  # WHY NOWHERE ELSE. The request's origin is whatever `Host` the request
  # named, and a site with no address configured refuses no host. Anyone
  # could then ask for a reset of an address they know under a host of their
  # own, and the account's owner would be mailed a valid token on a link to
  # that host (password-reset poisoning). On a developer's machine the
  # request's origin is the only address there is, and the only one asking
  # is the developer.
  #
  # An ALLOW-list (`local?` is Rails' own "development or test"), never
  # `!env.production?`: a staging, preview or demo environment is exactly
  # the kind that sits on a public address without `PUBLIC_HOST`, and host
  # authorisation is set up from `production.rb` alone, so an environment
  # nobody named here must fail closed.
  def self.request_origin_used?(env = Rails.env)
    env.local?
  end

  def mail(...)
    super.tap { |message| deliver_with_site_settings(message) unless @site_settings_applied }
  end

  private

  def deliver_with_site_settings(message)
    @site_settings_applied = true
    settings = MailSettings.current
    if !settings.complete?
      @mail_not_set_up = true
      message.perform_deliveries = false
    elsif smtp?(settings)
      message.delivery_method(SmtpDelivery, settings.smtp_options)
    end
    message.raise_delivery_errors = true
  end

  def smtp?(settings)
    return false if settings.stand_in?
    return true unless Rails.configuration.x.mail.smtp_loopback_only

    LOOPBACK.include?(settings.value(:server))
  end

  def say_not_sent
    Rails.logger.warn "[ContentSpiel] A mail was not sent: outgoing mail is not set up."
  end

  # Shared by the mails that carry a link (PasswordsMailer, InvitesMailer),
  # so the origin rules above are written once.
  def link_origin(origin)
    configured = SiteAddress.current
    return configured.url_options if configured.configured?

    return {} unless self.class.request_origin_used?

    SiteAddress.parse(origin, source: "the request's origin").url_options
  rescue SiteAddress::Invalid
    {}
  end

  # The site's name in the mail's default language, as text: the subject,
  # the heading and the footer. Read per message, so in the job.
  def site_name = Locales.read(SiteSetting.instance, :title, locale: I18n.default_locale)
  helper_method :site_name
end
