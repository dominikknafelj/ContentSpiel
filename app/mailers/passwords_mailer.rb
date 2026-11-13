class PasswordsMailer < ApplicationMailer
  helper_method :reset_url, :reset_minutes, :sign_in_url, :provider_name

  def reset(user, origin: nil)
    @user = user
    @url_options = link_origin(origin)

    if @url_options.empty?
      Rails.logger.warn "[ContentSpiel] A password reset mail was not sent: no site address is known. Set PUBLIC_HOST."
      return
    end

    mail subject: t("mail.reset.subject", site: site_name), to: user.email_address
  end

  # The reset request's answer for an account that signs in through the
  # provider alone (`SignInRules.reminder_instead_of_reset?`, decided by
  # `PasswordResetRequestJob`): to sign in with `provider` (its name, as a
  # job's argument holds it; never the provider itself, whose secret would
  # sit in the queue's row), with one button to the sign-in page. THE MAIL
  # CARRIES NO RESET LINK and no token: a password set here would be one the
  # account cannot use. It goes to the account's own address, as the reset
  # does, so the person who asked learns nothing they could not learn from
  # any reset request. Its origin follows `link_origin`, as the reset's.
  def sso_reminder(user, provider:, origin: nil)
    @provider = provider
    @url_options = link_origin(origin)

    if @url_options.empty?
      Rails.logger.warn "[ContentSpiel] A single sign-on reminder mail was not sent: no site address is known. Set PUBLIC_HOST."
      return
    end

    mail subject: t("mail.sso_reminder.subject", site: site_name, provider: provider), to: user.email_address
  end

  private

  def provider_name = @provider

  # `port: nil` first, for the reason `reset_url` gives.
  def sign_in_url = admin_sign_in_url(port: nil, **@url_options)

  # The 15 of "within 15 minutes", from the token's own lifetime.
  def reset_minutes = @user.password_reset_token_expires_in.to_i / 60

  # The link itself, built here and nowhere else: both parts of the mail
  # call it, so its shape is changed in this one line.
  #
  # `port: nil` first: `url_for` merges what it is given over
  # `default_url_options`, so an address without a port would otherwise
  # inherit the environment's (development's 3000).
  #
  # Memoised, so the two parts carry one link: every call of
  # `password_reset_token` signs a new token.
  #
  # THE TOKEN IS THE FRAGMENT (`anchor:`), not a segment of the path and not
  # a parameter: a browser sends what follows the "#" to no server, so the
  # token is in no request line, no span and no proxy's log. The page's
  # script moves it into the form, which sends it in its body
  # (`controllers/reset_token_controller.js`).
  def reset_url
    @reset_url ||= admin_edit_password_url(port: nil, **@url_options, anchor: @user.password_reset_token)
  end
end
