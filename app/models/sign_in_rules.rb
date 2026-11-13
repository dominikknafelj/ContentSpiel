# Who may sign in with what, by rule rather than by credential: a linked
# account (`User#sso_linked?`) signs in through its provider alone, with
# single sign-on on or off (the link, not the provider, decides: the way
# back is `Sso::Unlink`), and while `SSO_REQUIRED` is set
# (`SignIn::Oidc.required?`) so does every non-owner. An owner keeps a
# password and a passkey always: owners never link, and no outside service
# stands in for them.
#
# A REFUSAL BY RULE LOOKS LIKE A WRONG PASSWORD EVERYWHERE A BOT CAN SEE IT,
# so the rule tells nobody which accounts are linked, or that an address has
# an account at all. The places:
#
# - the password's answer: `SignIn::PasswordAttempt` (`allowed:`) checks the
#   right password through the same `authenticate_by`, then answers
#   `:refused` as for a wrong one, with the count its reservation already
#   made in the account's bucket, the same statements (the account is
#   dropped before `auth.account_exists` is asked, so that is asked by the
#   same query too) and the same span. The controller then audits
#   `session.failed` and redirects with the one sentence, as for any
#   refusal (test/integration/sign_in_throttles_test.rb);
# - a passkey's answer, at sign-in and at the second step: the wrong
#   passkey's (`passkey_failed`), from `passkey_allowed?`;
# - the reset request: its page is answered before anyone is looked up, and
#   `PasswordResetRequestJob` mails the reminder (`reminder_instead_of_reset?`)
#   to the account's own address only, in place of the reset link
#   (test/controllers/admin/passwords_controller_test.rb).
#
# The services that set a password or add a second factor refuse a linked
# account in words (`Users::Save`, `Users::UpdatePassword`, `Passkeys::Add`,
# `RecoveryCodes::Generate`): they are asked by someone already signed in,
# after their own authorization, so their answer tells nobody outside.
#
# It names no controller, route or request: the controllers ask it.
module SignInRules
  def self.password_allowed?(user) = !user.sso_linked? && (user.owner? || !SignIn::Oidc.required?)

  # The same rule: a passkey is a second way in that never asks the provider.
  def self.passkey_allowed?(user) = password_allowed?(user)

  # Whether a reset request for `user` is answered with the reminder to sign
  # in with the provider: linked, or a non-owner while SSO is required.
  def self.reminder_instead_of_reset?(user) = !password_allowed?(user)

  # The provider's name as a sentence says it to someone signed in: the
  # configured `SSO_NAME`, else (single sign-on off, the account still
  # linked) the host the account was linked under.
  def self.provider_name(user) = SignIn::Oidc::Provider.current&.name || SignIn::Oidc.issuer_host(user.sso_issuer)
end
