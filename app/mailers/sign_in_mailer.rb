# The mail to an account whose sign-in a run of failed attempts paused, sent
# by `SignIn::LockoutMailJob` at most once an hour per account
# (`SignIn::Throttle#notice_due?`): how long the pause is, when the attempt
# that paused it came (in the site's zone) and from which address, and a
# button to the reset request.
#
# THE LINK CARRIES NO TOKEN. It is the reset REQUEST page
# (`new_admin_password_url`), where the person asks for a reset link of
# their own: a mail sent because somebody else was guessing must not put a
# working reset in front of whoever reads the account's mail next. Its
# origin follows `ApplicationMailer#link_origin`, as the reset's does, so
# with no address known outside development and test no mail is built and
# one line says why, naming nobody.
#
# `from_address` is the request's `remote_ip`, as the controller read it:
# the address the account's owner is told the attempts came from. Behind a
# CDN whose ranges are not trusted it is the CDN's (docs/reference/hosting.md).
#
# THE TWO ACCOUNT MAILS, `passkey_added` and `recovery_code_used`, tell a
# person that their second factors changed: the passkey's name (theirs, typed
# in their own account) and when, or the address a code was used from, when,
# and how many codes are left. Neither carries a code, a key, a credential id
# or a digest, and neither names anyone but the account's own person. Their
# one button is "Open Your account", to Your account's passkeys
# (`admin_account_url`, a link with no token), under the same origin rule
# as the pause mail. They are queued by `queue_alert` only, which is one
# `auth.account_mail` span and, when mail is not ready, sends nothing and
# logs one line naming the mail's kind and nobody: a person is never
# blocked by a mail that cannot go.
class SignInMailer < ApplicationMailer
  helper_method :reset_request_url, :locked_time, :account_url, :account_mail_time

  ACCOUNT_MAILS = %i[passkey_added recovery_code_used].freeze
  # The line a mail with no known origin logs, with the mail's word
  # ("pause", "account"): it names nobody and nothing of the mail.
  NOT_SENT = "[ContentSpiel] A sign-in %s mail was not sent: no site address is known. Set PUBLIC_HOST.".freeze
  NOT_READY = "[ContentSpiel] A sign-in account mail (%s) was not queued: mail is not ready.".freeze

  # Queues the account mail `kind` for `user` when mail is ready; answers
  # whether it queued. The span's two attributes are a fixed word and a
  # Boolean: no name, address, code or count.
  def self.queue_alert(kind, user, **arguments)
    raise ArgumentError, "#{kind.inspect} is not an account mail" unless ACCOUNT_MAILS.include?(kind)

    Telemetry.in_span("auth.account_mail", attributes: { "auth.mail.kind" => kind.to_s }) do |span|
      queued = MailSettings.current.ready?
      if queued
        ApplicationMailer.queue(self, kind, user, **arguments)
      else
        Rails.logger.warn format(NOT_READY, kind)
      end
      Telemetry.record(span, "auth.mail.queued" => queued)
      queued
    end
  end

  def passkey_added(user, name:, added_at:, origin: nil)
    @name = name
    @at = added_at
    return unless account_mail_origin?(origin)

    mail subject: t("mail.passkey_added.subject", site: site_name), to: user.email_address
  end

  def recovery_code_used(user, used_at:, from_address:, left:, origin: nil)
    @at = used_at
    @from_address = from_address
    @left = left
    return unless account_mail_origin?(origin)

    mail subject: t("mail.recovery_code_used.subject", site: site_name), to: user.email_address
  end

  def locked(user, locked_at:, from_address:, minutes:, origin: nil)
    @locked_at = locked_at
    @from_address = from_address
    @minutes = minutes
    @url_options = link_origin(origin)

    if @url_options.empty?
      Rails.logger.warn format(NOT_SENT, "pause")
      return
    end

    mail subject: t("mail.locked.subject", site: site_name), to: user.email_address
  end

  private

  # Sets the link's origin; false, with one line that names nobody and
  # nothing of the mail, when none is known (as `locked`).
  def account_mail_origin?(origin)
    @url_options = link_origin(origin)
    return true unless @url_options.empty?

    Rails.logger.warn format(NOT_SENT, "account")
    false
  end

  def account_url = admin_account_url(port: nil, anchor: "passkeys", **@url_options)

  def account_mail_time = I18n.l(@at.in_time_zone(SiteSetting.instance.effective_time_zone), format: :"admin.datetime")

  # `port: nil` first, for the reason `PasswordsMailer#reset_url` gives:
  # an address without a port would otherwise inherit the environment's.
  def reset_request_url = new_admin_password_url(port: nil, **@url_options)

  def locked_time = I18n.l(@locked_at.in_time_zone(SiteSetting.instance.effective_time_zone), format: :"admin.datetime")
end
