# A reset request, decided out of the request (`Admin::PasswordsController#create`):
# the account the address typed belongs to, if any, gets the reset mail,
# queued through `ApplicationMailer.queue` with the origin the request
# handed over (`Admin::MailLinkOrigin`). An address with no account ends the
# job with no line, so nothing logged says whether it has one.
#
# Mail that stopped being ready between the request and the job (the
# request is closed while it isn't, `require_mail_ready`) ends it too, with
# no line, as a request made then would have sent nothing; the lock-out
# mail's job asks the same.
#
# `log_arguments = false`: the first argument is the address typed, which
# Active Job would otherwise write into its "Enqueued" and "Performing"
# lines. The queue's row still holds it.
#
# A NUL byte is no address of an account, and Postgres refuses one in a
# query's text, so the lookup is skipped for it rather than failing the job.
class PasswordResetRequestJob < ApplicationJob
  self.log_arguments = false

  def perform(email_address, origin: nil)
    return unless MailSettings.current.ready?
    return if email_address.include?("\0")

    user = User.find_by(email_address: email_address)
    return unless user

    ApplicationMailer.queue(PasswordsMailer, :reset, user, **{ origin: origin }.compact)
  end
end
