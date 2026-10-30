class User < ApplicationRecord
  has_secure_password

  # How long an invitation's link works (spec: seven days). The mail names
  # the date from this, so the token and the sentence cannot disagree.
  INVITE_VALID_FOR = 7.days
  # Signed over `invite_sent_at` and `email_address` (plan Ruling 3,
  # controller ruling F1): a resend moves the time, so the old link dies; a
  # withdrawal deletes the row, so nothing is found; an address corrected in
  # the Users editor (the natural fix of a typo'd invite, which stays
  # allowed) kills the link mailed to the wrong address, which would
  # otherwise set the password of the corrected account for seven days, and
  # a resend mails one that works. Accepting clears `invited_at` but changes
  # NEITHER of the two, so a used link still finds its row and the page can
  # say "already used" rather than "expired". The token is made only by
  # `InvitesMailer`, in the job.
  generates_token_for(:invite, expires_in: INVITE_VALID_FOR) { [ invite_sent_at, email_address ] }

  # Who sent the invite; nulled by the database when they are deleted.
  belongs_to :invited_by, class_name: "User", optional: true
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

  # INVITED PEOPLE (spec "Invites"; plan Ruling 2). An invited person is a
  # row with `invited_at` set and the digest of a random password nobody is
  # told: no way to sign in by any path until they accept. Every place that
  # counts or lists people who can sign in -- sign-in, the reset request, the
  # owner checks, mention suggestions and the deliveries of notes, a group's
  # member picker, the audit log's people filter -- reads `can_sign_in`, and
  # each has a test of its own that an invited row is not there (the plan's
  # "Places"). A new such place does the same. The Users screen alone lists
  # the invited too, with their state.
  scope :can_sign_in, -> { where(invited_at: nil) }
  scope :invited, -> { where.not(invited_at: nil) }

  def invited? = invited_at.present?

  # When the current link stops working: seven days after it was sent.
  def invite_expires_at = invite_sent_at && invite_sent_at + INVITE_VALID_FOR

  # `LOWER(users.email_address)`.
  def self.lowered_email = arel_table[:email_address].lower

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
  #
  # "Another owner" is another owner who can sign in: an invited row is never
  # an owner (`Users::Invite` takes no owner flag, `Users::Save` refuses to
  # make one), and one made so by hand still could not take over. The count
  # is of the OTHER rows, not "more than one", so an invited owner row --
  # which is itself not counted -- never blocks its own demotion or
  # withdrawal while a real owner remains. Every owner row is still locked,
  # self included and in id order, so two concurrent demotions of the last
  # two owners queue behind each other rather than deadlocking.
  def other_owner_remains?
    User.where(owner: true).order(:id).lock.pluck(:id, :invited_at).any? { |other_id, invited_at| other_id != id && invited_at.nil? }
  end
end
