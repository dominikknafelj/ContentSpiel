require "test_helper"

class Admin::AuditScreen::EventHeaderComponentTest < ViewComponent::TestCase
  def header(**attributes)
    event = Audit::Event.create!({ action: "post.updated", channel: "admin", user_id: users(:one).id, subject_type: "Post", subject_id: 5, subject_label: "Welcome",
      occurred_at: Time.zone.local(2026, 10, 2, 16, 5), last_occurred_at: Time.zone.local(2026, 10, 2, 16, 31), occurrences: 12,
      request_id: "7c1e", ip: "203.0.113.9" }.merge(attributes))
    sentence = Audit::Sentence.build(event, viewer: users(:one), target: Audit::Sentence::Target.new("Welcome", Audit::Sentence::Route.new(:admin_post_path, [ 5 ], {})))
    render_inline Admin::AuditScreen::EventHeaderComponent.new(event:, sentence:, back_path: "/cs-studio/audit_events?channel=admin")
  end

  test "breadcrumb, sentence title and the meta grid" do
    header

    assert_selector "a[href='/cs-studio/audit_events?channel=admin']", text: "Audit log"
    assert_selector "h1", text: "You edited “Welcome”"
    assert_selector "dd", text: "Fri 2 Oct 2026, 16:05–16:31 · 12 saves"
    assert_selector "dd", text: users(:one).display_name
    assert_selector "dd", text: "post.updated"
    assert_selector "dd", text: "Post #5 · Welcome"
    assert_selector "dd", text: "7c1e"
    assert_selector "dd", text: "203.0.113.9"
    assert_selector "dl .admin-channel-chip", text: "ADMIN"
  end

  test "blank values read a dash, and a security key is in warn ink" do
    header(action: "access.denied", request_id: nil, ip: nil, subject_type: nil, subject_id: nil, subject_label: nil, occurrences: 1,
      last_occurred_at: Time.zone.local(2026, 10, 2, 16, 5))

    assert_selector "dd", text: "—", minimum: 3
    assert_selector "dd.text-warn-ink", text: "access.denied"
    assert_selector "dd", text: "Fri 2 Oct 2026, 16:05"
    assert_no_text "saves"
  end

  test "a failed sign-in has no who" do
    header(action: "session.failed", user_id: nil, subject_type: nil, subject_label: nil)

    assert_selector "dt", text: "Who"
    assert_selector "h1", text: "Failed sign-in attempt"
  end
end
