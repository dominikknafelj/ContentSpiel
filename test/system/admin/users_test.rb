require "application_system_test_case"

# The Users list and the user editor in a real browser (round 3 Task 12): a row opens
# the editor, a ticked group card is one unsaved change, Make owner… confirms and
# the list shows the OWNER tag, the owner and delete buttons wait for unsaved
# changes, and the password disclosure counts nothing until something is typed and
# forgets what was typed when closed.
class Admin::UsersSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @target = users(:reader)
    sign_in_via_form(users(:one))
  end

  def row(user) = "##{ActionView::RecordIdentifier.dom_id(user)}"

  test "a row opens the editor; ticking a group card is one unsaved change; Save user saves it" do
    visit admin_users_path
    await_admin_controllers
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

  test "Make owner… confirms and the list shows the OWNER tag" do
    visit edit_admin_user_path(@target)
    await_admin_controllers

    click_button "Make owner…"
    within("dialog#owner-user-#{@target.id}") do
      assert_text "Make reader@example.com an owner?"
      press "Make owner"
    end

    assert_current_path edit_admin_user_path(@target)
    assert_text "reader@example.com is now an owner"
    assert_selector ".admin-owner-zone button", text: "Remove owner rights…"
    assert @target.reload.owner?

    visit admin_users_path
    within(row(@target)) { assert_text "OWNER" }
  end

  test "with a typed change the owner and delete buttons are disabled with the hint, and come back when it is undone" do
    visit edit_admin_user_path(@target)
    await_admin_controllers

    assert_selector ".admin-owner-zone button:not([disabled])", text: "Make owner…"
    assert_selector ".admin-delete-zone button:not([disabled])", text: "Delete user…"

    fill_in "Name", with: "Typed"
    assert_selector ".admin-owner-zone button[disabled]", text: "Make owner…"
    assert_selector ".admin-delete-zone button[disabled]", text: "Delete user…"
    assert_selector ".admin-owner-zone [data-admin--saving--pending-lock-target=hint]", text: "Save or cancel your changes first.", visible: :visible
    assert_selector ".admin-delete-zone [data-admin--saving--pending-lock-target=hint]", text: "Save or cancel your changes first.", visible: :visible

    fill_in "Name", with: ""
    assert_selector ".admin-owner-zone button:not([disabled])", text: "Make owner…"
    assert_selector ".admin-delete-zone button:not([disabled])", text: "Delete user…"
  end

  test "Set a new password… counts nothing until something is typed, and closing it forgets what was typed" do
    visit edit_admin_user_path(@target)
    await_admin_controllers
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

  test "Delete user… asks, then removes the user and lands on the list" do
    visit edit_admin_user_path(@target)
    await_admin_controllers

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
