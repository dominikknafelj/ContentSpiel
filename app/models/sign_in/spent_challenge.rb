module SignIn
  # A passkey challenge that has been answered, kept until it could no longer
  # be answered anyway (`PasskeyChallenges`).
  #
  # `spend!` is ONE statement, an insert that does nothing on a duplicate
  # digest (`ON CONFLICT DO NOTHING` on the unique index), and it is judged
  # by whether that statement returned the row. Two sends of one challenge at
  # once meet at the index, so exactly one of them inserts. A database error
  # is not rescued: it reaches the caller as a refusal, never as a spend.
  #
  # An expired row is never a reason to refuse: the digest is of the purpose
  # and a random challenge of 32 bytes, which is never issued twice, so a
  # digest that is still here after its expiry belongs to a challenge that
  # is refused as late anyway.
  class SpentChallenge < ApplicationRecord
    self.table_name = "sign_in_spent_challenges"

    SPENT_PURPOSE = "content_spiel passkey challenge".freeze

    # True for the one take of a value of a purpose: the digest is an HMAC of
    # both, never the value, and is spent by `spend!`. A failed statement or a
    # lost connection is no spend, so the value is refused and only the
    # error's class is logged; any other error is the code's own and is raised.
    def self.take(purpose:, value:, expires_at:)
      digest = VisitorAddress.digest("#{purpose}:#{value}", purpose: SPENT_PURPOSE)
      spend!(digest, expires_at: expires_at)
    rescue ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished => error
      Rails.logger.warn("[sign-in] a value could not be spent (#{error.class}), so it is refused")
      false
    end

    # True when this call inserted the digest, false when it was there.
    def self.spend!(digest, expires_at:)
      insert_all([ { digest: digest, expires_at: expires_at } ], unique_by: :digest, returning: :digest).rows.any? # version: none (a spent mark is sign-in bookkeeping, no page renders it)
    end

    # The rows that can no longer matter, deleted by the sign-in sweep.
    def self.sweep(at: Time.current)
      where(expires_at: ...at).delete_all # version: none (a spent mark is sign-in bookkeeping, no page renders it)
    end
  end
end
