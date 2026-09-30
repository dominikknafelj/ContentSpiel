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
      assert_select "*", text: /Admin/
      assert_select "*", text: /1 member/
      assert_select "*", text: /Built-in/
    end
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
      assert_select "li", text: /API token ##{token.id}.*#{Regexp.escape(users(:reader).email_address)}/
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
    assert_select "input[name='group[grants][posts.edit][content_types][]'][value=retired_type]", count: 0
    assert_select ".admin-stale-grant", text: /retired_type.*no longer exists/
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

  private

  def dom_id(record) = ActionView::RecordIdentifier.dom_id(record)
end
