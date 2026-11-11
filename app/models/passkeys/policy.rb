module Passkeys
  # Who must sign in with a passkey (`SiteSetting#effective_passkey_policy`):
  # `nobody`; `owners_and_admins`, the owners and whoever holds one of
  # ADMIN_PERMISSIONS on CS Studio; or `everyone`.
  #
  # The policy is read at sign-in (`Session.start`'s `enrolment_due`), so a
  # change reaches a person at their next session, never the one they are in.
  # `Passkeys::Remove` reads it at the moment of removal, so a covered person
  # keeps at least one passkey.
  class Policy
    # The rights that make someone an admin here: whoever can make accounts,
    # hand out rights or issue tokens can take over the site.
    ADMIN_PERMISSIONS = %w[users.manage groups.manage tokens.manage].freeze

    # The console, jobs and model tests run with no request's site.
    def self.current(site: Current.site || SiteSetting.instance) = new(site.effective_passkey_policy)

    attr_reader :name

    def initialize(name)
      @name = name
    end

    def covers?(user)
      case name
      when "everyone" then true
      when "owners_and_admins" then user.owner? || ADMIN_PERMISSIONS.any? { |key| AccessControl.holds?(user, key, channel: :admin) }
      else false
      end
    end

    def covers_owners? = name != "nobody"

    def enrolment_due?(user) = covers?(user) && !user.passkeys.exists?

    # The covered people who hold no passkey. Counted in Ruby over the
    # passkey-less users, since whether someone is an admin is a rights
    # question for `AccessControl`, not a column; a site has tens of users.
    def uncovered_count
      return 0 if name == "nobody"

      User.where.missing(:passkeys).to_a.count { |user| covers?(user) }
    end
  end
end
