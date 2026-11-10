require "application_system_test_case"

# The Users list and the user editor in a real browser: a row opens
# the editor, a ticked group card is one unsaved change, Make owner… confirms and
# the list shows the Owner tag, the owner and delete buttons wait for unsaved
# changes, the password disclosure counts nothing until something is typed and
# forgets what was typed when closed, and a read-only reason takes no Tab stop.
class Admin::UsersSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @target = users(:reader)
    sign_in_via_form(users(:one))
  end

  def row(user) = "##{ActionView::RecordIdentifier.dom_id(user)}"

  test "a row opens the editor; ticking a group card is one unsaved change; Save user saves it" do
    visit_screen admin_users_path
    within(row(@target)) { click_link @target.email_address }
    assert_current_path edit_admin_user_path(@target)
    assert_selector "h1", text: @target.email_address
    assert_selector ".admin-save-bar", text: /No unsaved changes/i
    assert_selector ".admin-save-bar button[type=submit][disabled]", text: "Save user"

    editor = access_control_groups(:editor)
    find("label[data-group-card='#{editor.id}']").click
    assert_selector ".admin-save-bar", text: /1 unsaved change/i
    assert_selector "label[data-group-card='#{editor.id}'] input:checked"
    assert_selector ".admin-save-bar button[type=submit]:not([disabled])", text: "Save user"

    press "Save user"
    assert_current_path edit_admin_user_path(@target)
    assert_text "User saved"
    assert_selector ".admin-save-bar", text: /No unsaved changes/i
    assert_equal [ access_control_groups(:read_only).id, editor.id ].sort, @target.reload.group_ids.sort
    visit admin_users_path
    within(row(@target)) { assert_text "Editor" }
  end

  test "Make owner… confirms and the list shows the Owner tag" do
    visit_screen edit_admin_user_path(@target)

    click_button "Make owner…"
    within("dialog#owner-user-#{@target.id}") do
      assert_text "Make reader@example.com an owner?"
      press "Make owner"
    end

    assert_current_path edit_admin_user_path(@target)
    assert_text "reader@example.com is now an owner"
    assert_selector "[data-zone=owner] button", text: "Remove owner rights…"
    assert @target.reload.owner?

    visit admin_users_path
    within(row(@target)) { assert_text "Owner" }
  end

  test "with a typed change the owner and delete buttons are disabled with the hint, and come back when it is undone" do
    visit_screen edit_admin_user_path(@target)

    assert_selector "[data-zone=owner] button:not([disabled])", text: "Make owner…"
    assert_selector "[data-zone=delete] button:not([disabled])", text: "Delete user…"

    fill_in "Name", with: "Typed"
    assert_selector "[data-zone=owner] button[disabled]", text: "Make owner…"
    assert_selector "[data-zone=delete] button[disabled]", text: "Delete user…"
    assert_selector "[data-zone=owner] [data-admin--saving--pending-lock-target=hint]", text: "Save or discard your changes first.", visible: :visible
    assert_selector "[data-zone=delete] [data-admin--saving--pending-lock-target=hint]", text: "Save or discard your changes first.", visible: :visible

    fill_in "Name", with: ""
    assert_selector "[data-zone=owner] button:not([disabled])", text: "Make owner…"
    assert_selector "[data-zone=delete] button:not([disabled])", text: "Delete user…"
  end

  test "Set a new password… counts nothing until something is typed, and closing it forgets what was typed" do
    visit_screen edit_admin_user_path(@target)
    assert_no_selector "#user_password", visible: :visible

    find("summary", text: "Set a new password…").click
    assert_selector "#user_password", visible: :visible
    assert_selector ".admin-save-bar", text: /No unsaved changes/i

    fill_in "New password", with: "a half-typed password"
    assert_selector ".admin-save-bar", text: /1 unsaved change/i
    assert_selector ".admin-save-bar button[type=submit]:not([disabled])"

    find("summary", text: "Set a new password…").click
    assert_no_selector "#user_password", visible: :visible
    assert_selector ".admin-save-bar", text: /No unsaved changes/i
    assert_selector ".admin-save-bar button[type=submit][disabled]"
    find("summary", text: "Set a new password…").click
    assert_equal "", find_field("New password").value
  end

  # The read-only reason is a note (`Admin::Ui::NoticeComponent`): read where
  # it stands and never a Tab stop, so the keyboard goes from the breadcrumb
  # to Activity and on through the page without landing in it.
  test "a user the viewer can't change says why in a note, and the keyboard passes over it from the breadcrumb to Activity" do
    managers = AccessControl::Group.create!(name: "User managers")
    %w[users.manage audit.view posts.read pages.read].each { |key| AccessControl::Grant.create!(group: managers, permission: key, scope: {}) }
    AccessControl::Membership.create!(user: users(:editor_branch), group: managers)
    Capybara.reset_sessions!
    sign_in_via_form(users(:editor_branch))

    visit_screen edit_admin_user_path(users(:one))
    assert_selector "[role=note]", text: "Only owners can change other owners."

    page.execute_script("document.querySelector(\"main a[href='#{admin_users_path}']\").focus()")
    page.driver.browser.keyboard.type(:tab)
    assert_equal "Activity", page.evaluate_script("document.activeElement.textContent.trim()")
    stops = Array.new(12) do
      page.driver.browser.keyboard.type(:tab)
      page.evaluate_script("document.activeElement.closest('[role=note]') ? 'note' : 'outside'")
    end
    assert_not_includes stops, "note"
  end

  test "Delete user… asks, then removes the user and lands on the list" do
    visit_screen edit_admin_user_path(@target)

    click_button "Delete user…"
    within("dialog#delete-user-#{@target.id}") do
      assert_text "Delete reader@example.com?"
      press "Delete user"
    end

    assert_current_path admin_users_path
    assert_text "User deleted"
    assert_not User.exists?(@target.id)
  end
end
