class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :api_tokens, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  # Presence here so the setup wizard shows a form error; uniqueness backs up
  # the unique index with a readable message instead of an exception.
  # `normalizes` above already downcases every stored value, which is what
  # makes this comparison case-insensitive without a second `LOWER(...)`
  # index or a case-sensitivity option here.
  validates :email_address, presence: true, uniqueness: true

  # `prepend: true` (final fix wave, P16): `has_many ..., dependent:
  # :destroy` above registered its own `before_destroy` callbacks first, so
  # without it a refused delete would already have destroyed this user's
  # sessions and tokens (rolled back with the transaction, but only after
  # doing the work and firing their callbacks).
  before_destroy :ensure_not_last_owner, prepend: true

  private

  # Users are the only way into CS Studio (there are no roles yet -- the
  # spec defers those), so destroying the last one would lock everyone out
  # with no console-free way back in.
  # `throw :abort` (rather than a plain `errors.add`, which `before_destroy`
  # alone doesn't stop anything on) is what actually halts the destroy;
  # `Users::Destroy` reports this same message back through its `Result`,
  # via `record.errors.full_messages` (`ApplicationService::Result.failure`'s
  # own default).
  #
  # Counted under a row lock (final fix wave, P16): `destroy` runs this
  # inside its own transaction, and `SELECT ... FOR UPDATE` on every user
  # row makes a second, concurrent delete wait until the first commits --
  # at which point Postgres re-reads, no longer sees the deleted row, and
  # this check refuses. A plain `User.count` would let two deletes of the
  # last two users each see "2" and both go through. (Postgres doesn't
  # allow `FOR UPDATE` with an aggregate, hence ids rather than `count`.)
  def ensure_not_last_owner
    return if User.lock.pluck(:id).size > 1

    errors.add(:base, "The last user can't be deleted")
    throw :abort
  end
end
