class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :api_tokens, dependent: :destroy
  has_many :memberships, class_name: "AccessControl::Membership", dependent: :destroy
  has_many :groups, through: :memberships, class_name: "AccessControl::Group"
  # A passkey or a recovery code is nothing without its account, and neither
  # has a callback, so they go in one statement each.
  has_many :passkeys, dependent: :delete_all # version: none (passkeys are on no public page)
  has_many :recovery_codes, dependent: :delete_all, extend: RecoveryCode::Redeem # version: none (recovery codes are on no public page)

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  MINIMUM_PASSWORD_LENGTH = 12

  # `allow_nil` is what keeps existing shorter
  # passwords working: `password` is only non-nil while one is being set,
  # so the rule applies to setup, new user, change and reset -- never to a
  # save that leaves the password alone. Length counts characters, not
  # bytes (Ruby's String#length), so twelve multibyte characters pass.
  # The message is a whole sentence; config/locales/en.yml drops the
  # "Password " prefix for this attribute so `full_messages` reads the same.
  validates :password, length: { minimum: MINIMUM_PASSWORD_LENGTH, message: "Use at least 12 characters." }, allow_nil: true

  # Optional: shown wherever a user is named, with
  # the email as the fallback -- `name_or_email` is the one reader, so no
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
    any = SqlNodes.like_pattern(text.to_s.downcase)
    where(SqlNodes.like(arel_table[:name].lower, any).or(SqlNodes.like(lowered_email, any)))
  }
  # Ordering: the users whose name or address STARTS with this text ahead of
  # the rest (`(... LIKE 'text%' OR ...) DESC`: true sorts before false). The
  # COALESCE keeps a user without a name false rather than NULL, which DESC
  # would sort first.
  scope :name_or_email_starting_first, ->(text) {
    prefix = SqlNodes.like_pattern(text.to_s.downcase, prefix: true)
    order(SqlNodes.like(SqlNodes.coalesce(arel_table[:name].lower, ""), prefix).or(SqlNodes.like(lowered_email, prefix)).desc)
  }
  # Ordering: by address, capitals and small letters together.
  scope :by_email, -> { order(lowered_email.asc) }

  # `LOWER(users.email_address)`.
  def self.lowered_email = arel_table[:email_address].lower

  # `prepend: true` (this checks owners rather than "any user"):
  # `has_many ..., dependent: :destroy` above registered its own
  # `before_destroy` callbacks first, so without it a refused delete would
  # already have destroyed this user's sessions and tokens (rolled back
  # with the transaction, but only after doing the work and firing their
  # callbacks).
  before_destroy :ensure_not_last_owner, prepend: true

  # Demoting the last owner (`owner: true -> false`) is refused the same
  # way deleting them is ("At least one owner must always
  # exist"). "Only owners may change owner" is the other half of that
  # sentence -- an authorization rule `Users::Save` enforces, not
  # something a model validation can see (it has no notion of
  # who's making the change); this validation only guards the invariant
  # itself, regardless of who's doing the demoting.
  validate :at_least_one_owner, if: :demoting_from_owner?

  def name_or_email = name.presence || email_address

  # The sessions of this user that are open at `at` (not past either
  # timeout), and how many.
  def open_sessions(at = Time.current) = sessions.live(at)
  def open_session_count(at = Time.current) = open_sessions(at).count

  # Whether the account has a second proof beside its password: a passkey,
  # or a recovery code not yet used. An account that has one is never signed
  # in by its password alone.
  def second_factor? = passkeys.exists? || recovery_codes.unused.exists?

  # The random user handle an authenticator keeps for this account in place
  # of its email (WebAuthn's `user.id`), made at the first ask and kept, so
  # every passkey of the account carries the same one. Written only where the
  # row has none yet and then read back, so two first asks at once (two tabs
  # adding a passkey) both answer the one handle that was stored, never each
  # its own.
  def webauthn_handle!
    if webauthn_id.nil?
      User.where(id: id, webauthn_id: nil).update_all(webauthn_id: WebAuthn.generate_user_id) # version: none (a user's handle is on no public page)
      self[:webauthn_id] = User.where(id: id).pick(:webauthn_id)
      clear_attribute_changes([ :webauthn_id ])
    end
    webauthn_id
  end

  private

  # Owner is the only privilege with no group behind it ("Owner is a protected user flag, not a
  # group") -- destroying the last
  # one would leave nobody able to grant it back, since only an owner may.
  # A non-owner is never blocked here, however few users remain.
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

  # Counted under a row lock : both callers above run inside their
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
