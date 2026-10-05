require "test_helper"

class Admin::AuditScreen::RowComponentTest < ViewComponent::TestCase
  def row_for(action, **attributes)
    at = Time.zone.local(2026, 10, 2, 16, 5)
    event = Audit::Event.create!({ action:, channel: "admin", user_id: users(:one).id, subject_label: "Hello", occurred_at: at, last_occurred_at: at }.merge(attributes))
    render_inline Admin::AuditScreen::RowComponent.new(event:, sentence: Audit::Sentence.build(event, viewer: users(:two), target: nil), event_path: "/e/1")
    event
  end

  test "time, avatar, sentence, raw key and channel chip; the time opens the event" do
    row_for("post.published")

    assert_selector "a[href='/e/1']", text: "16:05"
    assert_selector "span.rounded-full", text: users(:one).display_name[0].upcase
    assert_selector "p", text: "#{users(:one).display_name} published “Hello”"
    assert_selector "span.font-cs-mono.text-meta", text: "post.published"
    assert_selector ".admin-channel-chip[data-channel=admin]", text: "ADMIN"
  end

  test "the row's link is named by more than the time, and described by the sentence" do
    row_for("post.published")

    link = page.find("li a[href='/e/1']")
    assert_equal "16:05, details of this change", link["aria-label"]
    assert_selector "p##{link['aria-describedby']}", text: "published “Hello”"
  end

  test "a coalesced span reads both ends" do
    row_for("post.updated", last_occurred_at: Time.zone.local(2026, 10, 2, 16, 31))

    assert_selector "a", text: "16:05–16:31"
  end

  test "a security key is in warn ink, and a failed sign-in has a dash for an avatar and no name" do
    row_for("session.failed", user_id: nil)

    assert_selector "span.text-warn-ink", text: "session.failed"
    assert_selector "span.rounded-full", text: "–"
    assert_selector "p", text: "Failed sign-in attempt"
  end

  test "an MCP change shows the MCP chip" do
    row_for("post.created", channel: "mcp", actor_type: "ApiToken", actor_id: 1, actor_label: "claude-desktop")

    assert_selector ".admin-channel-chip[data-channel=mcp]", text: "MCP"
    assert_selector "p", text: /via claude-desktop/
  end
end
