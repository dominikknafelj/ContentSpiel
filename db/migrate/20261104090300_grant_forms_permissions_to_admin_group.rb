# Grants the two new forms rights (forms spec, decision 10: "both new
# permissions held by the Admin group by default") to an Admin group seeded
# before they existed. A fresh install gets them from `AccessControl::Seeds`
# itself (Admin's `grants: :all` resolves against the grantable part of the
# live registry). `forms.submit` is not granted: it is the visitor's alone
# and no group may hold it (`AccessControl::Permissions.grantable`). The same
# shape as `GrantTrashEmptyToAdmin`: the real models, and only a group still
# flagged `built_in` under its seeded name.
class GrantFormsPermissionsToAdminGroup < ActiveRecord::Migration[8.1]
  PERMISSIONS = %w[forms.manage form_submissions.view].freeze

  def up
    admin_groups.find_each do |group|
      PERMISSIONS.each do |permission|
        group.grants.find_or_create_by!(permission: permission) { |grant| grant.scope = {} }
      end
    end
  end

  # Removes the unscoped grants from that group again, including one an
  # admin added by hand after this ran (acceptable in a pre-production app).
  def down
    AccessControl::Grant.where(group: admin_groups, permission: PERMISSIONS, scope: {}).delete_all
  end

  private

  def admin_groups = AccessControl::Group.where(built_in: true, name: AccessControl::Seeds::ADMIN_NAME)
end
