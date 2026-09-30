require "test_helper"
require Rails.root.join("db/migrate/20260929090100_grant_trash_empty_to_admin").to_s

# Global constraints: `trash.empty` is Admin only -- for a fresh install
# (`AccessControl::Seeds`, Admin's `grants: :all` resolves against the live
# registry) and for a group seeded before the permission existed (this data
# migration), the same "belt and suspenders" shape as `GrantMediaManageTo
# BuiltInGroups`.
class GrantTrashEmptyToAdminMigrationTest < ActiveSupport::TestCase
  def migrate(direction) = ActiveRecord::Migration.suppress_messages { GrantTrashEmptyToAdmin.new.migrate(direction) }

  def holders = AccessControl::Grant.where(permission: "trash.empty").joins(:group).pluck("access_control_groups.name").sort

  test "the seeded Admin group holds trash.empty; Editor doesn't" do
    AccessControl::Grant.delete_all
    AccessControl::Membership.delete_all
    AccessControl::Group.delete_all

    groups = AccessControl::Seeds.ensure_built_in_groups!

    assert_equal %w[Admin], holders
    assert_not groups.fetch("Editor").grants.exists?(permission: "trash.empty")
  end

  test "the fixtures agree" do
    assert_equal %w[Admin], holders
  end

  test "the grant migration gives the built-in Admin group trash.empty only" do
    admin = access_control_groups(:admin)
    editor = access_control_groups(:editor)
    AccessControl::Grant.where(permission: "trash.empty").delete_all

    migrate(:up)

    assert admin.grants.exists?(permission: "trash.empty", scope: {})
    assert_not editor.grants.exists?(permission: "trash.empty")

    migrate(:down)
    assert_not admin.grants.exists?(permission: "trash.empty")
  end

  test "up is idempotent and leaves other groups alone" do
    AccessControl::Grant.where(permission: "trash.empty").delete_all
    custom = AccessControl::Group.create!(name: "Trashers (custom)")

    migrate(:up)
    migrate(:up)

    assert_equal %w[Admin], holders
    assert_equal 1, AccessControl::Grant.where(permission: "trash.empty").count
    assert AccessControl::Grant.where(permission: "trash.empty").all? { |grant| grant.scope == {} }
    assert_empty custom.grants
  end
end
