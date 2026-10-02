require "test_helper"
require Rails.root.join("db/migrate/20261002120100_grant_ai_translate_to_built_in_groups").to_s

# Translation helpers spec §7: "`ai.translate` ... seeded onto Admin and
# Editor" -- for a fresh install (`AccessControl::Seeds`) and for groups
# seeded before the permission existed (the data migration). The same shape
# as `GrantMediaManageToBuiltInGroupsMigrationTest`.
class GrantAiTranslateToBuiltInGroupsMigrationTest < ActiveSupport::TestCase
  def migrate(direction) = ActiveRecord::Migration.suppress_messages { GrantAiTranslateToBuiltInGroups.new.migrate(direction) }

  def holders = AccessControl::Grant.where(permission: "ai.translate").joins(:group).pluck("access_control_groups.name").sort

  test "the seeded Admin and Editor groups hold ai.translate; Author and Read only don't" do
    AccessControl::Grant.delete_all
    AccessControl::Membership.delete_all
    AccessControl::Group.delete_all

    AccessControl::Seeds.ensure_built_in_groups!

    assert_equal %w[Admin Editor], holders
  end

  test "the fixtures agree" do
    assert_equal %w[Admin Editor], holders
  end

  test "up grants it to the built-in Admin and Editor groups, idempotently, and leaves others alone" do
    AccessControl::Grant.where(permission: "ai.translate").delete_all
    custom = AccessControl::Group.create!(name: "Translators (custom)")

    migrate(:up)
    migrate(:up)

    assert_equal %w[Admin Editor], holders
    assert_equal 2, AccessControl::Grant.where(permission: "ai.translate").count
    assert AccessControl::Grant.where(permission: "ai.translate").all? { |grant| grant.scope == {} }
    assert_empty custom.grants
  end

  test "down removes it again" do
    migrate(:down)

    assert_empty holders
  end
end
