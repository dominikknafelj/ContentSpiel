class PasswordsMailer < ApplicationMailer
  helper_method :reset_url

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

  def reset(user, origin: nil)
    @user = user
    @url_options = link_origin(origin)

    if @url_options.empty?
      Rails.logger.warn "[ContentSpiel] A password reset mail was not sent: no site address is known. Set PUBLIC_HOST."
      return
    end

    mail subject: "Reset your password", to: user.email_address
  end

  private

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

  def link_origin(origin)
    configured = SiteAddress.current
    return configured.url_options if configured.configured?

    return {} unless self.class.request_origin_used?

    SiteAddress.parse(origin, source: "the request's origin").url_options
  rescue SiteAddress::Invalid
    {}
  end
end
