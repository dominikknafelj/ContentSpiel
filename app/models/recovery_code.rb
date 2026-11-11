# One of a person's recovery codes: a second proof for when no passkey is at
# hand, used once. Only the code's digest is stored; the code itself is shown
# once, when the set is made, and kept nowhere.
#
# A code is eight characters of Crockford's base32 (the digits and the capital
# letters without I, L, O and U), shown as `XXXX-XXXX`: 40 bits. Its digest is
# an HMAC-SHA256 under a key derived from the application's secret, so a
# stolen database alone gives nothing to try offline; with the secret too,
# 40 bits can be searched, which is the cost of a lookup by digest (a bcrypt
# hash per code would cost ten hashes per attempt).
class RecoveryCode < ApplicationRecord
  belongs_to :user

  COUNT = 10
  ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
  KEY_PURPOSE = "content_spiel recovery code"

  # What a typed code must be once normalised: eight characters of the
  # alphabet, the hyphen gone.
  NORMALISED = /\A[#{ALPHABET}]{8}\z/

  scope :unused, -> { where(used_at: nil) }

  # A fresh set of COUNT distinct codes, as shown to the person.
  def self.texts
    codes = Set.new
    codes << Array.new(8) { ALPHABET[SecureRandom.random_number(ALPHABET.size)] }.join until codes.size == COUNT
    codes.map { |code| "#{code[0, 4]}-#{code[4, 4]}" }
  end

  # The digest a code is stored and found by, however it was typed: capitals
  # or small letters, with or without spaces and the hyphen, O for 0 and I or
  # L for 1 (Crockford's reading). Nil for anything that is not a code once
  # read so, and for anything that is not a String.
  def self.digest(text)
    return unless text.is_a?(String)

    code = text.upcase.gsub(/[\s-]/, "").tr("OIL", "011")
    return unless code.match?(NORMALISED)

    OpenSSL::HMAC.hexdigest("SHA256", key, code)
  end

  def self.key = Rails.application.key_generator.generate_key(KEY_PURPOSE)
  private_class_method :key

  # Uses the code among this relation's (`user.recovery_codes.redeem(text)`):
  # true when an unused one matched and is now used. One UPDATE whose WHERE
  # holds `used_at IS NULL`, so two requests that race with the same code
  # cannot both use it.
  def self.redeem(text, at: Time.current)
    digest = digest(text)
    return false unless digest

    unused.where(digest: digest).update_all(used_at: at) == 1 # version: none (recovery codes are on no public page)
  end
end
