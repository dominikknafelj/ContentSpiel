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
      check "About"

      # Team sits under About: included, so a greyed tick that is not submitted.
      team = find_field("Team", disabled: true)
      assert team.checked?
      assert_text "included"
      assert_text "includes 1 subpage"
    end
    # The ancestors of the chosen page are partial: indeterminate, unchecked.
    home_box = page.evaluate_script("Array.from(document.querySelectorAll(\"#{row} .admin-branch-picker input[type=checkbox]\")).filter((box) => box.indeterminate).length")
    assert_operator home_box, :>=, 1

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
    button = find("#{row} button[aria-controls]")
    assert_equal "false", button["aria-expanded"]
    editor_id = button["aria-controls"]

    button.click
    assert_equal "true", find("#{row} button[aria-controls]")["aria-expanded"]
    assert_equal editor_id, find("##{editor_id}")["id"]
    assert page.evaluate_script("document.getElementById('#{editor_id}').contains(document.activeElement)")

    find("##{editor_id} input[type=checkbox]", match: :first).send_keys(:escape)
    assert_no_selector "##{editor_id}"
    assert_equal "false", find("#{row} button[aria-controls]")["aria-expanded"]
    assert page.evaluate_script("document.activeElement === document.querySelector(\"#{row} button[aria-controls]\")")
  end

  test "with only a removed type left, the chips say all content types, then the warn chip (what Save will store)" do
    group = AccessControl::Group.create!(name: "Leftover")
    group.grants.create!(permission: "posts.edit", scope: { "content_types" => %w[blog retired_type] })

    visit edit_admin_group_path(group)
    await_admin_controllers
    row = "[data-permission='posts.edit']"
    within(row) { click_button "Edit scope" }
    within("#{row} [data-scope-editor]") { uncheck "Blog" }

    chips = page.all("#{row} [data-chips] .admin-scope-chip").map(&:text)
    assert_equal [ "All content types", "! retired_type · type removed" ], chips
  end

  test "a redundant stored root survives untouched, and the carried input steps aside when its ancestor is unticked" do
    group = AccessControl::Group.create!(name: "Redundant")
    group.grants.create!(permission: "pages.edit", scope: { "page_ids" => [ @about.id, @team.id ].sort })

    visit edit_admin_group_path(group)
    await_admin_controllers
    assert_selector ".admin-save-bar", text: /No unsaved changes/i
    row = "[data-permission='pages.edit']"
    carried = "#{row} input[type=hidden][name='group[grants][pages.edit][page_ids][]'][value='#{@team.id}']"
    assert_selector carried, visible: :all
    assert_not find(carried, visible: :all).disabled?

    within(row) { click_button "Edit scope" }
    within("#{row} [data-scope-editor]") { uncheck "About" }
    assert find(carried, visible: :all).disabled?
    within("#{row} [data-scope-editor]") { assert_not find_field("Team").disabled? }
  end
end
