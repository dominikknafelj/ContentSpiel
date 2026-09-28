require "test_helper"
require Rails.root.join("db/migrate/20260928060000_seed_access_control_groups").to_s

# `AccessControl::Seeds.ensure_built_in_groups!`/`.backfill!` (design spec
# §6), driven directly rather than through `SeedAccessControlGroups.new
# .migrate(:up)` for the groups/backfill assertions -- the test database's
# `access_control_groups`/`memberships`/`grants` tables are already at
# their final (post-migration) shape via fixtures, so there's nothing to
# recreate the way test/migrations/drop_action_text_test.rb recreates a
# dropped table. The `api_tokens.group_id` NOT NULL tightening the
# migration's own `up` performs afterwards is exercised separately below,
# by loosening it back to nullable first (Postgres DDL is transactional,
# so the loosening rolls back with the rest of the test).
class AccessControlSeedMigrationTest < ActiveSupport::TestCase
  def connection = ActiveRecord::Base.connection

  # Starts from an empty table, clearing out the fixtures (which already
  # include the four built-in groups, so this file's other tests can use
  # them without calling `ensure_built_in_groups!` themselves) -- the Task
  # 2 brief's own scenario: "run it twice and get four groups, not eight."
  test "ensure_built_in_groups! is idempotent -- running it twice yields four groups, not eight" do
    AccessControl::Grant.delete_all
    AccessControl::Membership.delete_all
    AccessControl::Group.delete_all

    AccessControl::Seeds.ensure_built_in_groups!
    assert_equal 4, AccessControl::Group.count

    AccessControl::Seeds.ensure_built_in_groups!
    assert_equal 4, AccessControl::Group.count
  end

  test "ensure_built_in_groups! returns the four groups by name" do
    result = AccessControl::Seeds.ensure_built_in_groups!

    assert_equal [ "Admin", "Editor", "Author", "Read only" ].sort, result.keys.sort
    assert result.values.all? { |group| group.is_a?(AccessControl::Group) }
  end

  test "ensure_built_in_groups! grants Admin every registered permission, unscoped" do
    admin = AccessControl::Seeds.ensure_built_in_groups!.fetch("Admin")

    assert_equal AccessControl::Permissions.keys.sort, admin.grants.pluck(:permission).sort
    assert admin.grants.all? { |grant| grant.scope == {} }
  end

  test "backfill! makes every user an owner, assigns ungrouped tokens to Admin, and authors ungrouped posts to the lowest-id owner" do
    AccessControl::Seeds.ensure_built_in_groups!
    connection.change_column_null :api_tokens, :group_id, true

    non_owner = users(:reader)
    assert_not non_owner.owner?

    older_post = create_post(title: "Older post")
    newer_post = create_post(title: "Newer post")
    ungrouped_token, = ApiToken.generate!(non_owner, group: access_control_groups(:read_only))
    ungrouped_token.update_column(:group_id, nil)

    AccessControl::Seeds.backfill!

    assert User.all.all?(&:owner?)

    lowest_owner = User.order(:id).first
    assert_equal lowest_owner, older_post.reload.author
    assert_equal lowest_owner, newer_post.reload.author

    assert_equal "Admin", ungrouped_token.reload.group.name
  end

  test "backfill! doesn't reassign a post that already has an author" do
    AccessControl::Seeds.ensure_built_in_groups!
    authored_post = create_post(title: "Already authored")
    authored_post.update_column(:author_id, users(:two).id)

    AccessControl::Seeds.backfill!

    assert_equal users(:two), authored_post.reload.author
  end

  test "up tightens api_tokens.group_id to NOT NULL once every row has a group" do
    AccessControl::Seeds.ensure_built_in_groups!
    connection.change_column_null :api_tokens, :group_id, true

    ActiveRecord::Migration.suppress_messages { SeedAccessControlGroups.new.migrate(:up) }

    column = connection.columns(:api_tokens).find { |c| c.name == "group_id" }
    assert_not column.null, "expected api_tokens.group_id to be NOT NULL after the migration's up"
  end
end
