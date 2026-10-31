class PasswordsMailer < ApplicationMailer
  helper_method :reset_url, :reset_minutes

  def reset(user, origin: nil)
    @user = user
    @url_options = link_origin(origin)

    if @url_options.empty?
      Rails.logger.warn "[ContentSpiel] A password reset mail was not sent: no site address is known. Set PUBLIC_HOST."
      return
    end

    mail subject: t("mail.reset.subject", site: site_name), to: user.email_address
  end

  private

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
