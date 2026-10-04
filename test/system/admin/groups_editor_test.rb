require "application_system_test_case"

# The group editor's scope controls (access-control design spec §5 "Groups
# module"): ticking a scoped permission reveals its scope controls, and the
# page-branch picker (`admin--branch-picker`) stores branch *roots* -- a
# page under a ticked page is implied by it, shown ticked and disabled, and
# never submitted on its own.
class Admin::GroupsEditorSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @about = create_page(title: "About")
    @team = create_page(title: "Team", parent: @about)
    sign_in_via_form(users(:one))
  end

  test "tick pages.edit, pick a branch, save: the grant's page_ids is saved" do
    visit "/cs-studio/groups/new"
    await_admin_controllers

    fill_in "Name", with: "About editors"

    scope = find("[data-permission='pages.edit'] [data-admin--permission-matrix-target='scope']", visible: :all)
    assert_not scope.visible?
    check "Edit pages"
    assert scope.visible?

    within "[data-permission='pages.edit']" do
      find("summary", text: "Branches").click
      check "Team"
      check "About"

      # Team sits under About: implied, so disabled and not submitted.
      team = find_field("Team", disabled: true)
      assert team.checked?
      assert_text "1 branch"
    end

    press "Save"
    assert_text "Group saved"

    group = AccessControl::Group.find_by!(name: "About editors")
    assert_equal({ "page_ids" => [ @about.id ] }, group.grants.find_by!(permission: "pages.edit").scope)
  end
end
