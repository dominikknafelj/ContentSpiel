require "test_helper"

# A box of the caller's words in one of four tones. Its role follows the
# tone, so a screen reader hears a warning or a refusal at once, a success
# politely and an explanation only when it reads there; inside a live region
# the region speaks, and the notice says nothing of its own.
class Admin::Ui::NoticeComponentTest < ViewComponent::TestCase
  def notice_classes = page.find("div[data-notice]")["class"].split

  test "each tone draws its ground, its words and its role: warn and danger an alert, ok a status, neutral a note" do
    { warn: [ "bg-warn-tint", "text-warn-ink", "alert" ], ok: [ "bg-ok-tint", "text-ok-ink", "status" ],
      danger: [ "bg-danger-tint", "text-danger-ink", "alert" ], neutral: [ "bg-sunken", "text-dim", "note" ] }.each do |tone, (ground, ink, role)|
      render_inline(Admin::Ui::NoticeComponent.new(tone: tone, data: { notice: true })) { "Something to say." }

      assert_selector "div[data-notice][role=#{role}]", exact_text: "Something to say.", count: 1
      assert_includes notice_classes, ground, tone
      assert_includes notice_classes, ink, tone
    end
  end

  test "warn and danger have an edge in their own colour, ok and neutral none, every tone is rounded-card, and compact is 13px" do
    edges = { warn: "border-warn", danger: "border-danger", ok: nil, neutral: nil }
    edges.each do |tone, edge|
      render_inline(Admin::Ui::NoticeComponent.new(tone: tone, data: { notice: true })) { "Words." }

      assert_includes notice_classes, "rounded-card", tone
      assert_equal edge.present?, notice_classes.include?("border"), tone
      assert_equal [ edge ].compact, notice_classes.grep(/\Aborder-/), tone
      %w[px-3 py-2 text-sm].each { |utility| assert_includes notice_classes, utility, tone }
    end

    render_inline(Admin::Ui::NoticeComponent.new(tone: :ok, size: :compact, data: { notice: true })) { "Words." }
    %w[px-3 py-2.5 text-small leading-normal].each { |utility| assert_includes notice_classes, utility }
    assert_not_includes notice_classes, "text-sm"
  end

  test "the danger notice's edge is the error summary's, so a refusal looks the same in a notice and above a form" do
    render_inline(Admin::Ui::NoticeComponent.new(tone: :danger, data: { notice: true })) { "Refused." }
    summary = Rails.root.join("app/components/admin/ui/error_summary_component.html.erb").read[/class="admin-error-summary ([^"]*)"/, 1].split

    assert_empty notice_classes - %w[px-3 py-2 text-sm] - summary, "every look class of the danger notice is the summary's"
    assert_includes summary, "border-danger"
  end

  test "role: nil writes no role, and an unknown tone or size is refused" do
    render_inline(Admin::Ui::NoticeComponent.new(tone: :warn, role: nil, data: { notice: true })) { "Inside a live region." }
    assert_selector "div[data-notice]:not([role])", text: "Inside a live region."

    assert_raises(ArgumentError) { Admin::Ui::NoticeComponent.new(tone: :loud) }
    assert_raises(ArgumentError) { Admin::Ui::NoticeComponent.new(tone: :warn, size: :huge) }
  end

  test "a caller's class is added to the notice's own and its id and data reach the box" do
    render_inline(Admin::Ui::NoticeComponent.new(tone: :neutral, id: "why-not", class: "mt-4", data: { notice: true, reason: "owner" })) { "Only the owner can change this." }

    assert_selector "div#why-not[data-notice][data-reason=owner]", text: "Only the owner can change this."
    %w[mt-4 rounded-card bg-sunken text-dim].each { |utility| assert_includes notice_classes, utility }
  end

  test "a notice with no words draws nothing" do
    render_inline(Admin::Ui::NoticeComponent.new(tone: :warn))
    assert_equal "", rendered_content.strip

    render_inline(Admin::Ui::NoticeComponent.new(tone: :warn)) { "  " }
    assert_equal "", rendered_content.strip
  end

  # A notice inside a region that speaks for it says nothing of its own, so
  # it is heard once; the stale banner is a notice of its own role, and its
  # Reload stays the leave guard's way out into the content frame.
  test "a notice inside a live region adds no role of its own, and the stale banner keeps its Reload way out" do
    render_inline(Admin::SettingsScreen::MailTestOutcomeComponent.new(address: "ada@example.com", sent: true))
    assert_selector "div[role=status] > div.rounded-card.bg-ok-tint.text-ok-ink:not([role])", text: "Test mail sent to ada@example.com. Check your inbox.", count: 1

    render_in_view_context do
      render "admin/shared/stale_banner", words: "admin.settings.show.stale", change: nil, reload_path: "/cs-studio/settings"
    end
    assert_selector "div[role=alert].rounded-card.border-warn.bg-warn-tint.text-warn-ink", text: "Settings were changed elsewhere since you opened this screen.", count: 1
    assert_selector "div[role=alert] a[href='/cs-studio/settings'][data-save-bar-cancel][data-turbo-frame=content]", text: "Reload"
  end

  test "its classes are the box's own for a script-filled box that must stand empty" do
    assert_equal "rounded-card border border-warn bg-warn-tint text-warn-ink px-3 py-2 text-sm", Admin::Ui::NoticeComponent.classes(:warn)
    assert_equal "rounded-card bg-ok-tint text-ok-ink px-3 py-2.5 text-small leading-normal", Admin::Ui::NoticeComponent.classes(:ok, size: :compact)
    assert_raises(ArgumentError) { Admin::Ui::NoticeComponent.classes(:loud) }
  end
end
