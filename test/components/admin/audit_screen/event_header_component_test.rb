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

    assert_selector "span.text-label > a[href='/cs-studio/audit_events?channel=admin']", text: "Audit log"
    assert_selector "h1", text: "You edited “Welcome”"
    assert_selector "dd", text: "Fri 2 Oct 2026, 16:05–16:31 · 12 saves"
    assert_selector "dd", text: users(:one).name_or_email
    assert_selector "dd", text: "post.updated"
    assert_selector "dd", text: "Post #5 · Welcome"
    assert_selector "dd", text: "7c1e"
    assert_selector "dd", text: "203.0.113.9"
    assert_selector "dl .admin-channel-chip", text: "Admin"
  end

  test "blank values read a dash" do
    header(action: "access.denied", request_id: nil, ip: nil, subject_type: nil, subject_id: nil, subject_label: nil, occurrences: 1,
      last_occurred_at: Time.zone.local(2026, 10, 2, 16, 5))

    assert_selector "dd", text: "—", minimum: 3
    assert_selector "dd", text: "Fri 2 Oct 2026, 16:05"
    assert_no_text "saves"
  end

  test "the facts are one card divided inside, and a security action carries the Security chip" do
    header(action: "access.denied")

    assert_selector ".rounded-card", count: 1
    card = page.find(".rounded-card")
    %w[overflow-hidden bg-surface shadow-1].each { |name| assert_includes card[:class].split, name }
    facts = card.find("dl[data-audit-facts]")
    %w[grid -mr-px -mb-px].each { |name| assert_includes facts[:class].split, name }
    cells = facts.all(:xpath, "./div")
    assert_equal %w[When Who Action Object Request IP Channel], cells.map { |cell| cell.find("dt").text }
    cells.each do |cell|
      %w[border-b border-r border-line].each { |name| assert_includes cell[:class].split, name }
      %w[border border-t border-l rounded-cs].each { |name| assert_not_includes cell[:class].split, name }
    end

    action = facts.find("dt", text: "Action").find(:xpath, "following-sibling::dd")
    chip = action.find(".admin-state-chip")
    assert_equal "Security", chip.text.strip
    assert_includes chip[:class].split, "text-warn-ink"
    assert_selector "dd .admin-state-chip + span.font-cs-mono", text: "access.denied"
    assert_no_selector "dd.font-cs-mono, .admin-state-chip.font-cs-mono"
    assert_no_selector ".text-warn-ink", text: "access.denied"

    header
    assert_no_selector ".admin-state-chip"
    assert_selector "dd span.font-cs-mono", text: "post.updated"
  end

  test "a failed sign-in has no who" do
    header(action: "session.failed", user_id: nil, subject_type: nil, subject_label: nil)

    assert_selector "dt", text: "Who"
    assert_selector "h1", text: "Failed sign-in attempt"
  end
end
