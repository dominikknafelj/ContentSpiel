require "test_helper"

# The Groups module (access-control design spec §5): list, editor, delete.
# The rules themselves are `Groups::Save`/`Groups::Destroy`'s (test/
# services/groups); this covers the screens and the params they send.
class Admin::GroupsTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
  end

  test "the module needs groups.manage" do
    sign_in_as(users(:author))

    %w[/cs-studio/groups /cs-studio/groups/new].each do |path|
      get path
      assert_response :forbidden
    end
  end

  test "the list shows every group with its member count, and the sidebar links to it" do
    sign_in_as(users(:two))
    get "/cs-studio/groups"

    assert_response :success
    assert_select "nav[aria-label='Modules'] a[href='/cs-studio/groups']", text: "Groups"
    assert_select "#" + dom_id(access_control_groups(:admin)) do
      assert_select "a", text: "Admin"
      assert_select "[data-column=members]", text: /\A1\s+member\z/
      assert_select "*", text: /Built-in/
    end
  end

  test "each row is one link to the editor: no Edit button, nothing interactive nested in it" do
    sign_in_as(users(:one))
    get "/cs-studio/groups"

    group = access_control_groups(:editor)
    assert_select "#" + dom_id(group) do
      assert_select "a[href='/cs-studio/groups/#{group.id}/edit']", count: 1, text: group.name
      assert_select "a", count: 1
      assert_select "button", count: 0
    end
    assert_select "a", text: "Edit", count: 0
    assert_select "a[href='/cs-studio/groups/new']", text: "New group"
    assert_select "p", text: "Built-in groups can be changed but not deleted. Deleting a custom group removes its permissions from its members and revokes its AI tokens."
  end

  test "the tokens column counts the active tokens bound to the group" do
    group = AccessControl::Group.create!(name: "Bots")
    ApiToken.generate!(users(:reader), group: group)
    ApiToken.generate!(users(:reader), group: group)
    ApiToken.generate!(users(:reader), group: group)[0].revoke!
    sign_in_as(users(:one))

    get "/cs-studio/groups"

    assert_select "#" + dom_id(group) + " [data-column=tokens]", text: /\A2\s+tokens\z/
    assert_select "#" + dom_id(access_control_groups(:admin)) + " [data-column=tokens]", text: /\A0\s+tokens\z/
  end

  test "the list's queries don't grow with the number of groups" do
    sign_in_as(users(:one))
    get "/cs-studio/groups" # warm up
    few = count_queries { get "/cs-studio/groups" }

    8.times do |i|
      group = AccessControl::Group.create!(name: "More #{i}")
      ApiToken.generate!(users(:reader), group: group)
      AccessControl::Membership.create!(user: users(:reader), group: group)
    end
    many = count_queries { get "/cs-studio/groups" }

    assert_equal few, many
    assert_select "ul li", minimum: 10
  end

  test "create a group with posts.edit scoped to blog and own, then edit it" do
    sign_in_as(users(:one))

    assert_difference -> { AccessControl::Group.count }, 1 do
      post "/cs-studio/groups", params: { group: {
        name: "Bloggers", description: "Their own blog posts",
        member_ids: [ "", users(:author).id ],
        grants: {
          "posts.edit" => { enabled: "1", content_types: [ "", "blog" ], own: "1" },
          "posts.read" => { enabled: "1", content_types: [ "" ], own: "0" },
          "posts.delete" => { enabled: "0", content_types: [ "blog" ] }
        }
      } }
    end

    group = AccessControl::Group.find_by!(name: "Bloggers")
    assert_redirected_to "/cs-studio/groups/#{group.id}/edit"
    assert_equal [ [ "posts.edit", { "content_types" => [ "blog" ], "own" => true } ], [ "posts.read", {} ] ],
      group.grants.order(:permission).map { |g| [ g.permission, g.scope ] }
    assert_equal [ users(:author) ], group.users.to_a

    get "/cs-studio/groups/#{group.id}/edit"
    assert_response :success
    assert_select "input[type=checkbox][name='group[grants][posts.edit][enabled]'][checked]"
    assert_select "input[type=checkbox][name='group[grants][posts.edit][own]'][checked]"
    assert_select "input[type=checkbox][name='group[grants][posts.edit][content_types][]'][value=blog][checked]"
    assert_select "input[type=checkbox][name='group[grants][posts.delete][enabled]']:not([checked])"
    assert_select "input[type=checkbox][name='group[member_ids][]'][value='#{users(:author).id}'][checked]"

    patch "/cs-studio/groups/#{group.id}", params: { group: {
      name: "Bloggers", description: "",
      member_ids: [ "" ],
      grants: { "posts.edit" => { enabled: "1", content_types: [ "", "blog", "now_update" ], own: "0" } }
    } }

    assert_redirected_to "/cs-studio/groups/#{group.id}/edit"
    assert_equal [ [ "posts.edit", { "content_types" => %w[blog now_update] } ] ], group.grants.reload.map { |g| [ g.permission, g.scope ] }
    assert_empty group.users.reload
  end

  test "a validation failure re-renders the editor" do
    sign_in_as(users(:one))

    post "/cs-studio/groups", params: { group: { name: access_control_groups(:admin).name.downcase } }

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /has already been taken/
  end

  test "a non-owner forging a permission they lack gets the 403 page" do
    managers = AccessControl::Group.create!(name: "Group managers")
    AccessControl::Grant.create!(group: managers, permission: "groups.manage", scope: {})
    AccessControl::Membership.create!(user: users(:editor_branch), group: managers)
    sign_in_as(users(:editor_branch))

    patch "/cs-studio/groups/#{managers.id}", params: { group: {
      name: managers.name,
      grants: { "groups.manage" => { enabled: "1" }, "users.manage" => { enabled: "1" } }
    } }

    assert_response :forbidden
    assert_includes response.body, "You don&#39;t have permission to manage users"
    assert_equal [ "groups.manage" ], managers.grants.reload.pluck(:permission)
  end

  test "a built-in group has no Delete button, and a forged delete is refused" do
    sign_in_as(users(:one))
    group = access_control_groups(:read_only)

    get "/cs-studio/groups/#{group.id}/edit"
    assert_select "button", text: "Delete group", count: 0

    delete "/cs-studio/groups/#{group.id}"
    assert_redirected_to "/cs-studio/groups/#{group.id}/edit"
    follow_redirect!
    assert_select "[role=alert]", text: "Built-in groups can't be deleted"
    assert AccessControl::Group.exists?(group.id)
  end

  test "deleting a custom group revokes its tokens, and the confirmation names them" do
    sign_in_as(users(:one))
    group = AccessControl::Group.create!(name: "Bots")
    token, raw = ApiToken.generate!(users(:reader), group: group)

    get "/cs-studio/groups/#{group.id}/edit"
    assert_select "dialog#delete-group-#{group.id}" do
      assert_select "*", text: /revokes 1 token/
      assert_select "li", text: /#{Regexp.escape(token.name)} — .*#{Regexp.escape(users(:reader).email_address)}/
    end

    delete "/cs-studio/groups/#{group.id}"

    assert_redirected_to "/cs-studio/groups"
    assert_not AccessControl::Group.exists?(group.id)
    assert_nil ApiToken.authenticate(raw)
    assert Audit::Event.exists?(action: "token.revoked", subject_type: "ApiToken", subject_id: token.id)
  end

  # Review Focus 3: a grant scoped to a deleted branch root or an
  # unregistered content type still opens, with the stale values shown as
  # removed.
  test "a group with stale grants still loads, showing the stale values as removed" do
    page = as_owner { create_page(title: "Old branch") }
    group = AccessControl::Group.create!(name: "Stale")
    AccessControl::Grant.create!(group: group, permission: "posts.edit", scope: { "content_types" => %w[blog retired_type] })
    AccessControl::Grant.create!(group: group, permission: "pages.edit", scope: { "page_ids" => [ page.id ] })
    as_owner { delete_for_good(page) }
    sign_in_as(users(:one))

    get "/cs-studio/groups/#{group.id}/edit"

    assert_response :success
    assert_select "input[type=checkbox][name='group[grants][posts.edit][content_types][]'][value=blog][checked]"
    # The retired type is no longer a note: it is carried (hidden input) with a
    # warn chip and Remove, so an untouched save keeps it.
    assert_select "input[type=hidden][name='group[grants][posts.edit][content_types][]'][value=retired_type]"
    assert_select "[data-removed-type=retired_type]", text: /! retired_type · this type no longer exists/
    assert_select "[data-removed-type=retired_type] button", text: "Remove"
    # Its only branch is gone: the grant matched nothing, so it shows unticked.
    assert_select "input[type=checkbox][name='group[grants][pages.edit][enabled]']:not([checked])"
    assert_select ".admin-stale-grant", text: /page that no longer exists/
  end

  test "the branch picker lists only pages the actor can read" do
    hidden = as_owner { create_page(title: "Secret area") }
    visible = as_owner { create_page(title: "Public area") }
    managers = AccessControl::Group.create!(name: "Group managers")
    AccessControl::Grant.create!(group: managers, permission: "groups.manage", scope: {})
    AccessControl::Grant.create!(group: managers, permission: "pages.read", scope: { "page_ids" => [ visible.id ] })
    AccessControl::Membership.create!(user: users(:editor_branch), group: managers)
    sign_in_as(users(:editor_branch))

    get "/cs-studio/groups/new"

    assert_response :success
    assert_select "input[name='group[grants][pages.edit][page_ids][]'][value='#{visible.id}']"
    assert_select "input[name='group[grants][pages.edit][page_ids][]'][value='#{hidden.id}']", count: 0
    assert_not_includes response.body, "Secret area"
  end

  # A stored branch root the actor can't read isn't in their picker, but
  # it isn't dropped either: saving the group without touching the grant
  # keeps it (otherwise the grant would lose its only root and turn into
  # an unscoped one).
  test "a branch root the actor can't read is kept when they save the group" do
    hidden = as_owner { create_page(title: "Secret area") }
    group = AccessControl::Group.create!(name: "Secret editors")
    AccessControl::Grant.create!(group: group, permission: "pages.edit", scope: { "page_ids" => [ hidden.id ] })
    managers = AccessControl::Group.create!(name: "Group managers")
    AccessControl::Grant.create!(group: managers, permission: "groups.manage", scope: {})
    AccessControl::Membership.create!(user: users(:editor_branch), group: managers)
    sign_in_as(users(:editor_branch))

    get "/cs-studio/groups/#{group.id}/edit"
    assert_select "input[type=hidden][name='group[grants][pages.edit][page_ids][]'][value='#{hidden.id}']"
    assert_select "*", text: "A page you can't open (kept)"
    assert_select ".admin-unreadable-branches", text: /Only someone who can open them can change this permission/
    assert_not_includes response.body, "Secret area"

    patch "/cs-studio/groups/#{group.id}", params: { group: {
      name: "Secret editors", description: "Renamed",
      grants: { "pages.edit" => { enabled: "1", page_ids: [ "", hidden.id.to_s ] } }
    } }

    assert_redirected_to "/cs-studio/groups/#{group.id}/edit"
    assert_equal({ "page_ids" => [ hidden.id ] }, group.grants.reload.sole.scope)
  end

  # --- Review Focus 3: a form submitted exactly as rendered changes nothing --------

  # The tri-state tree is where this could break: an ancestor shown "-"
  # (indeterminate, unchecked) and a descendant shown as a greyed tick
  # (disabled) must never be submitted, a stored root the viewer can't open must
  # be carried, and a removed content type must be carried too.
  test "a group holding an unreadable page, a removed type, scoped grants and an own scope, saved untouched, changes nothing" do
    fixture = review_focus_group
    sign_in_as(users(:editor_branch))
    get "/cs-studio/groups/#{fixture[:group].id}/edit"
    assert_response :success

    # What the page says about the tree: section "-" (partial), a1 and b included.
    assert_select "[data-permission='pages.edit'] input[value='#{fixture[:section].id}'][data-partial]:not([checked])"
    assert_select "[data-permission='pages.edit'] input[value='#{fixture[:a1].id}'][checked][disabled]"
    assert_not_includes response.body, "Secret area"

    params = params_as_rendered
    submitted = params["group"]["grants"]
    assert_equal [ "", fixture[:a].id.to_s, fixture[:hidden].id.to_s ].sort, [ "" ].concat(submitted["pages.edit"]["page_ids"]).sort
    assert_not_includes submitted["pages.edit"]["page_ids"], fixture[:section].id.to_s
    assert_not_includes submitted["pages.edit"]["page_ids"], fixture[:a1].id.to_s
    assert_equal [ "blog", "retired_type" ], submitted["posts.edit"]["content_types"].reject(&:blank?).sort

    before = grants_snapshot(fixture[:group])
    assert_no_difference -> { Audit::Event.count } do
      patch "/cs-studio/groups/#{fixture[:group].id}", params: params
    end

    assert_redirected_to "/cs-studio/groups/#{fixture[:group].id}/edit"
    assert_equal 303, response.status
    assert_equal before, grants_snapshot(fixture[:group]), "no grant was rewritten or changed"
    assert_equal [ users(:author) ], fixture[:group].users.reload.to_a
  end

  test "the same untouched save by an owner changes nothing either" do
    fixture = review_focus_group
    sign_in_as(users(:one))
    get "/cs-studio/groups/#{fixture[:group].id}/edit"
    before = grants_snapshot(fixture[:group])

    assert_no_difference -> { Audit::Event.count } do
      patch "/cs-studio/groups/#{fixture[:group].id}", params: params_as_rendered
    end

    assert_response :see_other
    assert_equal before, grants_snapshot(fixture[:group])
  end

  test "Remove on the removed type is the one change: that value gone, nothing else touched" do
    fixture = review_focus_group
    sign_in_as(users(:one))
    get "/cs-studio/groups/#{fixture[:group].id}/edit"
    params = params_as_rendered
    params["group"]["grants"]["posts.edit"]["content_types"].delete("retired_type")

    patch "/cs-studio/groups/#{fixture[:group].id}", params: params

    assert_response :see_other
    assert_equal({ "content_types" => [ "blog" ], "own" => true }, fixture[:group].grants.find_by!(permission: "posts.edit").scope)
    assert_equal({ "page_ids" => [ fixture[:a].id, fixture[:hidden].id ].sort }, fixture[:group].grants.find_by!(permission: "pages.edit").scope)
  end

  test "with no live type ticked, a carried removed type is read as all content types, as the editor shows it" do
    fixture = review_focus_group
    sign_in_as(users(:one))
    get "/cs-studio/groups/#{fixture[:group].id}/edit"
    params = params_as_rendered
    params["group"]["grants"]["posts.edit"]["content_types"] = [ "retired_type" ]

    patch "/cs-studio/groups/#{fixture[:group].id}", params: params

    assert_equal({ "own" => true }, fixture[:group].grants.find_by!(permission: "posts.edit").scope)
  end

  test "a failed save keeps what was typed, and opens the row the error names" do
    fixture = review_focus_group
    sign_in_as(users(:one))

    patch "/cs-studio/groups/#{fixture[:group].id}", params: { group: {
      name: "", member_ids: [ "" ],
      grants: { "posts.edit" => { enabled: "1", content_types: [ "", "blog", "retired_type" ], own: "1" }, "not.registered" => { enabled: "1" } }
    } }

    assert_response :unprocessable_entity
    assert_select "[data-permission='posts.edit'] input[name$='[own]'][checked]"
    assert_select "[data-removed-type=retired_type]"
    assert_select "[data-save-bar-dirty-value], [data-admin--save-bar-dirty-value=true]"
  end

  test "a plugin permission is a toggle in a card of its own area, and saves" do
    AccessControl::Permissions.register "acme/widgets.use", label: "Use widgets", area: "Widgets", action: :use
    sign_in_as(users(:one))

    get "/cs-studio/groups/new"
    assert_select "section h3", text: "Widgets"
    assert_select "input[type=checkbox][role=switch][name='group[grants][acme/widgets.use][enabled]']"

    post "/cs-studio/groups", params: { group: { name: "Widgeteers", member_ids: [ "" ], grants: { "acme/widgets.use" => { enabled: "1" } } } }
    assert_equal [ "acme/widgets.use" ], AccessControl::Group.find_by!(name: "Widgeteers").grants.pluck(:permission)
  ensure
    AccessControl::Permissions.reset!
    AccessControl::BuiltIns.register
  end

  test "the editor is eleven rows and three toggle cards, up to 1000px, with the key as each row's title" do
    sign_in_as(users(:one))
    get "/cs-studio/groups/new"

    assert_select "[data-permission]", count: 11
    assert_select "[data-permission='posts.delete'] code[title='posts.delete']"
    assert_select "section h3", text: /Content|Administration|Oversight/, count: 3
    assert_select ".max-w-\\[1000px\\]"
    assert_select "[class*='mx-auto']", count: 0
  end

  private

  # The group of the Review Focus 3 tests, and the pages it points at. `editor_branch`
  # manages groups and reads only `section`'s branch -- `hidden` is a stored root
  # they can't open.
  def review_focus_group
    section = as_owner { create_page(title: "Public area") }
    a = as_owner { create_page(title: "Branch A", parent: section) }
    a1 = as_owner { create_page(title: "Leaf A1", parent: a) }
    as_owner { create_page(title: "Branch B", parent: section) }
    hidden = as_owner { create_page(title: "Secret area") }

    managers = AccessControl::Group.create!(name: "Group managers")
    AccessControl::Grant.create!(group: managers, permission: "groups.manage", scope: {})
    AccessControl::Grant.create!(group: managers, permission: "pages.read", scope: { "page_ids" => [ section.id ] })
    AccessControl::Membership.create!(user: users(:editor_branch), group: managers)

    group = AccessControl::Group.create!(name: "Mixed", description: "Everything at once")
    AccessControl::Grant.create!(group: group, permission: "posts.edit", scope: { "content_types" => %w[blog retired_type], "own" => true })
    AccessControl::Grant.create!(group: group, permission: "posts.read", scope: { "content_types" => [ "now_update" ] })
    AccessControl::Grant.create!(group: group, permission: "posts.create", scope: {})
    AccessControl::Grant.create!(group: group, permission: "pages.edit", scope: { "page_ids" => [ a.id, hidden.id ].sort })
    AccessControl::Grant.create!(group: group, permission: "pages.read", scope: { "page_ids" => [ section.id ] })
    AccessControl::Grant.create!(group: group, permission: "tags.manage", scope: {})
    AccessControl::Membership.create!(user: users(:author), group: group)

    { group: group, section: section, a: a, a1: a1, hidden: hidden }
  end

  def grants_snapshot(group) = group.grants.reload.order(:id).map { |grant| [ grant.id, grant.permission, grant.scope ] }

  # What a browser would post for the group form just fetched: every named
  # control that is not disabled, a checkbox only while ticked, in document
  # order (so repeated names make arrays) -- the request the editor makes when
  # the Save button is pressed with nothing touched. Indeterminate is not a
  # thing a server render can say, but a partial box is rendered unchecked.
  def params_as_rendered
    form = Nokogiri::HTML(response.body).at_css("form#group-form")
    pairs = form.css("input, textarea, select").filter_map do |field|
      name = field["name"]
      next if name.blank? || field["disabled"] || field["type"] == "submit"
      next if %w[checkbox radio].include?(field["type"]) && !field["checked"]

      [ name, field.name == "textarea" ? field.text : (field["value"] || (field["type"].in?(%w[checkbox radio]) ? "on" : "")) ]
    end
    Rack::Utils.parse_nested_query(pairs.map { |name, value| "#{CGI.escape(name)}=#{CGI.escape(value)}" }.join("&")).tap { |params| params["_method"] = "patch" }
  end

  # Every SQL statement the block issues (see `Admin::AccessControlTest#count_queries`).
  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end

  def dom_id(record) = ActionView::RecordIdentifier.dom_id(record)

  test "the delete dialog escapes a hostile token name" do
    sign_in_as(users(:one))
    group = AccessControl::Group.create!(name: "Hostile bots")
    ApiToken.generate!(users(:reader), group:, name: "<script>x</script>")

    get "/cs-studio/groups/#{group.id}/edit"

    assert_select "dialog#delete-group-#{group.id} li script", count: 0
    assert_select "dialog#delete-group-#{group.id} li", text: /<script>x<\/script> — /
  end
end
