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
class SignInMailer < ApplicationMailer
  helper_method :reset_request_url, :locked_time

  def locked(user, locked_at:, from_address:, minutes:, origin: nil)
    @locked_at = locked_at
    @from_address = from_address
    @minutes = minutes
    @url_options = link_origin(origin)

    if @url_options.empty?
      Rails.logger.warn "[ContentSpiel] A sign-in pause mail was not sent: no site address is known. Set PUBLIC_HOST."
      return
    end

    mail subject: t("mail.locked.subject", site: site_name), to: user.email_address
  end

  private

  # `port: nil` first, for the reason `PasswordsMailer#reset_url` gives:
  # an address without a port would otherwise inherit the environment's.
  def reset_request_url = new_admin_password_url(port: nil, **@url_options)

  def locked_time = I18n.l(@locked_at.in_time_zone(SiteSetting.instance.effective_time_zone), format: :"admin.datetime")
end
