require "test_helper"

# An instant action after a form: a section named by its heading, set off by
# a line rule above and no box, holding the cost in words and the caller's
# one trigger. With pending_lock the zone waits for the form above it.
class Admin::Ui::ActionZoneComponentTest < ViewComponent::TestCase
  def zone(**options)
    render_inline(Admin::Ui::ActionZoneComponent.new(heading_id: "zone-title", heading: "Delete this group", body: "3 members lose its permissions.", data: { zone: "delete" }, **options)) do |zone|
      zone.with_trigger { "<button type=\"button\">Delete group…</button>".html_safe }
    end
  end

  test "a section named by its heading, over a line rule, with no box of its own" do
    zone

    section = page.find("section[aria-labelledby=zone-title][data-zone=delete]")
    classes = section[:class].split
    %w[admin-action-zone flex flex-wrap items-center justify-between gap-3 border-t border-line pt-4].each { |utility| assert_includes classes, utility }
    assert_empty classes.grep(/\A-?m[tyb]?-/), "the space above the zone is the caller's"
    assert_empty classes & %w[border border-dashed rounded-cs rounded-card shadow-1 bg-surface bg-sunken], "the zone is a rule above its words, not a box"
    assert_selector "section h2#zone-title.text-h3.text-ink", text: "Delete this group"
    assert_selector "section p.text-small.text-dim", text: "3 members lose its permissions."
    assert_selector "section > button", text: "Delete group…"
    assert_no_selector "[data-action-zone-reason]"
    assert_no_selector "[data-controller]"
    assert_no_selector "[data-admin--saving--pending-lock-target=hint]", visible: :all
  end

  test "pending_lock wires the hint and the controller, and a reason is drawn when given" do
    zone(reason: "Mara is the only owner, so they can't be deleted.", pending_lock: true)

    assert_selector "section[data-zone=delete][data-controller='admin--saving--pending-lock']"
    assert_selector "section p[data-action-zone-reason].text-small.text-dim", text: "Mara is the only owner, so they can't be deleted."
    assert_selector "section p[data-admin--saving--pending-lock-target=hint][hidden]", visible: :all
  end

  test "a caller's class is added to the zone's own" do
    render_inline(Admin::Ui::ActionZoneComponent.new(heading_id: "z", heading: "H", body: "B", class: "mt-6 max-w-[1000px]"))
    assert_includes page.find("section")[:class].split, "max-w-[1000px]"
    assert_includes page.find("section")[:class].split, "mt-6"
    assert_includes page.find("section")[:class].split, "border-t"
  end

  # The media panel's zone: a narrow column with no heading, so the section
  # is named by the trigger's words, the cost line stands first and the
  # trigger wraps under it at the start.
  test "with no heading the section is named by its label, the cost line comes first and the trigger stands under it at the start" do
    render_inline(Admin::Ui::ActionZoneComponent.new(label: "Move to trash", body: "Kept in the trash for 30 days.", body_id: "zone-help")) do |zone|
      zone.with_trigger { "<button type=\"button\" aria-describedby=\"zone-help\">Move to trash…</button>".html_safe }
    end

    section = page.find("section[aria-label='Move to trash']")
    assert_nil section[:"aria-labelledby"]
    assert_no_selector "h2, h3"
    classes = section[:class].split
    %w[admin-action-zone flex flex-col items-start border-t border-line pt-4].each { |utility| assert_includes classes, utility }
    assert_not_includes classes, "justify-between"
    assert_selector "section p#zone-help.text-small.text-dim", text: "Kept in the trash for 30 days."
    assert page.find("section > :first-child").matches_css?("div"), "the cost line stands before the trigger"
    assert_selector "section > button:last-child", text: "Move to trash…"
  end

  test "with no cost line the zone is the rule and the trigger" do
    render_inline(Admin::Ui::ActionZoneComponent.new(label: "Move to trash")) do |zone|
      zone.with_trigger { "<button type=\"button\">Move to trash…</button>".html_safe }
    end

    assert_selector "section[aria-label='Move to trash'].border-t > button", text: "Move to trash…"
    assert_no_selector "section p"
  end

  test "a zone is named by a heading or a label, never by neither" do
    assert_raises(ArgumentError) { Admin::Ui::ActionZoneComponent.new(body: "B") }
    assert_raises(ArgumentError) { Admin::Ui::ActionZoneComponent.new(heading: "H", body: "B") }
  end
end
