class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :api_tokens, dependent: :destroy
  has_many :memberships, class_name: "AccessControl::Membership", dependent: :destroy
  has_many :groups, through: :memberships, class_name: "AccessControl::Group"

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  MINIMUM_PASSWORD_LENGTH = 12

  # Design pass spec §5.5. `allow_nil` is what keeps existing shorter
  # passwords working: `password` is only non-nil while one is being set,
  # so the rule applies to setup, new user, change and reset -- never to a
  # save that leaves the password alone. Length counts characters, not
  # bytes (Ruby's String#length), so twelve multibyte characters pass.
  # The message is a whole sentence; config/locales/en.yml drops the
  # "Password " prefix for this attribute so `full_messages` reads the same.
  validates :password, length: { minimum: MINIMUM_PASSWORD_LENGTH, message: "Use at least 12 characters." }, allow_nil: true

  # Optional (design pass spec §5.1): shown wherever a user is named, with
  # the email as the fallback -- `display_name` is the one reader, so no
  # screen decides the fallback for itself. A blank name is stored as nil,
  # so "no name" has one representation.
  normalizes :name, with: ->(name) { name.to_s.strip.presence }
  validates :name, length: { maximum: 120 }

  # Presence here so the setup wizard shows a form error; uniqueness backs up
  # the unique index with a readable message instead of an exception.
  # `normalizes` above already downcases every stored value, which is what
  # makes this comparison case-insensitive without a second `LOWER(...)`
  # index or a case-sensitivity option here.
  validates :email_address, presence: true, uniqueness: true

  # The users whose name or email address contains this text, whatever the
  # case; a typed `%` or `_` is a character to find, not a wildcard. A user
  # without a name is found by the address alone.
  scope :name_or_email_containing, ->(text) {
    where("LOWER(users.name) LIKE :any OR LOWER(users.email_address) LIKE :any", any: "%#{sanitize_sql_like(text.to_s.downcase)}%")
  }
  # Ordering: the users whose name or address STARTS with this text ahead of
  # the rest.
  scope :name_or_email_starting_first, ->(text) {
    order(Arel.sql(sanitize_sql_array([
      "(COALESCE(LOWER(users.name), '') LIKE :prefix OR LOWER(users.email_address) LIKE :prefix) DESC",
      { prefix: "#{sanitize_sql_like(text.to_s.downcase)}%" }
    ])))
  }
  # Ordering: by address, capitals and small letters together.
  scope :by_email, -> { order(Arel.sql("LOWER(users.email_address) ASC")) }

  # `prepend: true` (final fix wave, P16; still needed now that this checks
  # owners rather than "any user" -- access-control design spec §3.2/§6):
  # `has_many ..., dependent: :destroy` above registered its own
  # `before_destroy` callbacks first, so without it a refused delete would
  # already have destroyed this user's sessions and tokens (rolled back
  # with the transaction, but only after doing the work and firing their
  # callbacks).
  before_destroy :ensure_not_last_owner, prepend: true

  # Demoting the last owner (`owner: true -> false`) is refused the same
  # way deleting them is (design spec §3.2: "At least one owner must always
  # exist"). "Only owners may change owner" is the other half of that
  # sentence -- an authorization rule `Users::Save` enforces, not
  # something a model validation can see (it has no notion of
  # who's making the change); this validation only guards the invariant
  # itself, regardless of who's doing the demoting.
  validate :at_least_one_owner, if: :demoting_from_owner?

  def display_name = name.presence || email_address

  private

  # Owner is the only privilege with no group behind it (design spec §2:
  # "Owner is a protected user flag, not a group") -- destroying the last
  # one would leave nobody able to grant it back, since only an owner may.
  # This replaces the old "last user" guard (any user, owner or not, used
  # to be deletable as long as one remained; there were no owners yet). A
  # non-owner is never blocked here, however few users remain.
  # `throw :abort` (rather than a plain `errors.add`, which `before_destroy`
  # alone doesn't stop anything on) is what actually halts the destroy;
  # `Users::Destroy` reports this same message back through its `Result`,
  # via `record.errors.full_messages` (`ApplicationService::Result.failure`'s
  # own default).
  def ensure_not_last_owner
    return unless owner?
    return if other_owner_remains?

    errors.add(:base, "The last owner can't be deleted")
    throw :abort
  end

  def demoting_from_owner?
    owner_changed? && owner_was && !owner
  end

  def at_least_one_owner
    return if other_owner_remains?

    errors.add(:owner, "can't demote the last owner")
  end

  # Counted under a row lock (final fix wave, P16, carried over unchanged
  # by the access-control migration): both callers above run inside their
  # own transaction, and `SELECT ... FOR UPDATE` on every owner row makes a
  # second, concurrent demote-or-delete of the other remaining owner wait
  # until the first commits -- at which point Postgres re-reads and this
  # check sees the truth. A plain `User.where(owner: true).count` would let
  # two operations against the last two owners each see "2" and both go
  # through. (Postgres doesn't allow `FOR UPDATE` with an aggregate, hence
  # `pluck(:id)` rather than `count`.) `self` is still counted here: its
  # `owner` column hasn't been written yet (destroy hasn't deleted the row,
  # and the demoting update hasn't saved), so ">1" correctly reads as "at
  # least one other owner besides me."
  def other_owner_remains?
    User.where(owner: true).lock.pluck(:id).size > 1
  end
end
