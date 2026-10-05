class ApiToken < ApplicationRecord
  # The raw token is 256 random bits shown once and never stored. What is
  # stored is `lookup_digest`, its SHA-256 hex digest (unique index), so a
  # presented token is found by one indexed equality instead of a bcrypt
  # compare against every active token. A fast digest is enough because the
  # input is random, not a chosen password. Rows from before the digest
  # existed hold "revoked:<id>", which no value can hash to. The digest is a
  # credential-equivalent for lookup purposes: it is on
  # `Audit::Snapshot::NEVER_STORED`, never rendered and never logged.
  # Bound to the admin it authenticates as for MCP purposes (design spec
  # section 10 revisited): v1 shipped one global token with no user at all.
  # An MCP client holding this token inherits that user's full authoring
  # identity, so attributing and independently revoking it is worth the FK
  # even with a single admin today.
  belongs_to :user

  # Access-control design spec §3.2: "a foreign key to access_control_
  # groups, not null." `belongs_to` alone would already require it on save;
  # named explicitly (`class_name:`, not just `belongs_to :group`) since
  # the association points at a namespaced model, and there's no
  # `AccessControl` prefix on the association name itself to infer it from.
  belongs_to :group, class_name: "AccessControl::Group"

  MAX_NAME_LENGTH = 60

  # The name a person picks the token out of a list by, and what the audit
  # log says ("via <name>", `Audit::Event#via_label`) -- round 3 decision D2.
  # Unique per user among *active* tokens, so a revoked token's name is free
  # to reuse; compared case-insensitively.
  normalizes :name, with: ->(name) { name.to_s.strip }
  validates :name, presence: true, length: { maximum: MAX_NAME_LENGTH }
  validate :name_unique_among_active_tokens

  # `group:` defaults to the built-in Admin group (ruling R1, Task 2 brief)
  # for tests and the console that just want *a* token. The app itself
  # always goes through `ApiTokens::Issue`, where the group is required and
  # checked (design spec §3.3 "Tokens").
  #
  # `name: nil` means "I don't care": the next free "Token N" for that user
  # (so tests and the console need not invent names). A String is taken as
  # given and validated -- a blank one is an error, never a silent default.
  def self.generate!(user, group: AccessControl::Group.find_by!(name: AccessControl::Seeds::ADMIN_NAME), name: nil)
    raw_token = SecureRandom.hex(32)
    attempts = 0
    begin
      # A savepoint, so losing the unique-index race (below) doesn't poison
      # an enclosing Postgres transaction and the retry can still run.
      token = transaction(requires_new: true) do
        create!(user: user, group: group, name: name.nil? ? next_default_name(user) : name, lookup_digest: digest(raw_token))
      end
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => error
      # Only a generated name is retried, and only when the NAME is what
      # clashed (`.name_taken?`): a concurrent create took "Token N" between
      # our look and our insert, so look again. A name the caller chose is
      # theirs to fix, and any other failure (a missing group, another unique
      # index) would fail the same way every time -- it is raised at once
      # rather than five times over.
      raise unless name.nil? && name_taken?(error) && (attempts += 1) < 5

      retry
    end
    [ token, raw_token ]
  end

  # The partial unique index behind `name_unique_among_active_tokens`
  # (`db/schema.rb`): the backstop for two creates racing past the validation.
  NAME_INDEX = "index_api_tokens_on_user_and_lower_name_active".freeze
  NAME_TAKEN = "is already the name of one of this user's active tokens".freeze

  # Whether `error` (from saving a token) says the name is already an active
  # token's: the unique index named in the database's message, or a validation
  # failure on `name`. `ApiTokens::Issue` and `.generate!` both ask, so "the
  # name was taken" is never read into a failure that is about something else.
  def self.name_taken?(error)
    case error
    when ActiveRecord::RecordNotUnique then error.message.include?(NAME_INDEX)
    when ActiveRecord::RecordInvalid then error.record.is_a?(ApiToken) && error.record.errors.added?(:name, NAME_TAKEN)
    else false
    end
  end

  # "Token N" with N one past the user's token count (the backfill's own
  # numbering), moving on while that name is taken by an active token.
  def self.next_default_name(user)
    number = where(user_id: user.id).count
    number += 1 while active.where(user_id: user.id).exists?([ "LOWER(name) = LOWER(?)", "Token #{number + 1}" ])
    "Token #{number + 1}"
  end

  def self.digest(raw_token)
    OpenSSL::Digest::SHA256.hexdigest(raw_token.to_s)
  end

  # One indexed lookup on the digest of what was presented, however many
  # tokens exist; the digests are then compared again in constant time so the
  # answer never rests on the database's comparison alone. Blank is nil
  # without a query.
  def self.authenticate(raw_token)
    return if raw_token.to_s.strip.empty?

    wanted = digest(raw_token)
    candidate = active.find_by(lookup_digest: wanted)
    candidate if candidate && ActiveSupport::SecurityUtils.secure_compare(candidate.lookup_digest, wanted)
  end

  def self.active
    where(revoked_at: nil)
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  # Mirrors Session's own ip_address tracking (Authentication#start_new_session_for)
  # -- visibility into a bearer credential used unattended by an MCP client,
  # not just at creation.
  def record_usage!(ip_address)
    update!(last_used_at: Time.current, last_used_ip: ip_address)
  end

  private

  def name_unique_among_active_tokens
    return if name.blank? || revoked_at

    taken = ApiToken.active.where(user_id: user_id).where.not(id: id).exists?([ "LOWER(name) = LOWER(?)", name ])
    errors.add(:name, NAME_TAKEN) if taken
  end
end
