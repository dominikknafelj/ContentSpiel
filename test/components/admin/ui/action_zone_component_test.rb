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
end
