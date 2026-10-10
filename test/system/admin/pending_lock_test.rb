require "application_system_test_case"

# `admin--saving--pending-lock` (design pass round 3, Task 1; decision D10): while an
# explicit-save form on the screen has unsaved changes, the instant actions
# beside it are disabled and a hint says why -- "Save or cancel your changes
# first." -- because an instant action re-renders the screen and would throw
# the pending changes away.
#
# Its first real hosts arrive with Settings, Groups and Users later in the
# round, so the wrapper is added to the edit-user screen here (ruling R2):
# a button, a link and the hint, next to the real `admin--saving--save-bar` form.
class Admin::PendingLockTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @owner = users(:one)
    @target = users(:two)
  end

  def add_lock(position = "beforebegin")
    page.execute_script(<<~JS, position)
      document.getElementById("user-form").insertAdjacentHTML(arguments[0], `
        <div id="lock" data-controller="admin--saving--pending-lock">
          <button type="button" id="lock-button" data-admin--saving--pending-lock-target="control">Test connection</button>
          <button type="button" id="lock-off" disabled data-admin--saving--pending-lock-target="control">Already off</button>
          <a id="lock-link" href="#{admin_groups_path}" data-turbo-frame="_top" data-admin--saving--pending-lock-target="control">Manage groups</a>
          <p id="lock-hint" hidden data-admin--saving--pending-lock-target="hint"></p>
        </div>`)
    JS
    await_admin_controllers
  end

  test "controls are disabled with a hint while changes are pending, and come back when they are reverted" do
    sign_in_via_form(@owner)
    visit edit_admin_user_path(@target)
    await_admin_controllers
    add_lock

    assert_selector "#lock-button:not([disabled])"
    assert_selector "#lock-link:not([aria-disabled])"
    assert_selector "#lock-hint", visible: :hidden

    original = find_field("Name").value
    fill_in "Name", with: "#{original} changed"
    assert_selector "#lock-button[disabled]"
    assert_selector "#lock-link[aria-disabled=true]"
    assert_selector "#lock-hint", text: "Save or cancel your changes first.", visible: :visible

    # A disabled link goes nowhere -- and doesn't ask to leave either.
    find("#lock-link").click
    assert_no_selector "dialog#leave-dialog[open]"
    assert_current_path edit_admin_user_path(@target)
    assert_equal "#{original} changed", find_field("Name").value

    fill_in "Name", with: original
    assert_selector "#lock-button:not([disabled])"
    assert_selector "#lock-link:not([aria-disabled])"
    assert_selector "#lock-hint", visible: :hidden
    # What was disabled for its own reasons stays disabled.
    assert_selector "#lock-off[disabled]"

    find("#lock-link").click
    assert_current_path admin_groups_path
  end

  # The lock may connect after the form has announced its state (a form
  # re-rendered with errors is unsaved from the start): it asks.
  test "a lock that appears while changes are already pending is locked at once" do
    sign_in_via_form(@owner)
    visit edit_admin_user_path(@target)
    await_admin_controllers
    fill_in "Name", with: "Already typed"
    assert_selector ".admin-save-bar", text: /1 unsaved change/i

    add_lock("afterend")
    assert_selector "#lock-button[disabled]"
    assert_selector "#lock-hint", text: "Save or cancel your changes first.", visible: :visible
  end

  # Disabling a field of the explicit-save form itself would take it out of
  # what the form submits -- which the footer counts as a change, so the lock
  # could never open again. Such a control is left alone; an unnamed button
  # inside that form (a dialog's trigger) submits nothing and is locked.
  test "a control that belongs to the explicit-save form is never locked" do
    sign_in_via_form(@owner)
    visit edit_admin_user_path(@target)
    await_admin_controllers
    page.execute_script(<<~JS)
      document.querySelector("#user-form .admin-save-bar").insertAdjacentHTML("beforebegin", `
        <div id="lock" data-controller="admin--saving--pending-lock">
          <input id="lock-field" name="user[note]" value="kept" data-admin--saving--pending-lock-target="control">
          <button type="button" id="lock-button" data-admin--saving--pending-lock-target="control">Instant</button>
          <p id="lock-hint" hidden data-admin--saving--pending-lock-target="hint"></p>
        </div>`)
      const form = document.getElementById("user-form")
      const parent = form.parentNode, next = form.nextSibling
      form.remove()
      parent.insertBefore(form, next)
    JS
    await_admin_controllers
    assert_selector ".admin-save-bar", text: /No unsaved changes/i

    original = find_field("Name").value
    fill_in "Name", with: "#{original} changed"
    assert_selector "#lock-button[disabled]"
    assert_selector "#lock-field:not([disabled])"
    assert_selector ".admin-save-bar", text: /1 unsaved change\b/i

    fill_in "Name", with: original
    assert_selector ".admin-save-bar", text: /No unsaved changes/i
    assert_selector "#lock-button:not([disabled])"
    assert_selector "#lock-hint", visible: :hidden
  end
end
