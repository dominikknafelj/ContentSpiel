require "test_helper"

class Admin::AuditScreen::RowComponentTest < ViewComponent::TestCase
  # The shared avatar at its 28px size (`Admin::Ui::AvatarComponent`).
  AVATAR = "span.rounded-full.uppercase.size-7.text-count[aria-hidden=true]".freeze

  def row_for(action, viewer: users(:two), **attributes)
    at = Time.zone.local(2026, 10, 2, 16, 5)
    event = Audit::Event.create!({ action:, channel: "admin", user_id: users(:one).id, subject_label: "Hello", occurred_at: at, last_occurred_at: at }.merge(attributes))
    render_inline Admin::AuditScreen::RowComponent.new(event:, sentence: Audit::Sentence.build(event, viewer:, target: nil), event_path: "/e/1")
    event
  end

  test "time, avatar, sentence, raw key and channel chip; the time opens the event" do
    row_for("post.published")

    assert_selector "a[href='/e/1']", text: "16:05"
    assert_selector AVATAR, exact_text: PersonName.initials(PersonName.of(users(:one)))
    assert_selector "p", text: "#{users(:one).display_name} published “Hello”"
    assert_selector "span.font-cs-mono.text-meta", text: "post.published"
    assert_selector ".admin-channel-chip[data-channel=admin]", text: "Admin"
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

  test "a security key is in warn ink, and a failed sign-in has no circle and no name" do
    row_for("session.failed", user_id: nil)

    assert_selector "span.text-warn-ink", text: "session.failed"
    assert_selector "li > span.size-7.shrink-0[aria-hidden=true]:empty"
    assert_no_selector ".rounded-full, .rounded-chip"
    assert_selector "p", text: "Failed sign-in attempt"
  end

  test "a person is the shared avatar with two letters; the viewer's own is filled; the system is the neutral icon chip; an event nobody made draws no circle" do
    users(:one).update!(name: "Ada Lovelace")
    row_for("post.published")
    assert_selector "#{AVATAR}.border-line-strong.bg-sunken.text-ink", exact_text: "AL"

    row_for("post.published", viewer: users(:one))
    assert_selector "#{AVATAR}.bg-ink.text-paper", exact_text: "AL"

    row_for("post.published", user_id: nil)
    assert_selector "li > span.size-7[aria-hidden=true] > span.rounded-chip.size-6.bg-sunken.text-dim svg"
    assert_no_selector ".rounded-full"
    assert_selector "p", text: "System published"

    row_for("post.published", user_id: 999_999)
    assert_selector "#{AVATAR}.border-line.bg-paper.text-meta", exact_text: ""
    assert_selector "p", text: "a deleted user published"

    row_for("session.failed", user_id: nil)
    assert_selector "li > span.size-7.shrink-0[aria-hidden=true]:empty"
    assert_no_selector ".rounded-full, .rounded-chip"
  end

  # The audit log and the dashboard draw the actor through one component, so
  # one person has one pair of letters in both, a name of one word or none.
  test "the same user's circle is the same in the audit log and on the dashboard" do
    [ "Ada Lovelace", nil ].each_with_index do |name, index|
      users(:one).update!(name:, email_address: "a@example.com")
      post = Current.set(actor: users(:one), channel: :admin) { create_post(title: "Same #{index}", published: false) }
      dashboard = Dashboard::Activity.new(actor: users(:two), channel: :admin).rows.find { |row| row.record == post }
      render_inline Admin::DashboardScreen::ActivityRowComponent.new(row: dashboard)
      on_dashboard = page.find(AVATAR)

      event = Audit::Event.find_by!(subject: post)
      render_inline Admin::AuditScreen::RowComponent.new(event:, sentence: Audit::Sentence.build(event, viewer: users(:two), target: nil), event_path: "/e/1")
      in_the_log = page.find(AVATAR)

      assert_equal on_dashboard[:class], in_the_log[:class]
      assert_equal on_dashboard.text, in_the_log.text
      assert_equal name ? "AL" : "a", in_the_log.text
    end
  ensure
    Current.reset
  end

  test "an MCP change shows the MCP chip" do
    row_for("post.created", channel: "mcp", actor_type: "ApiToken", actor_id: 1, actor_label: "claude-desktop")

    assert_selector ".admin-channel-chip[data-channel=mcp]", text: "MCP"
    assert_selector "p", text: /via claude-desktop/
  end
end
