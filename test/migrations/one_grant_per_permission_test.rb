require "test_helper"
require Rails.root.join("db/migrate/20261005130000_one_grant_per_permission").to_s

# A group holds one grant per permission: existing duplicates are merged by
# what the pair granted (see the migration's header), and the unique index
# then refuses a second. The index exists on the test database, so each test
# rolls the migration back inside its own transaction (Postgres DDL is
# transactional), inserts the "before" rows raw and runs `up` again.
class OneGrantPerPermissionMigrationTest < ActiveSupport::TestCase
  setup do
    ActiveRecord::Migration.suppress_messages { OneGrantPerPermission.new.migrate(:down) }
    AccessControl::Grant.reset_column_information
  end

  def insert(group, permission, scope)
    AccessControl::Grant.insert_all!([ { group_id: group.id, permission: permission, scope: scope, created_at: Time.current, updated_at: Time.current } ])
  end

  def migrate_up
    ActiveRecord::Migration.verbose = true
    out, = capture_io { OneGrantPerPermission.new.migrate(:up) }
    out
  ensure
    ActiveRecord::Migration.verbose = false
  end

  def scopes(group, permission) = group.grants.reload.where(permission: permission).pluck(:scope)

  test "two content-type scopes become the union of the lists, without a notice" do
    group = AccessControl::Group.create!(name: "Union")
    insert(group, "posts.edit", { "content_types" => %w[now_update] })
    insert(group, "posts.edit", { "content_types" => %w[blog] })

    out = migrate_up

    assert_equal [ { "content_types" => %w[blog now_update] } ], scopes(group, "posts.edit")
    assert_not_includes out, "Union"
  end

  test "an unscoped grant absorbs a scoped one" do
    group = AccessControl::Group.create!(name: "Absorb")
    insert(group, "posts.edit", {})
    insert(group, "posts.edit", { "content_types" => %w[blog] })

    migrate_up

    assert_equal [ {} ], scopes(group, "posts.edit")
  end

  test "scopes on different keys widen to unscoped and the group and permission are printed" do
    group = AccessControl::Group.create!(name: "Different keys")
    insert(group, "posts.edit", { "content_types" => %w[blog] })
    insert(group, "posts.edit", { "own" => true })

    out = migrate_up

    assert_equal [ {} ], scopes(group, "posts.edit")
    assert_includes out, "Different keys"
    assert_includes out, "posts.edit"
  end

  test "a scope that covers the other is kept exactly, and two own grants stay own" do
    group = AccessControl::Group.create!(name: "Covers")
    insert(group, "posts.edit", { "content_types" => %w[blog] })
    insert(group, "posts.edit", { "content_types" => %w[blog], "own" => true })
    insert(group, "posts.publish", { "own" => true })
    insert(group, "posts.publish", { "own" => true })

    out = migrate_up

    assert_equal [ { "content_types" => %w[blog] } ], scopes(group, "posts.edit")
    assert_equal [ { "own" => true } ], scopes(group, "posts.publish")
    assert_not_includes out, "Covers"
  end

  test "a dead content type survives the merge, and three grants merge pairwise" do
    group = AccessControl::Group.create!(name: "Three")
    insert(group, "posts.edit", { "content_types" => %w[retired] })
    insert(group, "posts.edit", { "content_types" => %w[blog] })
    insert(group, "posts.edit", { "content_types" => %w[blog now_update] })

    migrate_up

    assert_equal [ { "content_types" => %w[blog now_update retired] } ], scopes(group, "posts.edit")
  end

  test "lists that differ on two keys are merged as the union of each and reported" do
    group = AccessControl::Group.create!(name: "Crossed")
    page = Struct.new(:id).new(41)
    insert(group, "pages.edit", { "page_ids" => [ page.id ], "content_types" => %w[blog] })
    insert(group, "pages.edit", { "page_ids" => [ page.id + 1 ], "content_types" => %w[now_update] })

    out = migrate_up

    assert_equal [ { "content_types" => %w[blog now_update], "page_ids" => [ page.id, page.id + 1 ] } ], scopes(group, "pages.edit")
    assert_includes out, "Crossed"
  end

  test "other groups and permissions are left alone, and the index then refuses a second grant" do
    group = AccessControl::Group.create!(name: "Index")
    other = AccessControl::Group.create!(name: "Index other")
    insert(group, "posts.edit", { "content_types" => %w[blog] })
    insert(group, "posts.read", {})
    insert(other, "posts.edit", { "content_types" => %w[now_update] })
    insert(group, "posts.edit", { "own" => true })

    migrate_up

    assert_equal [ [ "posts.edit", {} ], [ "posts.read", {} ] ], group.grants.reload.order(:permission).pluck(:permission, :scope)
    assert_equal [ { "content_types" => %w[now_update] } ], scopes(other, "posts.edit")
    assert_raises(ActiveRecord::RecordNotUnique) { insert(group, "posts.edit", {}) }
  end
end
