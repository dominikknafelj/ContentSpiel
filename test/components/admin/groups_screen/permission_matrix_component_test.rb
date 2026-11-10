require "test_helper"

# The matrix only composes the rows and the toggle list, in two card frames.
class Admin::GroupsScreen::PermissionMatrixComponentTest < ViewComponent::TestCase
  test "eleven rows under their areas, then the toggle list" do
    render_inline Admin::GroupsScreen::PermissionMatrixComponent.new(grants: [])

    assert_selector "[data-permission]", count: 11
    assert_equal %w[posts.read posts.create posts.edit posts.publish posts.delete pages.read pages.create pages.edit pages.publish pages.move pages.delete],
      page.all("[data-permission]").map { |row| row["data-permission"] }
    assert_equal %w[Posts Pages], page.all("[aria-labelledby=group-content-permissions] .admin-area-heading").map { |heading| heading.text.strip }
    assert_selector "h2", text: "Content permissions"
    assert_selector "h2", text: "Other permissions"
    assert_selector "[aria-labelledby=group-other-permissions] section h3", count: 4
  end

  test "ticked grants tick their rows and toggles, and a stale grant keeps its note" do
    group = AccessControl::Group.create!(name: "Stale #{SecureRandom.hex(3)}")
    group.grants.create!(permission: "posts.edit", scope: { "content_types" => %w[blog retired_type] })
    group.grants.create!(permission: "pages.edit", scope: { "page_ids" => [ 0 ] })
    group.grants.create!(permission: "tags.manage", scope: {})
    live = AccessControl::LiveGrants.new(group.grants.to_a)

    render_inline Admin::GroupsScreen::PermissionMatrixComponent.new(grants: live.carried_attributes, stale: live)

    assert_selector "input[name='group[grants][posts.edit][enabled]'][checked]"
    assert_selector "[data-removed-type=retired_type]"
    assert_selector "input[name='group[grants][pages.edit][enabled]']:not([checked])"
    assert_selector ".admin-stale-grant", text: /page that no longer exists/
    assert_selector "input[name='group[grants][tags.manage][enabled]'][checked]"
    # A removed type is a chip, not a note.
    assert_no_selector ".admin-stale-grant", text: /retired_type/
  end

  test "content permissions and other permissions are two card frames, each area a band" do
    render_inline Admin::GroupsScreen::PermissionMatrixComponent.new(grants: [])

    content = page.find("section.admin-settings-card[aria-labelledby=group-content-permissions]")
    assert_equal "Content permissions", content.find("h2#group-content-permissions").text
    assert_selector "section[aria-labelledby=group-content-permissions] .admin-settings-card__head p", text: "Each permission has its own scope. No scope means everything."
    assert_selector "section[aria-labelledby=group-content-permissions] .admin-settings-card__head span.bg-ic-structure-bg"
    assert_equal %w[Posts Pages], content.all("section[aria-labelledby^=content-band-] > h3.admin-area-heading.bg-paper.text-label.text-meta").map { |band| band.text.strip }
    assert_equal 5, content.all("section[aria-labelledby=content-band-posts] [data-permission]").size
    assert_equal 11, content.all("[data-permission]").size

    other = page.find("section.admin-settings-card[aria-labelledby=group-other-permissions]")
    assert_equal "Other permissions", other.find("h2#group-other-permissions").text
    assert_selector "section[aria-labelledby=group-other-permissions] .admin-settings-card__head span.bg-sunken.text-dim"
    assert_equal %w[Content Administration Oversight Forms], other.all(".admin-area-heading.bg-paper.text-label.text-meta").map { |band| band.text.strip }
    assert_no_selector "section.admin-settings-card section.rounded-card"
    assert_selector "section.admin-settings-card", count: 2

    # The script draws its chips with the row's class strings and the row's words.
    root = page.find(".admin-permission-matrix[data-controller='admin--groups--permission-matrix']")
    assert_equal 5, Admin::GroupsScreen::PermissionRowComponent.chip_classes.size
    Admin::GroupsScreen::PermissionRowComponent.chip_classes.each do |kind, classes|
      assert_equal classes, root["data-admin--groups--permission-matrix-#{kind.to_s.dasherize}-value"], kind
    end
    messages = JSON.parse(root["data-messages"])
    assert_equal "! %{name} · type removed", messages["components.groups_screen.permission_row.chips.removed_type"]
    assert_equal({ "one" => "includes %{count} subpage", "other" => "includes %{count} subpages" }, messages["components.groups_screen.scope_editor.notes.includes"])
  end

  test "a stale grant's note is the warn notice under its row" do
    group = AccessControl::Group.create!(name: "Stale #{SecureRandom.hex(3)}")
    group.grants.create!(permission: "pages.edit", scope: { "page_ids" => [ 0 ] })
    group.grants.new(permission: "gone.plugin", scope: {}).save!(validate: false)
    live = AccessControl::LiveGrants.new(group.grants.to_a)

    render_inline Admin::GroupsScreen::PermissionMatrixComponent.new(grants: live.carried_attributes, stale: live)

    compact = Admin::Ui::NoticeComponent.classes(:warn, size: :compact)
    note = page.find("[data-permission='pages.edit'] + div > .admin-stale-grant")
    assert_equal "#{compact} admin-stale-grant", note[:class]
    assert_match(/page that no longer exists/, note.text)
    assert_nil note[:role], "a standing warning is read where it stands"
    assert_selector "[data-permission='pages.edit'] + div.pl-\\[calc\\(1\\.25rem\\+0\\.75rem\\+1rem\\)\\]"

    unregistered = page.find(".admin-permission-matrix > .admin-stale-grant")
    assert_equal "#{Admin::Ui::NoticeComponent.classes(:warn)} admin-stale-grant", unregistered[:class]
    assert_equal "The permission “gone.plugin” no longer exists and will be removed when you save.", unregistered.text
    assert_no_selector "[class*='rounded-cs border border-warn']"
  end

  test "the rows named by open_keys start open" do
    render_inline Admin::GroupsScreen::PermissionMatrixComponent.new(grants: [ { permission: "posts.edit", scope: {} }, { permission: "posts.read", scope: {} } ], open_keys: [ "posts.edit" ])

    assert_selector "[data-permission='posts.edit'] [data-scope-editor][data-open='true']"
    assert_selector "[data-permission='posts.read'] [data-scope-editor][data-open='false']"
    assert_selector "[data-permission='posts.edit'] button[aria-expanded='true']", text: "Done"
  end

  test "a scoped plugin permission gets its own section of rows" do
    AccessControl::Permissions.register "acme/widgets.edit", label: "Edit widgets", area: "Widgets", action: :edit, scopes: [ :own ]
    render_inline Admin::GroupsScreen::PermissionMatrixComponent.new(grants: [])

    assert_selector "[data-permission='acme/widgets.edit']"
    assert_selector "[aria-labelledby=group-content-permissions] section > h3.admin-area-heading", text: "Widgets"
    assert_no_selector "[aria-labelledby=group-other-permissions] h3", text: "Widgets"
  ensure
    AccessControl::Permissions.reset!
    AccessControl::BuiltIns.register
  end

  # --- Locked ticks and view-only --------------------------------------------------

  def viewer_holding(grants)
    user = User.create!(email_address: "viewer-#{SecureRandom.hex(3)}@example.org", password: "a-long-enough-password")
    group = AccessControl::Group.create!(name: "Held #{SecureRandom.hex(3)}")
    grants.each { |permission, scope| group.grants.create!(permission: permission, scope: scope) }
    AccessControl::Membership.create!(user: user, group: group)
    user
  end

  def matrix_for(viewer, grants, **options)
    as(viewer) { render_inline Admin::GroupsScreen::PermissionMatrixComponent.new(grants: grants, **options) }
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
    assert_selector "p.admin-locked-hint.text-small.text-meta"
  end

  test "a grant that isn't what the group stores (a typed tick, a changed row) is never locked" do
    viewer = viewer_holding("posts.read" => {})

    matrix_for(viewer, [ { permission: "posts.delete", scope: {} }, { permission: "posts.read", scope: { "own" => true } } ], stored: [ { permission: "posts.read", scope: {} } ])

    assert_no_selector "[data-locked]"
    assert_no_selector ".admin-locked-hint"
  end

  # The case a lock on POSTED values would get wrong. The
  # group stores `posts.edit {blog}` (the viewer's own right, so no lock); the
  # editor widened the row to `{blog, now_update}` and the save was refused.
  # The row now holds a scope the viewer couldn't hand out -- but it is what
  # they typed, not what is stored, so it comes back editable.
  test "a stored row the editor widened beyond their own right is not locked" do
    viewer = viewer_holding("posts.edit" => { "content_types" => [ "blog" ] })
    stored = [ { permission: "posts.edit", scope: { "content_types" => %w[blog] } } ]
    posted = [ { permission: "posts.edit", scope: { "content_types" => %w[blog now_update] } } ]

    matrix_for(viewer, posted, stored: stored)

    assert_no_selector "[data-locked]"
    assert_no_selector ".admin-locked-hint"
    assert_selector "[data-permission='posts.edit'] input[type=checkbox][name$='[enabled]'][checked]:not([disabled])", visible: :all
    assert_selector "[data-permission='posts.edit'] button", text: "Edit scope", visible: :all

    # The same scope, when it IS what the group stores, locks.
    matrix_for(viewer, posted, stored: posted)
    assert_selector "[data-permission='posts.edit'][data-locked]"
  end

  # The lock is judged on the scope as stored, a removed content type's name
  # included -- the question `can_manage_group?` asks of the whole group, which
  # is why the controller draws such a group view-only before any row is locked.
  test "a stored row carrying a removed type locks for a viewer who couldn't grant the name, not for one who could" do
    stored = [ { permission: "posts.edit", scope: { "content_types" => %w[blog retired_type] } } ]

    matrix_for(viewer_holding("posts.edit" => { "content_types" => [ "blog" ] }), stored, stored: stored)
    assert_selector "[data-permission='posts.edit'][data-locked]"
    assert_no_selector "[data-removed-type] button", text: "Remove", visible: :all

    [ {}, { "content_types" => %w[blog retired_type] } ].each do |held|
      matrix_for(viewer_holding("posts.edit" => held), stored, stored: stored)
      assert_no_selector "[data-locked]"
      assert_selector "[data-removed-type='retired_type'] button", text: "Remove", visible: :all
    end
  end

  test "an owner, no actor, and a view-only render lock nothing" do
    grants = [ { permission: "posts.delete", scope: {} }, { permission: "trash.empty", scope: {} } ]

    matrix_for(users(:one), grants)
    assert_no_selector "[data-locked]"
    assert_no_selector ".admin-locked-hint"

    render_inline Admin::GroupsScreen::PermissionMatrixComponent.new(grants: grants)
    assert_no_selector "[data-locked]"

    matrix_for(viewer_holding({}), grants, view_only: true)
    assert_no_selector "[data-locked]"
    assert_selector "a[role=button]", text: "View scope", visible: :all
    assert_no_selector "button", text: "Edit scope", visible: :all
  end
end
