# The invitation to a person who has no account yet (`Invitation`). The token
# is made HERE, when the mail is built in the job
# (`generate_token_for(:accept)`, as the reset mail does), never handed in: an
# argument is written to the queue's row and to Active Job's log lines, and a
# credential is in neither. The link is `<site address>/<admin>/invitation#<token>`:
# like the reset's, the token is the FRAGMENT, which a browser sends to no
# server, so it is in no request line, span or proxy log. Where the link
# points is the reset's rule, shared through `ApplicationMailer#link_origin`.
#
# An invitation withdrawn before the job ran cannot be found by the job, which
# then ends quietly (`MailDeliveryJob`, controller ruling T8a).
class InvitesMailer < ApplicationMailer
  helper_method :invite_url, :inviter_name, :valid_until

  def invite(invitation, origin: nil)
    @invitation = invitation
    @url_options = link_origin(origin)

    if @url_options.empty?
      Rails.logger.warn "[ContentSpiel] An invitation mail was not sent: no site address is known. Set PUBLIC_HOST."
      return
    end

    mail subject: t("mail.invite.subject", inviter: inviter_name, site: site_name), to: invitation.email_address
  end

  private

  # Built once (a call signs a new token): both parts carry one link. `port: nil` as the reset's does.
  def invite_url = @invite_url ||= admin_invitation_url(port: nil, **@url_options, anchor: @invitation.generate_token_for(:accept))

  # An invitation with no person behind it (the console, a trusted code path,
  # an inviter deleted since) is the site's own.
  def inviter_name = @invitation.inviter ? PersonName.of(@invitation.inviter) : site_name

  # The invitation's own expiry (`sent_at` + seven days), the date the Users
  # list shows too: never later than the link's own, which counts from when
  # this job made the token. One with no date (a preview) counts from now.
  def valid_until = I18n.l((@invitation.expires_at || Invitation::VALID_FOR.from_now).to_date, format: :long)
end
