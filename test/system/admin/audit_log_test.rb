require "application_system_test_case"

# The audit log in a real browser (design pass round 3, Task 15): filters
# apply on choosing, Custom reveals From and To, a row opens its event page,
# and Older/Newer walk the filtered list.
class Admin::AuditLogSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @recent = Audit::Event.create!(action: "test.recent", channel: "admin", user_id: users(:one).id, subject_label: "Recent thing",
      occurred_at: 1.hour.ago, last_occurred_at: 1.hour.ago)
    @old = Audit::Event.create!(action: "test.old", channel: "mcp", user_id: users(:one).id, subject_label: "Old thing",
      occurred_at: 40.days.ago, last_occurred_at: 40.days.ago)
    sign_in_via_form(users(:one))
  end

  test "choosing a date preset or a channel applies at once; Custom reveals the two dates" do
    visit admin_audit_events_path
    await_admin_controllers
    assert_selector "#audit_event_#{@recent.id}"
    assert_selector "#audit_event_#{@old.id}"

    select "Last 30 days", from: "Date"
    assert_no_selector "#audit_event_#{@old.id}", wait: 5
    assert_selector "#audit_event_#{@recent.id}"

    select "Custom…", from: "Date"
    assert_selector "input#from", wait: 5
    assert_selector "input#to"

    select "Any time", from: "Date"
    # The answer re-renders the toolbar: wait for it, or the next choice is
    # made on a select that is about to be replaced (and is lost with it).
    assert_selector "#audit_event_#{@old.id}", wait: 5
    select "MCP", from: "Channel"
    assert_no_selector "#audit_event_#{@recent.id}", wait: 5
    assert_selector "#audit_event_#{@old.id}"
    assert_no_selector "input#from"
  end

  test "a row opens its event page, and Older goes to the next event in the list" do
    visit admin_audit_events_path
    await_admin_controllers

    find("#audit_event_#{@recent.id} a.font-cs-mono").click
    assert_selector "h1", text: "test.recent"
    assert_text "Older event"
    click_link "Older event"
    assert_selector "dd", text: "test.old"
    assert_no_link "Older event"
    click_link "Newer event"
    assert_selector "dd", text: "test.recent"
  end
end
