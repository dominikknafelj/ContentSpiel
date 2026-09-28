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

  # `group:` defaults to the built-in Admin group (ruling R1, Task 2 brief)
  # -- an interim stand-in for "the caller chooses, and only among groups
  # they may assign" (design spec §3.3), which a later task makes required
  # and checked. Every existing caller (the setup wizard's MCP-token step,
  # CS Studio's "Create token", every test that just wants *a* token) keeps
  # working unchanged in the meantime by getting Admin, same as it would
  # have before groups existed at all.
  def self.generate!(user, group: AccessControl::Group.find_by!(name: AccessControl::Seeds::ADMIN_NAME))
    raw_token = SecureRandom.hex(32)
    token = create!(user: user, group: group, token: raw_token)
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

  # Mirrors Session's own ip_address tracking (Authentication#start_new_session_for)
  # -- visibility into a bearer credential used unattended by an MCP client,
  # not just at creation.
  def record_usage!(ip_address)
    update!(last_used_at: Time.current, last_used_ip: ip_address)
  end
end
