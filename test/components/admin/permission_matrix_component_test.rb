require "test_helper"

# The matrix only composes the rows and the toggle cards (round 3 Task 10).
class Admin::PermissionMatrixComponentTest < ViewComponent::TestCase
  test "eleven rows under their areas, then the toggle cards" do
    render_inline Admin::PermissionMatrixComponent.new(grants: [])

    assert_selector "[data-permission]", count: 11
    assert_equal %w[posts.read posts.create posts.edit posts.publish posts.delete pages.read pages.create pages.edit pages.publish pages.move pages.delete],
      page.all("[data-permission]").map { |row| row["data-permission"] }
    assert_equal %w[Posts Pages], page.all(".admin-area-heading").map { |heading| heading.text.strip }
    assert_selector "h2", text: "Content permissions"
    assert_selector "h2", text: "Other permissions"
    assert_selector "section h3", count: 3
  end

  test "ticked grants tick their rows and toggles, and a stale grant keeps its note" do
    group = AccessControl::Group.create!(name: "Stale #{SecureRandom.hex(3)}")
    group.grants.create!(permission: "posts.edit", scope: { "content_types" => %w[blog retired_type] })
    group.grants.create!(permission: "pages.edit", scope: { "page_ids" => [ 0 ] })
    group.grants.create!(permission: "tags.manage", scope: {})
    live = AccessControl::LiveGrants.new(group.grants.to_a)

    render_inline Admin::PermissionMatrixComponent.new(grants: live.carried_attributes, stale: live)

    assert_selector "input[name='group[grants][posts.edit][enabled]'][checked]"
    assert_selector "[data-removed-type=retired_type]"
    assert_selector "input[name='group[grants][pages.edit][enabled]']:not([checked])"
    assert_selector ".admin-stale-grant", text: /page that no longer exists/
    assert_selector "input[name='group[grants][tags.manage][enabled]'][checked]"
    # A removed type is a chip, not a note.
    assert_no_selector ".admin-stale-grant", text: /retired_type/
  end

  test "the rows named by open_keys start open" do
    render_inline Admin::PermissionMatrixComponent.new(grants: [ { permission: "posts.edit", scope: {} }, { permission: "posts.read", scope: {} } ], open_keys: [ "posts.edit" ])

    assert_selector "[data-permission='posts.edit'] [data-scope-editor][data-open='true']"
    assert_selector "[data-permission='posts.read'] [data-scope-editor][data-open='false']"
    assert_selector "[data-permission='posts.edit'] button[aria-expanded='true']", text: "Done"
  end

  test "a scoped plugin permission gets its own section of rows" do
    AccessControl::Permissions.register "acme/widgets.edit", label: "Edit widgets", area: "Widgets", action: :edit, scopes: [ :own ]
    render_inline Admin::PermissionMatrixComponent.new(grants: [])

    assert_selector "[data-permission='acme/widgets.edit']"
    assert_selector ".admin-area-heading", text: "Widgets"
    assert_no_selector "section h3", text: "Widgets"
  ensure
    AccessControl::Permissions.reset!
    AccessControl::BuiltIns.register
  end

  # --- Locked ticks and view-only (round 3 Task 11) ---------------------------------

  def viewer_holding(grants)
    user = User.create!(email_address: "viewer-#{SecureRandom.hex(3)}@example.org", password: "a-long-enough-password")
    group = AccessControl::Group.create!(name: "Held #{SecureRandom.hex(3)}")
    grants.each { |permission, scope| group.grants.create!(permission: permission, scope: scope) }
    AccessControl::Membership.create!(user: user, group: group)
    user
  end

  def matrix_for(viewer, grants, **options)
    as(viewer) { render_inline Admin::PermissionMatrixComponent.new(grants: grants, **options) }
  end

  test "for a non-owner, exactly the ticked rows and toggles they couldn't hand out are locked; the note under the matrix appears" do
    viewer = viewer_holding("posts.read" => {}, "posts.edit" => { "content_types" => [ "blog" ] }, "tags.manage" => {})

    grants = [
      { permission: "posts.read", scope: {} },
      { permission: "posts.edit", scope: { "content_types" => %w[blog now_update] } },
      { permission: "posts.delete", scope: {} },
      { permission: "tags.manage", scope: {} },
      { permission: "trash.empty", scope: {} }
    ]
    matrix_for(viewer, grants, stored: grants)

    assert_selector "[data-locked]", count: 2 # posts.edit (wider than held) and posts.delete (not held)
    assert_selector "[data-permission='posts.edit'][data-locked]"
    assert_selector "[data-permission='posts.delete'][data-locked]"
    assert_selector "[data-permission='posts.read']:not([data-locked]) button", text: "Edit scope", visible: :all
    assert_selector "input[type=checkbox][name='group[grants][trash.empty][enabled]'][disabled]"
    assert_selector "input[type=checkbox][name='group[grants][tags.manage][enabled]']:not([disabled])"
    assert_selector ".admin-locked-hint"
  end

  test "a grant that isn't what the group stores (a typed tick, a changed row) is never locked" do
    viewer = viewer_holding("posts.read" => {})

    matrix_for(viewer, [ { permission: "posts.delete", scope: {} }, { permission: "posts.read", scope: { "own" => true } } ], stored: [ { permission: "posts.read", scope: {} } ])

    assert_no_selector "[data-locked]"
    assert_no_selector ".admin-locked-hint"
  end

  test "an owner, no actor, and a view-only render lock nothing" do
    grants = [ { permission: "posts.delete", scope: {} }, { permission: "trash.empty", scope: {} } ]

    matrix_for(users(:one), grants)
    assert_no_selector "[data-locked]"
    assert_no_selector ".admin-locked-hint"

    render_inline Admin::PermissionMatrixComponent.new(grants: grants)
    assert_no_selector "[data-locked]"

    matrix_for(viewer_holding({}), grants, view_only: true)
    assert_no_selector "[data-locked]"
    assert_selector "a[role=button]", text: "View scope", visible: :all
    assert_no_selector "button", text: "Edit scope", visible: :all
  end
end
