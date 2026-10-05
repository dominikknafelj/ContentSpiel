require "application_system_test_case"

# The group editor's permission rows (access-control design spec §5, round 3
# Task 10): each row has its own scope chips and "Edit scope", the page tree is
# tri-state (`admin--branch-picker`), and the footer counts what the form would
# SUBMIT -- so opening a scope editor, or ticking a page that greys out its
# subpages, is as many changes as it really is.
class Admin::GroupsEditorSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @about = create_page(title: "About")
    @team = create_page(title: "Team", parent: @about)
    sign_in_via_form(users(:one))
  end

  test "tick Edit pages, pick About in the tree: Team is a greyed tick, Home a dash, the chip says Under About, and Save stores the root" do
    visit "/cs-studio/groups/new"
    await_admin_controllers
    fill_in "Name", with: "About editors"

    row = "[data-permission='pages.edit']"
    assert_selector "#{row} button", text: "Edit scope", visible: :hidden
    find("#{row} input[name='group[grants][pages.edit][enabled]']").check
    assert_selector "#{row} [data-chips]", text: "All pages"

    within(row) { click_button "Edit scope" }
    assert_selector "#{row} button[aria-expanded='true']", text: "Done"
    within("#{row} [data-scope-editor]") do
      # The child first, then its parent: a page ticked in this session and then
      # covered by a ticked ancestor must end as "included" all the same.
      check "Team"
      check "About"

      # Team sits under About: included, so a greyed tick that is not submitted.
      assert_selector "#grant-pages-edit-page-#{@team.id}:checked:disabled"
      assert_text "included"
      assert_text "includes 1 subpage"
    end
    # The ancestor of the chosen page is partial: Home's own box, and only that
    # one, is indeterminate and unchecked. (`indeterminate` is a property, so it
    # is read in the page; the `:indeterminate` selector makes the read wait.)
    assert_selector "#{row} .admin-branch-picker input[type=checkbox]:indeterminate", count: 1
    assert_selector "#grant-pages-edit-page-#{@about.parent_id}:indeterminate:not(:checked)"

    within(row) { click_button "Done" }
    assert_no_selector "#{row} [data-scope-editor]"
    assert_selector "#{row} [data-chips]", text: "Under About"
    assert_selector "#{row} [data-chips]", text: "All pages", count: 0

    press "Create group"
    assert_text "Group saved"

    group = AccessControl::Group.find_by!(name: "About editors")
    assert_equal({ "page_ids" => [ @about.id ] }, group.grants.find_by!(permission: "pages.edit").scope)
  end

  test "unticking a content type rewrites the chips and the footer counts that one change; opening and closing alone counts none" do
    group = AccessControl::Group.create!(name: "Writers")
    group.grants.create!(permission: "posts.edit", scope: { "content_types" => %w[blog now_update] })

    visit edit_admin_group_path(group)
    await_admin_controllers
    row = "[data-permission='posts.edit']"
    assert_selector ".admin-save-bar", text: /No unsaved changes/i
    assert_selector "#{row} [data-chips]", text: "Blog"
    assert_selector "#{row} [data-chips]", text: "Now update"

    within(row) { click_button "Edit scope" }
    assert_selector "#{row} [data-scope-editor]"
    assert_selector ".admin-save-bar", text: /No unsaved changes/i
    within(row) { click_button "Done" }
    assert_no_selector "#{row} [data-scope-editor]"
    assert_selector ".admin-save-bar", text: /No unsaved changes/i

    within(row) { click_button "Edit scope" }
    within("#{row} [data-scope-editor]") { uncheck "Now update" }
    assert_selector "#{row} [data-chips]", text: "Now update", count: 0
    assert_selector "#{row} [data-chips]", text: "Blog"
    assert_selector ".admin-save-bar", text: /\b1 unsaved change\b/i

    within("#{row} [data-scope-editor]") { check "Now update" }
    assert_selector ".admin-save-bar", text: /No unsaved changes/i
  end

  test "ticking a page whose subpages grey out is one change, not one per subpage" do
    group = AccessControl::Group.create!(name: "Pagers")
    group.grants.create!(permission: "pages.edit", scope: {})

    visit edit_admin_group_path(group)
    await_admin_controllers
    row = "[data-permission='pages.edit']"
    within(row) { click_button "Edit scope" }
    within("#{row} [data-scope-editor]") { check "About" }

    assert_selector ".admin-save-bar", text: /\b1 unsaved change\b/i
  end

  test "a removed content type is a warn chip: untouched it saves nothing, Remove is one counted change and drops it on Save" do
    group = AccessControl::Group.create!(name: "Retired")
    group.grants.create!(permission: "posts.edit", scope: { "content_types" => %w[blog retired_type] })

    visit edit_admin_group_path(group)
    await_admin_controllers
    row = "[data-permission='posts.edit']"
    assert_selector "#{row} [data-chips]", text: "! retired_type · type removed"
    assert_selector ".admin-save-bar", text: /No unsaved changes/i

    within(row) { click_button "Edit scope" }
    assert_selector "[data-removed-type='retired_type']", text: "this type no longer exists"
    within("[data-removed-type='retired_type']") { click_button "Remove" }

    assert_no_selector "#{row} [data-chips]", text: "retired_type"
    assert_selector ".admin-save-bar", text: /\b1 unsaved change\b/i
    press "Save group"
    assert_text "Group saved"
    assert_equal({ "content_types" => [ "blog" ] }, group.grants.find_by!(permission: "posts.edit").scope)
  end

  test "Edit scope announces itself, focus moves into the editor, and Escape brings it back to the button" do
    group = AccessControl::Group.create!(name: "Keyboard")
    group.grants.create!(permission: "posts.read", scope: {})

    visit edit_admin_group_path(group)
    await_admin_controllers
    row = "[data-permission='posts.read']"
    button = find("#{row} button[aria-controls][aria-expanded='false']")
    editor_id = button["aria-controls"]

    # Every state below is waited for, never read once: the controller sets the
    # attribute, shows the editor and moves the focus in separate steps.
    button.click
    assert_selector "#{row} button[aria-controls='#{editor_id}'][aria-expanded='true']"
    assert_selector "##{editor_id}"
    assert_selector "##{editor_id} :focus"

    find("##{editor_id} input[type=checkbox]", match: :first).send_keys(:escape)
    assert_no_selector "##{editor_id}"
    assert_selector "#{row} button[aria-controls='#{editor_id}'][aria-expanded='false']:focus"
  end

  test "with only a removed type left, the chips say all content types, then the warn chip (what Save will store)" do
    group = AccessControl::Group.create!(name: "Leftover")
    group.grants.create!(permission: "posts.edit", scope: { "content_types" => %w[blog retired_type] })

    visit edit_admin_group_path(group)
    await_admin_controllers
    row = "[data-permission='posts.edit']"
    within(row) { click_button "Edit scope" }
    within("#{row} [data-scope-editor]") { uncheck "Blog" }

    # Waited for (the chips are redrawn by script after the change), and in order.
    assert_selector "#{row} [data-chips] .admin-scope-chip", count: 2
    assert_selector "#{row} [data-chips] .admin-scope-chip:nth-of-type(1)", text: "All content types", exact_text: true
    assert_selector "#{row} [data-chips] .admin-scope-chip:nth-of-type(2)", text: "! retired_type · type removed", exact_text: true
  end

  # A grant that names only removed content types has no tick and no chip; saving
  # the form is what removes it, so Save is live with nothing touched -- and the
  # footer doesn't say "No unsaved changes" beside an enabled button.
  test "a group with a dormant dead grant: Save is enabled untouched, the footer shows no count, and saving removes the grant" do
    group = AccessControl::Group.create!(name: "Dormant")
    group.grants.create!(permission: "posts.edit", scope: { "content_types" => %w[blog] })
    group.grants.create!(permission: "posts.read", scope: { "content_types" => %w[retired_type] })

    visit edit_admin_group_path(group)
    await_admin_controllers
    assert_selector ".admin-stale-grant", text: "Limited to a content type that no longer exists (retired_type). Saving removes it;"
    assert_button "Save group", disabled: false
    assert_no_selector ".admin-save-bar", text: /unsaved/i

    click_button "Save group"

    assert_selector "#toasts", text: "Group saved"
    assert_no_selector ".admin-stale-grant"
    assert_selector ".admin-save-bar", text: /No unsaved changes/i
    assert_button "Save group", disabled: true
    assert_equal %w[posts.edit], group.grants.reload.map(&:permission)
  end

  test "a redundant stored root survives untouched, and the carried input steps aside when its ancestor is unticked" do
    group = AccessControl::Group.create!(name: "Redundant")
    group.grants.create!(permission: "pages.edit", scope: { "page_ids" => [ @about.id, @team.id ].sort })

    visit edit_admin_group_path(group)
    await_admin_controllers
    assert_selector ".admin-save-bar", text: /No unsaved changes/i
    row = "[data-permission='pages.edit']"
    carried = "#{row} input[type=hidden][name='group[grants][pages.edit][page_ids][]'][value='#{@team.id}']"
    assert_selector "#{carried}:enabled", visible: :all

    within(row) { click_button "Edit scope" }
    within("#{row} [data-scope-editor]") { uncheck "About" }
    assert_selector "#{carried}:disabled", visible: :all
    assert_selector "#grant-pages-edit-page-#{@team.id}:enabled:checked"
  end

  test "a Save on a form opened before another admin changed the group shows the banner, keeps the typed name, and Reload shows the other change" do
    group = AccessControl::Group.create!(name: "Shared", description: "before")
    # The banner names a change only when its event lies more than
    # `Audit::ChangeSince::SLACK` past the base the form loaded.
    backdate(group, by: 1.minute)
    visit "/cs-studio/groups/#{group.id}/edit"
    await_admin_controllers

    # Another admin saves the same group while this form is open.
    Current.set(actor: users(:two), channel: :admin) do
      assert Groups::Save.call(group, attributes: { description: "changed by the other admin" }).ok?
    end

    fill_in "Name", with: "My rename"
    click_button "Save group"

    assert_selector "[role=alert]", text: "This group was changed by two@example.com just now. Reload to see the latest — your changes are still in the form."
    assert_field "Name", with: "My rename"
    assert_equal "Shared", group.reload.name

    click_link "Reload"

    assert_field "Description", with: "changed by the other admin"
    assert_field "Name", with: "Shared"
    assert_no_selector "[role=alert]", text: "changed elsewhere"
  end
end
