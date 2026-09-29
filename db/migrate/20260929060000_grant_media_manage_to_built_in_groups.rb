# Grants the new `media.manage` permission (media library design spec §5.1:
# "Seeds: Admin and Editor get `media.manage`") to the two built-in groups
# on an install whose groups were seeded before it existed -- a fresh
# install gets it from `AccessControl::Seeds::BUILT_IN` itself (Admin via
# `grants: :all`, Editor listed explicitly).
#
# Idempotent: `find_or_create_by!` per group, so re-running it (or running
# it after `db/seeds.rb` already added the grant) changes nothing. Only the
# groups still flagged `built_in` under their seeded names are touched --
# a renamed group isn't the seeded one any more, and a custom group called
# "Editor" isn't ours to widen. See `AccessControl::Seeds` for why a data
# migration here goes through the real models.
class GrantMediaManageToBuiltInGroups < ActiveRecord::Migration[8.1]
  GROUP_NAMES = [ AccessControl::Seeds::ADMIN_NAME, AccessControl::Seeds::EDITOR_NAME ].freeze

  def up
    built_in_groups.find_each do |group|
      group.grants.find_or_create_by!(permission: "media.manage") { |grant| grant.scope = {} }
    end
  end

  # Removes the unscoped grant from those same groups again -- including
  # one an admin added by hand after this ran, which is indistinguishable
  # from ours (acceptable in a pre-production app; see `AccessControl::
  # Seeds`).
  def down
    AccessControl::Grant.where(group: built_in_groups, permission: "media.manage", scope: {}).delete_all
  end

  private

  def built_in_groups = AccessControl::Group.where(built_in: true, name: GROUP_NAMES)
end
