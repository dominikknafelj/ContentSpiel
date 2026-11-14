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

  # Derived from `secret_key_base`: a site whose secret changes holds no
  # code that matches again, and its people make new sets
  # (`docs/reference/hosting.md`, `SECRET_KEY_BASE`).
  def self.key = Rails.application.key_generator.generate_key(KEY_PURPOSE)
  private_class_method :key

  # Uses one of an account's codes: `user.recovery_codes.redeem(text)`, true
  # when an unused one matched and is now used. It is an extension of the
  # association (`User`'s `has_many :recovery_codes`) and nothing else, so no
  # caller can redeem a code by its digest alone, without its account. One
  # UPDATE whose WHERE holds `used_at IS NULL`, so two requests that race with
  # the same code cannot both use it.
  module Redeem
    def redeem(text, at: Time.current)
      digest = RecoveryCode.digest(text)
      return false unless digest

      unused.where(digest: digest).update_all(used_at: at) == 1 # version: none (recovery codes are on no public page)
    end

    # Whether `text` is one of the account's unused codes, using none: the
    # same digest and an indexed read where `redeem` would write, for a proof
    # that is checked but may not let its person in (`SignIn::Proof`, a
    # refusal by rule).
    def unused_code?(text)
      digest = RecoveryCode.digest(text)
      return false unless digest

      unused.exists?(digest: digest)
    end
  end
end
