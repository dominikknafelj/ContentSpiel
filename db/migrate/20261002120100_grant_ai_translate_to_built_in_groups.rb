# Grants the new `ai.translate` permission (translation helpers spec §7:
# "seeded onto Admin and Editor") to the two built-in groups on an install
# whose groups were seeded before it existed -- a fresh install gets it from
# `AccessControl::Seeds::BUILT_IN` itself (Admin via `grants: :all`, Editor
# listed explicitly). The same shape as `GrantMediaManageToBuiltInGroups`;
# see there (and `AccessControl::Seeds`) for why a data migration here goes
# through the real models and touches only groups still flagged `built_in`
# under their seeded names.
class GrantAiTranslateToBuiltInGroups < ActiveRecord::Migration[8.1]
  GROUP_NAMES = [ AccessControl::Seeds::ADMIN_NAME, AccessControl::Seeds::EDITOR_NAME ].freeze

  def up
    built_in_groups.find_each do |group|
      group.grants.find_or_create_by!(permission: "ai.translate") { |grant| grant.scope = {} }
    end
  end

  # Removes the unscoped grant from those same groups again -- including one
  # an admin added by hand after this ran, which is indistinguishable from
  # ours (acceptable in a pre-production app).
  def down
    AccessControl::Grant.where(group: built_in_groups, permission: "ai.translate", scope: {}).delete_all
  end

  private

  def built_in_groups = AccessControl::Group.where(built_in: true, name: GROUP_NAMES)
end
