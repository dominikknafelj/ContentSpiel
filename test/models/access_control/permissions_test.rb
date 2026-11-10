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
              groups.manage tokens.manage system_status.view audit.view trash.empty ai.translate
              forms.manage form_submissions.view forms.submit]
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

  # The two rights an editor is given, in their own
  # area, unscoped like the Administration ones.
  test "the forms rights are registered in a Forms area, unscoped" do
    [ [ "forms.manage", "Manage forms" ], [ "form_submissions.view", "View form submissions" ], [ "forms.submit", "Send a form" ] ].each do |key, label|
      permission = AccessControl::Permissions.fetch(key)
      assert_equal [ label, "Forms", nil, [] ], [ permission.label, permission.area, permission.subject, permission.scopes ], key
    end
  end

  # `forms.submit` is the visitor's alone. No group,
  # token, matrix or seed may hold it.
  test "forms.submit is registered but not grantable: the matrix, the built-in groups and Groups::Save never hold it" do
    assert AccessControl::Permissions.find("forms.submit")
    assert_not AccessControl::Permissions.fetch("forms.submit").grantable
    assert AccessControl::Permissions.fetch("forms.manage").grantable
    assert_equal AccessControl::Permissions.keys - %w[forms.submit], AccessControl::Permissions.grantable.map(&:key)

    toggles = Admin::GroupsScreen::ToggleListComponent.new(grants: {}).send(:bands).flat_map(&:last).map(&:key)
    assert_includes toggles, "forms.manage"
    assert_not_includes toggles, "forms.submit"

    AccessControl::Seeds::BUILT_IN.each_key do |name|
      assert_not_includes AccessControl::Seeds.grants_of(name).map { |grant| grant[:permission] }, "forms.submit", name
    end
    assert_not AccessControl::Grant.exists?(permission: "forms.submit"), "the fixtures hold none either"

    grant = AccessControl::Grant.new(group: access_control_groups(:admin), permission: "forms.submit", scope: {})
    assert_not grant.valid?
    assert_includes grant.errors[:permission], "can't be granted"
    assert_not AccessControl.can_grant?(users(:one), "forms.submit"), "not even an owner hands it out"

    result = as(users(:one)) do
      Groups::Save.call(attributes: { name: "Senders", grants: [ { permission: "forms.submit", scope: {} } ] })
    end
    assert_not result.ok?
    assert_not AccessControl::Group.exists?(name: "Senders")
  end

  test "the Admin group gets forms.manage and form_submissions.view, on a fresh database and through the data migration" do
    admin = access_control_groups(:admin)
    assert admin.grants.exists?(permission: "forms.manage")
    assert admin.grants.exists?(permission: "form_submissions.view")
    assert_not access_control_groups(:editor).grants.exists?(permission: "forms.manage")

    AccessControl::Grant.delete_all
    AccessControl::Membership.delete_all
    AccessControl::Group.delete_all
    Groups::EnsureBuiltIns.call
    fresh = AccessControl::Group.find_by!(name: "Admin")
    assert_equal AccessControl::Permissions.grantable.map(&:key).sort, fresh.grants.pluck(:permission).sort
    assert_equal %w[Admin], AccessControl::Grant.where(permission: %w[forms.manage form_submissions.view]).joins(:group).distinct.pluck("access_control_groups.name")

    fresh.grants.where(permission: %w[forms.manage form_submissions.view]).delete_all
    require Rails.root.join("db/migrate/20261104090300_grant_forms_permissions_to_admin_group").to_s
    ActiveRecord::Migration.suppress_messages { GrantFormsPermissionsToAdminGroup.new.migrate(:up) }
    assert_equal %w[form_submissions.view forms.manage], fresh.grants.where(permission: %w[forms.manage form_submissions.view]).pluck(:permission).sort
    assert(fresh.grants.all? { |grant| grant.scope == {} })
    ActiveRecord::Migration.suppress_messages { GrantFormsPermissionsToAdminGroup.new.migrate(:up) }
    assert_equal 2, fresh.grants.where(permission: %w[forms.manage form_submissions.view]).count, "up is idempotent"
    assert_empty AccessControl::Group.where.not(name: "Admin").joins(:grants).where(access_control_grants: { permission: %w[forms.manage form_submissions.view] })
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
