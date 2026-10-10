require "test_helper"

class Admin::AuditScreen::ToolbarComponentTest < ViewComponent::TestCase
  def toolbar(params = nil, other_actions: [], users: User.order(:id).limit(3).to_a, **keywords)
    filter = Audit::Filter.new(ActiveSupport::HashWithIndifferentAccess.new(params || keywords))
    render_inline Admin::AuditScreen::ToolbarComponent.new(filter:, users:, other_actions:)
  end

  test "one row of drop-downs, applied on change, with the date presets" do
    toolbar

    assert_selector "form[data-controller='admin--ui--auto-submit']"
    %w[user_id event_action subject_type channel range].each { |id| assert_selector "select##{id}" }
    assert_selector "select#range option", count: 6 # Any time + five
    assert_selector "select#channel option", text: "Other"
    assert_no_selector "input[type=date]"
    assert_no_link "Clear"
  end

  test "Custom shows From and To; the chosen filters are selected and Clear appears" do
    toolbar(range: "custom", from: "2026-06-01", to: "2026-06-30", channel: "mcp", event_action: "post.published")

    assert_selector "select#range option[selected]", text: "Custom…"
    assert_selector "input#from[value='2026-06-01']"
    assert_selector "input#to[value='2026-06-30']"
    assert_selector "select#channel option[selected]", text: "MCP"
    assert_selector "select#event_action option[selected]", text: "post.published"
    assert_link "Clear"
  end

  test "actions are grouped by what they are about, with an Other group for the unknown" do
    toolbar({ event_action: "acme/x.y" }, other_actions: [ "acme/x.z" ])

    assert_selector "optgroup[label=Pages] option", text: "page.published"
    assert_selector "optgroup[label=Sign-in] option", text: "session.failed"
    assert_selector "optgroup[label=Other] option", text: "acme/x.y"
    assert_selector "optgroup[label=Other] option", text: "acme/x.z"
  end

  test "a subject filter is a removable chip with hidden values, not a Type drop-down" do
    toolbar(subject_type: "Page", subject_id: "9", channel: "admin")

    assert_selector "[data-subject-chip]", text: "About this page #9"
    assert_selector "input[type=hidden][name=subject_type][value=Page]", visible: :all
    assert_selector "input[type=hidden][name=subject_id][value='9']", visible: :all
    assert_no_selector "select#subject_type"
    assert_selector "[data-subject-chip] a[href*='channel=admin']"
  end
end
