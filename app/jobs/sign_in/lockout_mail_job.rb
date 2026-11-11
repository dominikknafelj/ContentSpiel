module SignIn
  # Mails an account that its sign-in is paused (`SignInMailer#locked`).
  #
  # THE LOOKUP IS HERE, NOT IN THE REQUEST. Sign-in enqueues this job for
  # every account-bucket lock whose hour's mark is new, whether or not an
  # account has the address, so a known and an unknown email do the same
  # work while a bot waits for the answer. The job then finds the account
  # (`User` normalises the address as sign-in counted it) and queues the
  # mail through `ApplicationMailer.queue` only when there is one and mail
  # is ready; otherwise it ends with no line, so nothing logged says
  # whether the address has an account.
  #
  # `log_arguments = false`: the first argument is the email typed, which
  # Active Job would otherwise write into its "Enqueued" and "Performing"
  # lines. The queue's row still holds it, as the reset request's does.
  class LockoutMailJob < ApplicationJob
    self.log_arguments = false

    def perform(email_address, locked_at:, from_address:, minutes:, origin: nil)
      return unless MailSettings.current.ready?

      user = User.find_by(email_address: email_address)
      return unless user

      ApplicationMailer.queue(SignInMailer, :locked, user, locked_at: locked_at, from_address: from_address, minutes: minutes, origin: origin)
    end
  end
end
