module Admin
  # The origin a request hands a mail that carries a link (the reset, the
  # invitation, the sign-in pause), as the keyword arguments to pass on.
  #
  # The link is the site's configured address whenever there is one, and
  # then the request's origin is not handed over at all: it is whatever
  # `Host` this request named. Without one, and in development and test only
  # (`ApplicationMailer.request_origin_used?`, which says why), this
  # request's origin is the only address anybody knows: a String, because a
  # job delivers the mail, and the mailer parses it before it uses any of it
  # (`ApplicationMailer#link_origin`). Anywhere else without an address the
  # mailer builds no mail and logs why.
  module MailLinkOrigin
    private

    def mail_link_origin
      return {} if SiteAddress.current.configured? || !ApplicationMailer.request_origin_used?

      { origin: request.base_url }
    end
  end
end
