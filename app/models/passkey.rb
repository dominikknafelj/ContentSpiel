# One of a person's passkeys: a WebAuthn credential registered to their
# account. `external_id` is the credential id and `public_key` the COSE key,
# both base64url, as the authenticator handed them over at registration;
# `sign_count` is the authenticator's counter at its last use (a synced
# passkey's stays 0). Neither the id nor the key reaches a page, a span, an
# audit snapshot (`Audit::Snapshot` names a passkey's fields) or production's
# log, which holds no SQL; development's and test's SQL log prints the id
# among a statement's values.
class Passkey < ApplicationRecord
  belongs_to :user

  # A passkey's name, typed by its person when they add it ("MacBook",
  # "Phone"): the longest the dialog's field takes.
  NAME_LIMIT = 60

  normalizes :name, with: ->(name) { name.to_s.strip }
  validates :name, presence: true, length: { maximum: NAME_LIMIT }

  # Records a use: the authenticator's new counter and when. `update_columns`,
  # so `updated_at` stays the time the passkey itself last changed (a rename).
  def used!(sign_count:, at: Time.current)
    update_columns(sign_count: sign_count, last_used_at: at) # version: none (passkeys are on no public page)
  end

  # The random handle the authenticator keeps for the account
  # (`User#webauthn_handle!`), never the email.
  def user_handle = user.webauthn_id
end
