# The invitation to a person who has no account yet. The CALLER hands the
# token (`Users::Invite`, Task 8), so this mailer reads no user's token and
# signs nothing. The link is `<site address>/invitation#<token>`: like the
# reset's, the token is the FRAGMENT, which a browser sends to no server, so
# it is in no request line, span or proxy log. Where the link points is the
# reset's rule, shared through `ApplicationMailer#link_origin`.
class InvitesMailer < ApplicationMailer
  # How long the link works (spec: seven days). The token itself expires by
  # its own `generates_token_for` (Task 8); this is only the date the mail
  # names, so the two are changed together.
  VALID_FOR = 7.days

  helper_method :invite_url, :inviter_name, :valid_until

  def invite(user, inviter:, token:, origin: nil)
    @user = user
    @inviter = inviter
    @token = token
    @url_options = link_origin(origin)

    if @url_options.empty?
      Rails.logger.warn "[ContentSpiel] An invitation mail was not sent: no site address is known. Set PUBLIC_HOST."
      return
    end

    mail subject: t("mail.invite.subject", inviter: inviter_name, site: site_name), to: user.email_address
  end

  private

  # Built once: both parts carry one link. `port: nil` as the reset's does.
  def invite_url = @invite_url ||= invitation_url(port: nil, **@url_options, anchor: @token)

  def inviter_name = PersonName.of(@inviter)

  def valid_until = I18n.l(VALID_FOR.from_now.to_date, format: :long)
end
