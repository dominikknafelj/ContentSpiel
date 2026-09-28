require "test_helper"

class AccessControl::GrantTest < ActiveSupport::TestCase
  setup { @group = access_control_groups(:branch_editors) }

  test "an unknown permission key is invalid" do
    grant = @group.grants.new(permission: "nonsense.key", scope: {})

    assert_not grant.valid?
    assert_includes grant.errors[:permission], "isn't a registered permission"
  end

  test "a scope key the permission doesn't allow is invalid" do
    # posts.edit is scoped by content_type/own, never branch (page_ids).
    grant = @group.grants.new(permission: "posts.edit", scope: { "page_ids" => [ 1 ] })

    assert_not grant.valid?
    assert_includes grant.errors[:scope], "can't be scoped by page_ids for posts.edit"
  end

  test "content_types must be an array of strings" do
    grant = @group.grants.new(permission: "posts.edit", scope: { "content_types" => [ "blog", 1 ] })

    assert_not grant.valid?
    assert_includes grant.errors[:scope], "content_types must be an array of strings"
  end

  test "page_ids must be an array of integers" do
    grant = @group.grants.new(permission: "pages.edit", scope: { "page_ids" => [ "12" ] })

    assert_not grant.valid?
    assert_includes grant.errors[:scope], "page_ids must be an array of integers"
  end

  test "own must be a boolean" do
    grant = @group.grants.new(permission: "posts.edit", scope: { "own" => "yes" })

    assert_not grant.valid?
    assert_includes grant.errors[:scope], "own must be true or false"
  end

  test "a well-formed scoped grant is valid" do
    grant = @group.grants.new(permission: "posts.edit", scope: { "content_types" => [ "blog" ], "own" => true })

    assert grant.valid?, grant.errors.full_messages.to_sentence
  end

  test "an unscoped grant is valid" do
    grant = @group.grants.new(permission: "posts.read", scope: {})

    assert grant.valid?, grant.errors.full_messages.to_sentence
  end

  test "#permission_definition resolves the registered permission" do
    grant = @group.grants.new(permission: "posts.edit")

    assert_equal AccessControl::Permissions.fetch("posts.edit"), grant.permission_definition
  end

  test "#permission_definition is nil, not a raise, for a stale key" do
    grant = @group.grants.new(permission: "removed_plugin/thing.read")
    grant.save(validate: false)

    assert_nil grant.reload.permission_definition
  end

  test "#scope_content_types, #scope_page_ids and #scope_own? read the jsonb scope" do
    scoped = @group.grants.create!(permission: "posts.edit", scope: { "content_types" => [ "blog", "resume_entry" ], "own" => true })
    assert_equal %w[blog resume_entry], scoped.scope_content_types
    assert_equal [], scoped.scope_page_ids
    assert scoped.scope_own?

    unscoped = @group.grants.create!(permission: "posts.read", scope: {})
    assert_equal [], unscoped.scope_content_types
    assert_equal [], unscoped.scope_page_ids
    assert_not unscoped.scope_own?
  end

  test "#scope_page_ids casts stored ids to integers" do
    grant = @group.grants.create!(permission: "pages.edit", scope: { "page_ids" => [ 3, 7 ] })

    assert_equal [ 3, 7 ], grant.reload.scope_page_ids
  end
end
