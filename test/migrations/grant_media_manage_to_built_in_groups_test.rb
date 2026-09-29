require "test_helper"
require Rails.root.join("db/migrate/20260929060000_grant_media_manage_to_built_in_groups").to_s

# Media library design spec §5.1: "Seeds: Admin and Editor get
# `media.manage`; Author keeps `media.upload`" -- for a fresh install
# (`AccessControl::Seeds`) and for groups seeded before the permission
# existed (the data migration).
class GrantMediaManageToBuiltInGroupsMigrationTest < ActiveSupport::TestCase
  def migrate(direction) = ActiveRecord::Migration.suppress_messages { GrantMediaManageToBuiltInGroups.new.migrate(direction) }

  def holders = AccessControl::Grant.where(permission: "media.manage").joins(:group).pluck("access_control_groups.name").sort

  test "the seeded Admin and Editor groups hold media.manage; Author doesn't" do
    AccessControl::Grant.delete_all
    AccessControl::Membership.delete_all
    AccessControl::Group.delete_all

    groups = AccessControl::Seeds.ensure_built_in_groups!

    assert_equal %w[Admin Editor], holders
    assert groups.fetch("Author").grants.exists?(permission: "media.upload")
  end

  test "the fixtures agree" do
    assert_equal %w[Admin Editor], holders
  end

  test "up grants it to the built-in Admin and Editor groups, idempotently, and leaves others alone" do
    AccessControl::Grant.where(permission: "media.manage").delete_all
    custom = AccessControl::Group.create!(name: "Editors (custom)")

    migrate(:up)
    migrate(:up)

    assert_equal %w[Admin Editor], holders
    assert_equal 2, AccessControl::Grant.where(permission: "media.manage").count
    assert AccessControl::Grant.where(permission: "media.manage").all? { |grant| grant.scope == {} }
    assert_empty custom.grants
  end

  test "down removes it again" do
    migrate(:down)

    assert_empty holders
  end
end
