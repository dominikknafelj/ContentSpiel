class ApiToken < ApplicationRecord
  has_secure_password :token, validations: false

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
    token = create!(user: user, group: group, name: name.nil? ? next_default_name(user) : name, token: raw_token)
    [ token, raw_token ]
  end

  # "Token N" with N one past the user's token count (the backfill's own
  # numbering), moving on while that name is taken by an active token.
  def self.next_default_name(user)
    number = where(user_id: user.id).count
    number += 1 while active.where(user_id: user.id).exists?([ "LOWER(name) = LOWER(?)", "Token #{number + 1}" ])
    "Token #{number + 1}"
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
    errors.add(:name, "is already the name of one of this user's active tokens") if taken
  end
end
