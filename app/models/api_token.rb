class ApiToken < ApplicationRecord
  has_secure_password :token, validations: false

  def self.generate!
    raw_token = SecureRandom.hex(32)
    token = create!(token: raw_token)
    [ token, raw_token ]
  end

  def self.authenticate(raw_token)
    active.find { |candidate| candidate.authenticate_token(raw_token) }
  end

  def self.active
    where(revoked_at: nil)
  end

  def revoke!
    update!(revoked_at: Time.current)
  end
end
