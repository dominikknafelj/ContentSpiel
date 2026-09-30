# Fresh installs get `trash.empty` from `AccessControl::Seeds` (Admin's
# `grants: :all` resolves against the live registry); this backfills an
# already-seeded Admin group, like `GrantMediaManageToBuiltInGroups`. Admin
# only (trash spec §6): emptying the trash is the one irreversible bulk action.
class GrantTrashEmptyToAdmin < ActiveRecord::Migration[8.1]
  def up
    admin_groups.find_each do |group|
      group.grants.find_or_create_by!(permission: "trash.empty") { |grant| grant.scope = {} }
    end
  end

  def down
    AccessControl::Grant.where(group: admin_groups, permission: "trash.empty", scope: {}).delete_all
  end

  private

  def admin_groups = AccessControl::Group.where(built_in: true, name: AccessControl::Seeds::ADMIN_NAME)
end
