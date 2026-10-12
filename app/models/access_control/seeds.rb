module AccessControl
  # The four seeded groups (design spec §5, exact names per Global
  # Constraints) and the one-time backfill of existing data onto the new
  # access-control columns (design spec §6). Two call sites:
  # `db/migrate/20260928060000_seed_access_control_groups.rb` (the data
  # migration) and `db/seeds.rb` (dev seeds, via `ensure_built_in_groups!`
  # alone -- there's nothing to backfill in a fresh dev database).
  #
  # Built on the real `AccessControl::Group`/`Membership`/`Grant`/`User`/
  # `ApiToken`/`Post` models, not migration-local SQL-only shadow classes.
  # The usual reason to avoid that in a data migration -- a later change to
  # those models silently breaking this migration when it's replayed
  # against an old schema/app-code combination -- doesn't apply here: this
  # is a pre-production app with no data anyone needs to keep (dev/test
  # databases only, freely recreatable), so this migration is never
  # replayed against anything but the schema and app code it shipped
  # alongside. Using the real models also means `ensure_built_in_groups!`/
  # `backfill!` share the exact same validations (`Grant`'s scope checks,
  # `Group`'s uniqueness) as everything else that touches these tables.
  module Seeds
    ADMIN_NAME = "Admin"
    EDITOR_NAME = "Editor"
    AUTHOR_NAME = "Author"
    READ_ONLY_NAME = "Read only"

    # The §5 table as data. `grants: :all` (Admin only) means "every
    # built-in permission, unscoped" -- resolved live against
    # `AccessControl::Permissions.keys` in `ensure_built_in_groups!` below,
    # rather than listed out by hand, so Admin never drifts out of sync
    # with whatever the registry currently holds. Every other group's
    # grants are listed explicitly: unlike Admin they're a deliberate
    # subset, not "whatever's registered".
    BUILT_IN = {
      ADMIN_NAME => {
        description: "Every permission, unscoped.",
        grants: :all
      },
      EDITOR_NAME => {
        description: "Full, unscoped access to posts and pages, plus tags and media.",
        grants: [
          { permission: "posts.read", scope: {} },
          { permission: "posts.create", scope: {} },
          { permission: "posts.edit", scope: {} },
          { permission: "posts.publish", scope: {} },
          { permission: "posts.delete", scope: {} },
          { permission: "pages.read", scope: {} },
          { permission: "pages.create", scope: {} },
          { permission: "pages.edit", scope: {} },
          { permission: "pages.publish", scope: {} },
          { permission: "pages.move", scope: {} },
          { permission: "pages.delete", scope: {} },
          { permission: "tags.manage", scope: {} },
          { permission: "media.upload", scope: {} },
          # Added with the media library (design spec §5.1); an install
          # seeded before that gets it from a data migration instead
          # (`GrantMediaManageToBuiltInGroups`).
          { permission: "media.manage", scope: {} },
          # Translation helpers spec §7; an install seeded before that gets
          # it from `GrantAiTranslateToBuiltInGroups`.
          { permission: "ai.translate", scope: {} }
        ]
      },
      AUTHOR_NAME => {
        description: "Own posts, read-only pages.",
        grants: [
          { permission: "posts.read", scope: {} },
          { permission: "posts.create", scope: {} },
          { permission: "posts.edit", scope: { "own" => true } },
          { permission: "media.upload", scope: {} },
          { permission: "pages.read", scope: {} }
        ]
      },
      READ_ONLY_NAME => {
        description: "Read-only access to posts and pages.",
        grants: [
          { permission: "posts.read", scope: {} },
          { permission: "pages.read", scope: {} }
        ]
      }
    }.freeze

    class << self
      # Idempotent by name (design spec §6: "seed the four groups
      # (idempotent, by name)") -- safe to call from both the data
      # migration and, indirectly through it, a `db:migrate` re-run against
      # a database that already has them. Returns the Hash name -> group
      # (interface, Task 2 brief), so a caller (dev seeds, this file's own
      # tests) never has to re-look them up by name afterwards.
      def ensure_built_in_groups!
        BUILT_IN.each_with_object({}) do |(name, definition), groups|
          group = Group.find_or_create_by!(name: name) do |new_group|
            new_group.description = definition[:description]
            new_group.built_in = true
          end

          grants_for(definition).each do |grant_attributes|
            group.grants.find_or_create_by!(permission: grant_attributes[:permission]) do |grant|
              grant.scope = grant_attributes[:scope]
            end
          end

          groups[name] = group
        end
      end

      # The one-time data migration (design spec §6): every existing user
      # becomes an owner, every existing token gets the Admin group, and
      # every existing post gets the first owner (lowest id) as author.
      #
      # Only for that migration -- never call it on a live install: the
      # first step promotes *every* non-owner, so a second call would make
      # an owner of every user created or demoted since (final fix wave,
      # Minor 7). The token and post steps are guarded (`where(...: nil)`)
      # and leave values set since alone; the owner step can't be, since
      # "not an owner" is exactly what it changes.
      def backfill!
        User.where(owner: false).update_all(owner: true) # changes: none (a user, not a page or post)

        admin = Group.find_by!(name: ADMIN_NAME)
        ApiToken.where(group_id: nil).update_all(group_id: admin.id) # changes: none (a token, not a page or post)

        first_owner = User.where(owner: true).order(:id).first
        Post.where(author_id: nil).update_all(author_id: first_owner.id) if first_owner # version: none (the public site shows no author) # changes: none (an author is not in a copy)
      end

      private

      def grants_for(definition)
        return definition[:grants] unless definition[:grants] == :all

        Permissions.keys.map { |key| { permission: key, scope: {} } }
      end
    end
  end
end
