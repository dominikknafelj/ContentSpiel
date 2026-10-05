require "test_helper"

# The group editor's members, locked ticks, delete zone and view-only state
# (round 3 Task 11). The rules are `Groups::Save`/`Groups::Destroy`'s and are
# unchanged: everything here is what the form shows and carries, plus -- for the
# forged requests -- proof that the services still refuse. Review Focus 3 throughout:
# a form submitted exactly as rendered changes nothing, for an owner and for a
# non-owner manager.
class Admin::GroupsEditorStatesTest < ActionDispatch::IntegrationTest
  include ContentHelper

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
  end

  # --- Members as chips -------------------------------------------------------

  test "members are chips with the name as label and the email as hint, tracked hidden inputs and the blank sentinel; no checkbox per user" do
    group = AccessControl::Group.create!(name: "Writers")
    users(:reader).update_columns(name: "Rita Reader")
    AccessControl::Membership.create!(user: users(:reader), group: group)
    AccessControl::Membership.create!(user: users(:author), group: group)
    sign_in_as(users(:one))

    get "/cs-studio/groups/#{group.id}/edit"

    assert_response :success
    assert_select "form#group-form .admin-group-members" do
      assert_select "input[type=hidden][name='group[member_ids][]'][value=''][data-save-bar-track]", count: 1
      assert_select "li[data-chip-value='#{users(:reader).id}']", text: /Rita Reader\s*·\s*reader@example.com/
      assert_select "li[data-chip-value='#{users(:reader).id}'] input[type=hidden][name='group[member_ids][]'][data-save-bar-track]"
      assert_select "li[data-chip-value='#{users(:author).id}']", text: /author@example\.com/
      assert_select "li[data-chip-value='#{users(:author).id}'] [data-chip-hint]", count: 0
      assert_select "[data-controller='admin--chip-input'][data-admin--chip-input-search-url-value='/cs-studio/users/suggest']"
      assert_select "p", text: "Owners aren't listed: they already have every permission."
    end
    assert_select "input[type=checkbox][name='group[member_ids][]']", count: 0
  end

  test "adding, removing and emptying the member list" do
    group = AccessControl::Group.create!(name: "Writers")
    AccessControl::Membership.create!(user: users(:reader), group: group)
    sign_in_as(users(:one))

    patch "/cs-studio/groups/#{group.id}", params: { group: { name: "Writers", member_ids: [ "", users(:reader).id, users(:author).id ], grants: {} } }
    assert_response :see_other
    assert_equal [ users(:author), users(:reader) ].sort_by(&:id), group.users.reload.sort_by(&:id)

    patch "/cs-studio/groups/#{group.id}", params: { group: { name: "Writers", member_ids: [ "", users(:author).id ], grants: {} } }
    assert_equal [ users(:author) ], group.users.reload.to_a

    patch "/cs-studio/groups/#{group.id}", params: { group: { name: "Writers", member_ids: [ "" ], grants: {} } }
    assert_empty group.users.reload
  end

  # Final fix wave (Task 11): the chip input posts ids; a forged one is the
  # service's to judge. An id that names nobody is no member (never a 500, and
  # no change recorded); an owner's id -- never offered by the suggestions --
  # is still a user id, so it is added like any other: owners already hold
  # everything, the membership gives them nothing.
  test "a forged member id: one that names nobody is ignored, an owner's is an ordinary member" do
    group = AccessControl::Group.create!(name: "Writers")
    AccessControl::Membership.create!(user: users(:reader), group: group)
    sign_in_as(users(:one))
    missing = User.maximum(:id) + 1000

    assert_no_difference -> { Audit::Event.where(action: "group.updated").count } do
      patch "/cs-studio/groups/#{group.id}", params: { group: { name: "Writers", member_ids: [ "", users(:reader).id, missing, "abc" ], grants: {} } }
    end
    assert_response :see_other
    assert_equal [ users(:reader) ], group.users.reload.to_a

    patch "/cs-studio/groups/#{group.id}", params: { group: { name: "Writers", member_ids: [ "", users(:reader).id, users(:one).id ], grants: {} } }
    assert_response :see_other
    assert_equal [ users(:one), users(:reader) ].sort_by(&:id), group.users.reload.sort_by(&:id)
    get "/cs-studio/groups/#{group.id}/edit"
    assert_select "input[type=hidden][name='group[member_ids][]'][value='#{users(:one).id}']"
  end

  test "a non-owner manager's forged member ids are judged the same way: nobody for a missing id, the escalation rule for a real one" do
    group = AccessControl::Group.create!(name: "Everything")
    AccessControl::Grant.create!(group: group, permission: "users.manage", scope: {})
    sign_in_as(manager_user(grants: { "groups.manage" => {} }))

    as_stored = { "users.manage" => { enabled: "1" } }

    patch "/cs-studio/groups/#{group.id}", params: { group: { name: "Everything", member_ids: [ "", User.maximum(:id) + 1000 ], grants: as_stored } }
    assert_response :see_other
    assert_empty group.users.reload

    assert_difference -> { Audit::Event.where(action: "access.denied").sum(:occurrences) }, 1 do
      patch "/cs-studio/groups/#{group.id}", params: { group: { name: "Everything", member_ids: [ "", users(:one).id ], grants: as_stored } }
    end
    assert_response :forbidden
    assert_empty group.users.reload
  end

  test "an owner who is already a member stays as a chip until removed, and an untouched save keeps them (owner and non-owner viewers)" do
    group = AccessControl::Group.create!(name: "Mixed crew", description: "Everyone")
    AccessControl::Grant.create!(group: group, permission: "posts.read", scope: {})
    AccessControl::Membership.create!(user: users(:one), group: group)
    AccessControl::Membership.create!(user: users(:reader), group: group)

    [ users(:one), manager_user(grants: { "groups.manage" => {}, "posts.read" => {} }) ].each do |viewer|
      sign_in_as(viewer)
      get "/cs-studio/groups/#{group.id}/edit"
      assert_select "li[data-chip-value='#{users(:one).id}']", text: /Owner/
      assert_select "li[data-chip-value='#{users(:one).id}'] input[type=hidden][name='group[member_ids][]'][value='#{users(:one).id}']"

      before = [ group.memberships.reload.pluck(:user_id).sort, group.grants.reload.pluck(:permission, :scope) ]
      assert_no_difference -> { Audit::Event.count } do
        patch "/cs-studio/groups/#{group.id}", params: params_as_rendered
      end
      assert_response :see_other
      assert_equal before, [ group.memberships.reload.pluck(:user_id).sort, group.grants.reload.pluck(:permission, :scope) ]
    end
  end

  test "a failed save keeps the member chips that were posted" do
    sign_in_as(users(:one))

    post "/cs-studio/groups", params: { group: { name: "", member_ids: [ "", users(:author).id ], grants: {} } }

    assert_response :unprocessable_entity
    assert_select "li[data-chip-value='#{users(:author).id}'] input[name='group[member_ids][]']"
    assert_select "li[data-chip-value='#{users(:reader).id}']", count: 0
  end

  # --- Save and create ---------------------------------------------------------

  test "Save group keeps the editor open with the toast; a new group says Create group, then opens its editor" do
    sign_in_as(users(:one))

    get "/cs-studio/groups/new"
    assert_select ".admin-save-bar button[type=submit]", text: "Create group"

    post "/cs-studio/groups", params: { group: { name: "Fresh", member_ids: [ "" ], grants: {} } }
    group = AccessControl::Group.find_by!(name: "Fresh")
    assert_redirected_to "/cs-studio/groups/#{group.id}/edit"
    assert_equal 303, response.status
    follow_redirect!
    assert_select ".admin-save-bar button[type=submit]", text: "Save group"
    assert_select "#toasts", text: /Group saved/
  end

  # --- Locked ticks -------------------------------------------------------------

  # A removed content type's name is dormant, not gone, and a group is judged
  # as stored (`AccessControl.can_manage_group?`): the row is editable -- with
  # its Remove chip -- only for a viewer who could grant that name. Here the
  # viewer's own grant names it.
  test "a grant carrying a removed type the viewer's own grant names is editable, with its Remove chip; an untouched save changes nothing" do
    group = locked_scenario_group
    sign_in_as(manager_user(grants: { "groups.manage" => {}, "posts.edit" => { "content_types" => %w[blog retired_type] }, "posts.read" => {}, "tags.manage" => {} }))

    get "/cs-studio/groups/#{group.id}/edit"
    assert_response :success

    assert_select "[data-locked]", count: 0
    assert_select "[data-permission='posts.edit']" do
      assert_select "input[type=checkbox][name='group[grants][posts.edit][enabled]'][checked]:not([disabled])"
      assert_select "button", text: "Edit scope"
      assert_select "[data-removed-type=retired_type] button", text: "Remove"
    end
    assert_select ".admin-locked-hint", count: 0
    assert_select "fieldset[disabled]", count: 0

    before = grants_snapshot(group)
    params = params_as_rendered
    assert_equal %w[blog retired_type], params["group"]["grants"]["posts.edit"]["content_types"].reject(&:blank?).sort
    assert_equal "1", params["group"]["grants"]["posts.edit"]["own"]

    assert_no_difference -> { Audit::Event.count } do
      patch "/cs-studio/groups/#{group.id}", params: params
    end

    assert_redirected_to "/cs-studio/groups/#{group.id}/edit"
    assert_equal 303, response.status
    assert_equal before, grants_snapshot(group)
    assert_equal [ users(:reader) ], group.users.reload.to_a
  end

  test "a group storing a removed type is view-only for a viewer who could only grant the live one: the notice, a disabled fieldset, no footer, no delete zone" do
    group = locked_scenario_group
    sign_in_as(manager_user(grants: { "groups.manage" => {}, "posts.edit" => { "content_types" => [ "blog" ] }, "posts.read" => {}, "tags.manage" => {} }))

    get "/cs-studio/groups/#{group.id}/edit"

    assert_response :success
    assert_select "p.admin-view-only-notice", text: "This group has permissions you can't hand out, so you can only view it."
    assert_select "form#group-form fieldset.admin-view-only[disabled]" do
      assert_select "[data-permission='posts.edit'] input[type=checkbox][name$='[enabled]'][checked]"
      # The removed type is still there to be read.
      assert_select "[data-permission='posts.edit'] [data-removed-type=retired_type]"
    end
    assert_select "[data-permission='posts.edit'] a[role=button]", text: "View scope"
    assert_select "button", text: "Edit scope", count: 0
    assert_select "[data-locked]", count: 0
    assert_select ".admin-save-bar", count: 0
    assert_select "form#group-form button[type=submit]", count: 0
    assert_select ".admin-delete-zone", count: 0
    page = Nokogiri::HTML(response.body)
    enabled = page.css("form#group-form input[name], form#group-form select[name], form#group-form textarea[name], form#group-form button").reject { |field| field.ancestors("fieldset[disabled]").any? || field["type"] == "hidden" && field["name"] == "_method" }
    assert_empty enabled.map { |field| field["name"] || field.text.strip }, "nothing in the form may be enabled, Remove included"
  end

  test "a group whose only grant for a permission names removed types alone is view-only for a viewer who couldn't grant them, editable for an owner" do
    group = AccessControl::Group.create!(name: "Dormant only")
    AccessControl::Grant.create!(group: group, permission: "posts.edit", scope: { "content_types" => [ "retired_type" ] })
    AccessControl::Grant.create!(group: group, permission: "posts.read", scope: {})

    sign_in_as(manager_user(grants: { "groups.manage" => {}, "posts.edit" => { "content_types" => [ "blog" ] }, "posts.read" => {} }))
    get "/cs-studio/groups/#{group.id}/edit"
    assert_select "p.admin-view-only-notice"
    assert_select "form#group-form fieldset.admin-view-only[disabled]"
    assert_select ".admin-save-bar", count: 0

    sign_in_as(users(:one))
    get "/cs-studio/groups/#{group.id}/edit"
    assert_select "p.admin-view-only-notice", count: 0
    assert_select "fieldset[disabled]", count: 0
    assert_select ".admin-save-bar"
  end

  test "the Remove chip of a removed type is offered to an unscoped holder and to an owner, and pressing it is saved" do
    group = locked_scenario_group

    sign_in_as(users(:one))
    get "/cs-studio/groups/#{group.id}/edit"
    assert_select "fieldset[disabled]", count: 0
    assert_select "[data-removed-type=retired_type] button", text: "Remove"

    sign_in_as(manager_user(grants: { "groups.manage" => {}, "posts.edit" => {}, "posts.read" => {} }))
    get "/cs-studio/groups/#{group.id}/edit"
    assert_select "fieldset[disabled]", count: 0
    assert_select "[data-removed-type=retired_type] button", text: "Remove"

    # What Remove does: the carried hidden input is disabled, so the name isn't posted.
    params = params_as_rendered
    params["group"]["grants"]["posts.edit"]["content_types"].delete("retired_type")
    assert_no_difference -> { Audit::Event.where(action: "access.denied").count } do
      patch "/cs-studio/groups/#{group.id}", params: params
    end
    assert_response :see_other
    assert_equal [ { "content_types" => [ "blog" ], "own" => true }, {} ], group.grants.reload.order(:id).map(&:scope)
  end

  test "a tick the viewer typed comes back ticked and editable after a refused save, never locked" do
    sign_in_as(manager_user(grants: { "groups.manage" => {}, "posts.read" => {} }))

    post "/cs-studio/groups", params: { group: { name: "", member_ids: [ "" ], grants: {
      "posts.publish" => { enabled: "1", content_types: [ "", "blog" ] }, "trash.empty" => { enabled: "1" } } } }

    assert_response :unprocessable_entity
    assert_select "[data-locked]", count: 0
    assert_select ".admin-locked-note", count: 0
    assert_select "[data-permission='posts.publish'] input[type=checkbox][name$='[enabled]'][checked]:not([disabled])"
    assert_select "[data-permission='posts.publish'] input[type=checkbox][value=blog][checked]"
    assert_select "[data-permission='posts.publish'] button", text: "Edit scope"
    assert_select "input[type=checkbox][name='group[grants][trash.empty][enabled]'][checked]:not([disabled])"
  end

  test "a tick the editor changed on an existing group comes back editable after a refused save" do
    group = AccessControl::Group.create!(name: "Stored", description: "x")
    AccessControl::Grant.create!(group: group, permission: "posts.read", scope: {})
    sign_in_as(manager_user(grants: { "groups.manage" => {}, "posts.read" => {} }))

    patch "/cs-studio/groups/#{group.id}", params: { group: { name: "", member_ids: [ "" ], grants: {
      "posts.read" => { enabled: "1" }, "trash.empty" => { enabled: "1" } } } }

    assert_response :unprocessable_entity
    assert_select "[data-locked]", count: 0
    assert_select "input[type=checkbox][name='group[grants][trash.empty][enabled]'][checked]:not([disabled])"
  end

  test "an owner sees no locks" do
    group = locked_scenario_group
    sign_in_as(users(:one))

    get "/cs-studio/groups/#{group.id}/edit"

    assert_select "[data-locked]", count: 0
    assert_select ".admin-locked-note", count: 0
    assert_select "[data-permission='posts.edit'] button", text: "Edit scope"
  end

  test "forged requests against a grant carrying a removed type are refused by the service: widening it is a 403 with one access.denied and nothing stored" do
    group = locked_scenario_group
    sign_in_as(manager_user(grants: { "groups.manage" => {}, "posts.edit" => { "content_types" => [ "blog" ] }, "posts.read" => {} }))
    before = grants_snapshot(group)

    # Dropping the type list widens {blog, retired} to every type: the viewer holds {blog} only.
    assert_difference -> { Audit::Event.where(action: "access.denied").count }, 1 do
      patch "/cs-studio/groups/#{group.id}", params: { group: { name: group.name, member_ids: [ "", users(:reader).id ],
        grants: { "posts.edit" => { enabled: "1" }, "posts.read" => { enabled: "1" } } } }
    end

    assert_response :forbidden
    assert_equal before, grants_snapshot(group)
  end

  # Fix round 2 of Task 10: the request the editor makes when "Own only" is unticked
  # on a row that carries a removed type, without pressing Remove first -- the form as
  # rendered, minus `own`. For a viewer who holds {blog} the group is view-only, so
  # the form as rendered is taken from an owner's editor and the request is a forged
  # one; the service decides. `Groups::Save` judges a grant that changed with a
  # removed type still on it raw, so the name the viewer can't hand out refuses it.
  test "Own only unticked on a row that carries a removed type, without Remove, is a 403 with one access.denied and nothing stored" do
    group = locked_scenario_group
    sign_in_as(users(:one))
    get "/cs-studio/groups/#{group.id}/edit"
    assert_select "fieldset[disabled]", count: 0 # an editable form, not view-only
    params = params_as_rendered
    assert_equal "1", params["group"]["grants"]["posts.edit"].delete("own")

    sign_in_as(manager_user(grants: { "groups.manage" => {}, "posts.edit" => { "content_types" => [ "blog" ] }, "posts.read" => {} }))
    get "/cs-studio/groups/#{group.id}/edit"
    assert_select "fieldset.admin-view-only[disabled]"
    before = grants_snapshot(group)

    assert_no_difference -> { Audit::Event.where(action: "group.updated").count } do
      assert_difference -> { Audit::Event.where(action: "access.denied").sum(:occurrences) }, 1 do
        patch "/cs-studio/groups/#{group.id}", params: params
      end
    end

    assert_response :forbidden
    assert_equal before, grants_snapshot(group)
  end

  # The form as an owner sees it, posted by a viewer who could only grant "blog",
  # with one more member: the member would be handed the removed name too.
  test "a forged request adding a member to a group that stores a removed type, grants as rendered, is a 403 with one access.denied" do
    group = locked_scenario_group
    sign_in_as(users(:one))
    get "/cs-studio/groups/#{group.id}/edit"
    params = params_as_rendered
    params["group"]["member_ids"] = [ "", users(:reader).id.to_s, users(:author).id.to_s ]

    sign_in_as(manager_user(grants: { "groups.manage" => {}, "posts.edit" => { "content_types" => [ "blog" ] }, "posts.read" => {} }))
    before = grants_snapshot(group)
    assert_difference -> { Audit::Event.where(action: "access.denied").sum(:occurrences) }, 1 do
      patch "/cs-studio/groups/#{group.id}", params: params
    end

    assert_response :forbidden
    assert_equal before, grants_snapshot(group)
    assert_equal [ users(:reader) ], group.users.reload.to_a
  end

  # The group is view-only for this viewer, and the service is the backstop:
  # giving up a removed content type's name is a removal, so the request Remove
  # would make -- forged here, the form offers them no Remove -- is refused.
  test "a forged request dropping a removed type from a group the viewer can only view is a 403 with one access.denied and nothing stored" do
    group = AccessControl::Group.create!(name: "G")
    AccessControl::Grant.create!(group: group, permission: "posts.edit", scope: { "content_types" => %w[blog retired_type] })
    sign_in_as(manager_user(grants: { "groups.manage" => {}, "posts.edit" => { "content_types" => [ "blog" ] } }))
    get "/cs-studio/groups/#{group.id}/edit"
    assert_select "fieldset.admin-view-only[disabled]"
    before = grants_snapshot(group)

    assert_no_difference -> { Audit::Event.where(action: "group.updated").count } do
      assert_difference -> { Audit::Event.where(action: "access.denied").sum(:occurrences) }, 1 do
        patch "/cs-studio/groups/#{group.id}", params: { group: { name: "G", member_ids: [ "" ],
          grants: { "posts.edit" => { enabled: "1", content_types: [ "", "blog" ] } } } }
      end
    end

    assert_response :forbidden
    assert_equal before, grants_snapshot(group)
    get "/cs-studio/groups/#{group.id}/edit"
    assert_select "fieldset.admin-view-only[disabled]"
  end

  # The dead-grant variant: `posts.read {retired_type}` is never rendered ticked,
  # so the form as an owner sees it doesn't post it -- saving it drops the grant.
  test "the form as rendered, posted by a viewer who can only view a group with a dormant dead grant, is a 403 with one access.denied and nothing stored" do
    group = dormant_dead_group
    sign_in_as(users(:one))
    get "/cs-studio/groups/#{group.id}/edit"
    params = params_as_rendered
    assert_nil params["group"]["grants"]["posts.read"]

    sign_in_as(manager_user(grants: { "groups.manage" => {}, "posts.edit" => { "content_types" => [ "blog" ] } }))
    get "/cs-studio/groups/#{group.id}/edit"
    assert_select "fieldset.admin-view-only[disabled]"
    assert_select ".admin-stale-grant", text: "Limited to a content type that no longer exists (retired_type). Saving removes it; until then only someone who could grant that type can manage this group."
    before = grants_snapshot(group)

    assert_no_difference -> { Audit::Event.where(action: "group.updated").count } do
      assert_difference -> { Audit::Event.where(action: "access.denied").sum(:occurrences) }, 1 do
        patch "/cs-studio/groups/#{group.id}", params: params
      end
    end

    assert_response :forbidden
    assert_equal before, grants_snapshot(group)
  end

  # The way out of that state: a dormant dead grant has no chip and no tick, so
  # the note names it and Save is enabled with nothing touched -- saving the form
  # as rendered is what removes it.
  test "an owner opens a group with a dormant dead grant: the note says how to clear it, Save is enabled untouched, saving drops the grant, and the manager's form is editable afterwards" do
    group = dormant_dead_group
    manager = manager_user(grants: { "groups.manage" => {}, "posts.edit" => { "content_types" => [ "blog" ] } })

    sign_in_as(users(:one))
    get "/cs-studio/groups/#{group.id}/edit"
    assert_select "fieldset[disabled]", count: 0
    assert_select ".admin-stale-grant", text: "Limited to a content type that no longer exists (retired_type). Saving removes it; until then only someone who could grant that type can manage this group."
    assert_select "[data-permission='posts.read'] input[type=checkbox][name$='[enabled]'][checked]", count: 0
    # Save is live from the start, without a counted change (so leaving doesn't ask).
    assert_select "form#group-form[data-admin--save-bar-always-value=true][data-admin--save-bar-dirty-value=false]"

    assert_difference -> { Audit::Event.where(action: "group.updated", subject_id: group.id).count }, 1 do
      patch "/cs-studio/groups/#{group.id}", params: params_as_rendered
    end
    assert_response :see_other
    assert_equal [ [ "posts.edit", { "content_types" => [ "blog" ] } ] ], group.grants.reload.map { |grant| [ grant.permission, grant.scope ] }

    follow_redirect!
    assert_select ".admin-stale-grant", count: 0
    assert_select "form#group-form[data-admin--save-bar-always-value=false]"

    sign_in_as(manager)
    get "/cs-studio/groups/#{group.id}/edit"
    assert_select "p.admin-view-only-notice", count: 0
    assert_select "fieldset[disabled]", count: 0
    assert_select ".admin-save-bar"
  end

  test "a group with nothing dormant keeps Save waiting for a change, and a dead grant that can never come back doesn't enable it" do
    page = as_owner { create_page(title: "Doomed") }
    group = AccessControl::Group.create!(name: "Plain")
    AccessControl::Grant.create!(group: group, permission: "posts.edit", scope: { "content_types" => %w[blog retired_type] })
    AccessControl::Grant.create!(group: group, permission: "pages.edit", scope: { "page_ids" => [ page.id ] })
    as_owner { delete_for_good(page) }
    sign_in_as(users(:one))

    get "/cs-studio/groups/#{group.id}/edit"

    assert_select ".admin-stale-grant", text: /matched nothing\. It stays off unless you tick it again\./
    assert_select "form#group-form[data-admin--save-bar-always-value=false]"
  end

  # Final fix wave (Task 11): the two groups differ ONLY in how many unscoped
  # rows and toggles are ticked (one against seven), every one of them a grant
  # the viewer holds and so has to be checked for a lock. Exactly the same
  # number of queries -- not "at most a few more", which a query per row could
  # hide behind for a small enough difference.
  test "the lock check costs no query per row: seven ticked unscoped rows ask exactly what one does" do
    keys = %w[posts.read posts.create posts.edit posts.publish pages.read tags.manage media.upload]
    manager = manager_user(grants: keys.index_with { {} }.merge("groups.manage" => {}))
    few = AccessControl::Group.create!(name: "Few")
    AccessControl::Grant.create!(group: few, permission: "posts.read", scope: {})
    many = AccessControl::Group.create!(name: "Many")
    keys.each { |key| AccessControl::Grant.create!(group: many, permission: key, scope: {}) }
    sign_in_as(manager)

    get "/cs-studio/groups/#{few.id}/edit"
    base = count_queries { get "/cs-studio/groups/#{few.id}/edit" }
    assert_select "[data-locked]", count: 0
    with_more = count_queries { get "/cs-studio/groups/#{many.id}/edit" }
    assert_select "[data-locked]", count: 0
    assert_select "[data-permission] input[type=checkbox][name$='[enabled]'][checked]", minimum: 5

    assert_equal base, with_more, "ticked rows must not run queries of their own"
  end

  # --- Review Focus 3, non-owner, editable form, page tree --------------------------

  test "a non-owner who can manage the group, with an unreadable carried root, a redundant root, a removed type and an owner member, saves it untouched: nothing changes" do
    section = as_owner { create_page(title: "Section") }
    a = as_owner { create_page(title: "Branch A", parent: section) }
    a1 = as_owner { create_page(title: "Leaf A1", parent: a) }
    gone = as_owner { create_page(title: "Soon trashed", parent: section) }
    as_owner { assert Trash::Move.call(gone).ok? }

    sign_in_as(manager_user(grants: {
      "groups.manage" => {}, "posts.edit" => {}, "posts.read" => {}, "tags.manage" => {},
      "pages.read" => { "page_ids" => [ section.id ] }, "pages.edit" => { "page_ids" => [ section.id ] }, "pages.publish" => { "page_ids" => [ section.id ] }
    }))

    group = AccessControl::Group.create!(name: "Target", description: "Everything at once")
    AccessControl::Grant.create!(group: group, permission: "posts.edit", scope: { "content_types" => %w[blog retired_type], "own" => true })
    AccessControl::Grant.create!(group: group, permission: "posts.read", scope: { "content_types" => [ "now_update" ] })
    AccessControl::Grant.create!(group: group, permission: "pages.edit", scope: { "page_ids" => [ a.id, gone.id ].sort })
    AccessControl::Grant.create!(group: group, permission: "pages.publish", scope: { "page_ids" => [ section.id, a1.id ].sort })
    AccessControl::Grant.create!(group: group, permission: "tags.manage", scope: {})
    AccessControl::Membership.create!(user: users(:author), group: group)
    AccessControl::Membership.create!(user: users(:one), group: group)

    get "/cs-studio/groups/#{group.id}/edit"
    assert_response :success
    assert_select "fieldset[disabled]", count: 0
    assert_select "[data-locked]", count: 0
    assert_select ".admin-save-bar"
    assert_select "li[data-chip-value='#{users(:one).id}']"
    assert_select "[data-permission='pages.edit'] input[type=hidden][name$='[page_ids][]'][value='#{gone.id}']"

    grants_before = grants_snapshot(group)
    members_before = group.memberships.reload.pluck(:user_id).sort
    assert_no_difference -> { Audit::Event.count } do
      patch "/cs-studio/groups/#{group.id}", params: params_as_rendered
    end

    assert_redirected_to "/cs-studio/groups/#{group.id}/edit"
    assert_equal 303, response.status
    assert_equal grants_before, grants_snapshot(group)
    assert_equal members_before, group.memberships.reload.pluck(:user_id).sort
  end

  # --- View only ----------------------------------------------------------------

  test "a group the viewer can't manage as it stands is read-only: the notice, a disabled fieldset, no footer, no delete zone; a scope can still be opened" do
    group = AccessControl::Group.create!(name: "Everything", description: "All of it")
    AccessControl::Grant.create!(group: group, permission: "users.manage", scope: {})
    AccessControl::Grant.create!(group: group, permission: "posts.edit", scope: { "content_types" => [ "blog" ] })
    sign_in_as(manager_user(grants: { "groups.manage" => {} }))

    get "/cs-studio/groups/#{group.id}/edit"

    assert_response :success
    assert_select "p.admin-view-only-notice", text: "This group has permissions you can't hand out, so you can only view it."
    assert_select "form#group-form fieldset.admin-view-only[disabled]" do
      assert_select "input[name='group[name]']"
      assert_select "[data-permission='posts.edit'] input[type=checkbox][name$='[enabled]'][checked]"
    end
    assert_select ".admin-save-bar", count: 0
    assert_select "form#group-form button[type=submit]", count: 0
    assert_select ".admin-delete-zone", count: 0
    assert_select "dialog[id^=delete-group]", count: 0
    assert_select "button", text: "Edit scope", count: 0
    # The scope toggle is a link, which a disabled fieldset leaves alone.
    assert_select "[data-permission='posts.edit'] a[role=button][aria-controls][data-open-label='Hide scope']", text: "View scope"
    assert_select "[data-permission='posts.edit'] [data-scope-editor] input[value=blog][checked]"
    assert_select "[data-locked]", count: 0
    # Every named control that is not inside a disabled fieldset would be a leak.
    page = Nokogiri::HTML(response.body)
    enabled = page.css("form#group-form input[name], form#group-form select[name], form#group-form textarea[name]").reject { |field| field.ancestors("fieldset[disabled]").any? || field["type"] == "hidden" && field["name"] == "_method" }
    assert_empty enabled.map { |field| field["name"] }, "nothing in the form may be enabled"
  end

  test "forged requests against a group the viewer can only view are refused: untick and delete" do
    group = AccessControl::Group.create!(name: "Everything")
    AccessControl::Grant.create!(group: group, permission: "users.manage", scope: {})
    AccessControl::Membership.create!(user: users(:reader), group: group)
    sign_in_as(manager_user(grants: { "groups.manage" => {} }))
    before = grants_snapshot(group)

    assert_difference -> { Audit::Event.where(action: "access.denied").count }, 1 do
      patch "/cs-studio/groups/#{group.id}", params: { group: { name: "Everything", member_ids: [ "", users(:reader).id ], grants: {} } }
    end
    assert_response :forbidden
    assert_equal before, grants_snapshot(group)

    # (A refused attempt coalesces with the one before it, so only the answer and the effect are asserted.)
    delete "/cs-studio/groups/#{group.id}"
    assert_response :forbidden
    assert AccessControl::Group.exists?(group.id)
    assert_equal [ users(:reader) ], group.users.reload.to_a
  end

  test "a built-in group the viewer can manage shows its note, not the delete zone; one they can't is read-only" do
    sign_in_as(users(:one))
    get "/cs-studio/groups/#{access_control_groups(:read_only).id}/edit"
    assert_select ".admin-delete-zone", text: "A built-in group can be changed but not deleted."
    assert_select "button", text: /Delete group/, count: 0
    assert_select "dialog[id^=delete-group]", count: 0

    sign_in_as(manager_user(grants: { "groups.manage" => {} }))
    get "/cs-studio/groups/#{access_control_groups(:admin).id}/edit"
    assert_select "p.admin-view-only-notice"
    assert_select ".admin-delete-zone", count: 0
  end

  # --- The delete zone -----------------------------------------------------------

  test "the delete zone counts members and active tokens, and the dialog names the tokens: a revoked one is not among them" do
    sign_in_as(users(:one))
    group = AccessControl::Group.create!(name: "Bots")
    AccessControl::Membership.create!(user: users(:reader), group: group)
    AccessControl::Membership.create!(user: users(:author), group: group)
    token, raw = ApiToken.generate!(users(:reader), group: group, name: "Deploy bot")
    ApiToken.generate!(users(:author), group: group, name: "Old bot")[0].revoke!
    users(:author).update_columns(name: "Ann Author")

    get "/cs-studio/groups/#{group.id}/edit"

    assert_select ".admin-delete-zone" do
      assert_select "h2", text: "Delete this group"
      assert_select "p", text: "2 members lose its permissions. 1 AI token is revoked."
      assert_select "button.text-danger, button[class*='danger']", text: "Delete group…"
    end
    assert_select "dialog#delete-group-#{group.id}" do
      assert_select "h2, h1, [data-dialog-title]", text: "Delete “Bots”?"
      assert_select "*", text: "Its 2 members lose these permissions, and its 1 AI token is revoked. Users themselves are not deleted."
      assert_select "li", count: 1
      assert_select "li", text: /\ADeploy bot — reader@example\.com\z/
      assert_select "button[type=submit]", text: "Delete group"
    end
    assert_not_includes response.body, raw
    assert token.lookup_digest.present?
    assert_not response.body.include?(token.lookup_digest), "the token's digest is in the page"
    assert_select "form#group-form dialog", count: 0
    assert_select "form#group-form form", count: 0

    delete "/cs-studio/groups/#{group.id}"
    assert_redirected_to "/cs-studio/groups"
    follow_redirect!
    assert_select "#toasts", text: /Group deleted/
    assert_not AccessControl::Group.exists?(group.id)
  end

  test "the dialog's token list is bounded, and a group with no members or tokens says so" do
    sign_in_as(users(:one))
    group = AccessControl::Group.create!(name: "Busy")
    13.times { |i| ApiToken.generate!(users(:reader), group: group, name: "Bot #{i + 1}") }

    get "/cs-studio/groups/#{group.id}/edit"

    assert_select "dialog#delete-group-#{group.id} li", count: Admin::GroupsScreen::DeleteZoneComponent::MAX_TOKENS_SHOWN
    assert_select "dialog#delete-group-#{group.id}", text: /and 3 more/
    assert_select ".admin-delete-zone p", text: "It has no members. 13 AI tokens are revoked."

    empty = AccessControl::Group.create!(name: "Empty")
    get "/cs-studio/groups/#{empty.id}/edit"
    assert_select ".admin-delete-zone p", text: "It has no members. It has no AI tokens."
    assert_select "dialog#delete-group-#{empty.id} p", text: "It has no members. Users themselves are not deleted."
  end

  test "the delete zone's queries don't grow with members and tokens" do
    sign_in_as(users(:one))
    group = AccessControl::Group.create!(name: "Growing")
    AccessControl::Membership.create!(user: users(:reader), group: group)
    ApiToken.generate!(users(:reader), group: group)
    get "/cs-studio/groups/#{group.id}/edit"
    few = count_queries { get "/cs-studio/groups/#{group.id}/edit" }

    5.times do |i|
      user = User.create!(email_address: "m#{i}@example.org", password: "a-long-enough-password")
      AccessControl::Membership.create!(user: user, group: group)
      ApiToken.generate!(user, group: group)
    end
    many = count_queries { get "/cs-studio/groups/#{group.id}/edit" }

    assert_equal few, many
  end

  private

  def manager_user(grants:)
    user = User.create!(email_address: "manager-#{SecureRandom.hex(3)}@example.org", password: "a-long-enough-password")
    group = AccessControl::Group.create!(name: "Managers #{SecureRandom.hex(3)}")
    grants.each { |permission, scope| AccessControl::Grant.create!(group: group, permission: permission, scope: scope) }
    AccessControl::Membership.create!(user: user, group: group)
    user
  end

  # posts.edit {blog, retired_type, own} (the viewer of these tests holds {blog} only: the removed type is one they couldn't hand out)
  # and posts.read {} (the viewer holds it: ordinary), with one member.
  def locked_scenario_group
    group = AccessControl::Group.create!(name: "Locked scenario", description: "Locks")
    AccessControl::Grant.create!(group: group, permission: "posts.edit", scope: { "content_types" => %w[blog retired_type], "own" => true })
    AccessControl::Grant.create!(group: group, permission: "posts.read", scope: {})
    AccessControl::Membership.create!(user: users(:reader), group: group)
    group
  end

  # posts.edit {blog} (the manager's own right) and the dead `posts.read {retired_type}`:
  # dormant, so the group is one a {blog} holder can't manage.
  def dormant_dead_group
    group = AccessControl::Group.create!(name: "G")
    AccessControl::Grant.create!(group: group, permission: "posts.edit", scope: { "content_types" => [ "blog" ] })
    AccessControl::Grant.create!(group: group, permission: "posts.read", scope: { "content_types" => [ "retired_type" ] })
    group
  end

  def grants_snapshot(group) = group.grants.reload.order(:id).map { |grant| [ grant.id, grant.permission, grant.scope ] }

  # What a browser would post for the group form just fetched: every named control
  # that is not disabled (itself or by a disabled fieldset) and not inside a
  # `<template>` (the chip input's clone source), a checkbox only while
  # ticked, in document order -- the request Save makes with nothing touched.
  def params_as_rendered
    form = Nokogiri::HTML(response.body).at_css("form#group-form")
    pairs = form.css("input, textarea, select").filter_map do |field|
      name = field["name"]
      next if name.blank? || field["disabled"] || field["type"] == "submit" || field.ancestors("fieldset[disabled], template").any?
      next if %w[checkbox radio].include?(field["type"]) && !field["checked"]

      [ name, field.name == "textarea" ? field.text : (field["value"] || (field["type"].in?(%w[checkbox radio]) ? "on" : "")) ]
    end
    Rack::Utils.parse_nested_query(pairs.map { |name, value| "#{CGI.escape(name)}=#{CGI.escape(value)}" }.join("&")).tap { |params| params["_method"] = "patch" }
  end

  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
