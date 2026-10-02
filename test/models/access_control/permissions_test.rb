require "test_helper"

class AccessControl::PermissionsTest < ActiveSupport::TestCase
  teardown { Rails.application.reloader.prepare! }

  test "built-ins are registered with areas, subjects and scopes" do
    edit = AccessControl::Permissions.fetch("posts.edit")
    assert_equal "Posts", edit.area
    assert_equal Post, edit.subject
    assert_equal :edit, edit.action
    assert_equal %i[content_type own], edit.scopes
    assert_equal %i[branch], AccessControl::Permissions.fetch("pages.move").scopes
    assert_nil AccessControl::Permissions.fetch("users.manage").subject

    manage = AccessControl::Permissions.fetch("media.manage")
    assert_equal [ "Manage media", "Content", nil ], [ manage.label, manage.area, manage.subject ]
  end

  test "every spec key exists" do
    keys = %w[posts.read posts.create posts.edit posts.publish posts.delete
              pages.read pages.create pages.edit pages.publish pages.move pages.delete
              tags.manage media.upload media.manage settings.manage languages.manage users.manage
              groups.manage tokens.manage system_status.view audit.view trash.empty ai.translate]
    assert_equal keys.sort, AccessControl::Permissions.keys.sort
  end

  # Translation helpers spec §7: unscoped, no subject -- requesting a
  # suggestion also needs the record's own edit right, checked separately.
  test "ai.translate is a Content permission with no subject" do
    permission = AccessControl::Permissions.fetch("ai.translate")
    assert_equal [ "Use AI translation", "Content", nil, :translate, [] ],
      [ permission.label, permission.area, permission.subject, permission.action, permission.scopes ]
  end

  # Trash spec §3.1/global constraints: its own area (not folded into
  # Administration), Admin only.
  test "trash.empty is registered in its own Trash area" do
    permission = AccessControl::Permissions.find("trash.empty")
    assert_equal "Empty trash", permission.label
    assert_equal "Trash", permission.area
  end

  test "plugin permissions must be prefixed and unique" do
    AccessControl::Permissions.register("shop/orders.manage", label: "Manage orders", area: "Shop", action: :manage)
    assert_raises(AccessControl::DuplicatePermission) { AccessControl::Permissions.register("shop/orders.manage", label: "x", area: "Shop", action: :manage) }
    assert_raises(ArgumentError) { AccessControl::Permissions.register("Bad Key", label: "x", area: "x", action: :manage) }
  end

  test "unknown scope names are rejected at registration" do
    assert_raises(ArgumentError) { AccessControl::Permissions.register("shop/x.read", label: "x", area: "x", action: :read, scopes: [ :galaxy ]) }
  end
  # Final fix wave (Minor 3): audit.view isn't content-scoped -- its
  # events carry snapshots of every record -- and its label says so.
  test "the audit log permission says it covers all content" do
    assert_equal "View audit log (all content)", AccessControl::Permissions.fetch("audit.view").label
  end
end
