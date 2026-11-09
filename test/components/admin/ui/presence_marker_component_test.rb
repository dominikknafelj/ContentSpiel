require "test_helper"

# The people on a row, as circles: the one drawing of the page tree's and the
# posts list's marker. It knows no feature, so the letters, the count and the
# words are its caller's.
class Admin::Ui::PresenceMarkerComponentTest < ViewComponent::TestCase
  def render_marker(people: %w[DW JL], count: people.size, label: "2 people here: Dana Weiss, Jonas Lind", shown: 2, **options)
    render_inline Admin::Ui::PresenceMarkerComponent.new(people:, count:, label:, shown:, **options)
  end

  test "it draws shown circles of initials with the here ring, hidden past the people, then +N" do
    render_marker(people: %w[DW JL], count: 5, shown: 3, label: "5 people here")

    assert_selector "span.admin-presence-marker:not([hidden])"
    assert_selector "[data-presence-avatar]", count: 3, visible: :all
    assert_selector "[data-presence-avatar]:not([hidden]) > span.size-\\[22px\\].bg-people-tint.text-people.inset-ring-\\[1\\.5px\\].inset-ring-people", count: 2
    assert_selector "[data-presence-avatar]:nth-of-type(1) > span", text: "DW", exact_text: true
    assert_selector "[data-presence-avatar]:nth-of-type(2) > span", text: "JL", exact_text: true
    assert_selector "[data-presence-avatar][hidden]", count: 1, visible: :all
    assert_selector "[data-presence-avatar][hidden] > span", text: "", exact_text: true, visible: :all
    # Wide: everyone past the circles; narrow: everyone past the first.
    assert_selector "[data-presence-more]:not([hidden]) > span.bg-sunken", text: "+2", exact_text: true
    assert_selector "[data-presence-more-narrow]:not([hidden]) > span.bg-sunken", text: "+4", exact_text: true
  end

  test "up to the circles shown there is no wide +N, and a lone person has no narrow one" do
    render_marker(people: %w[DW JL], count: 2, shown: 2)
    assert_selector "[data-presence-more][hidden]", visible: :all
    assert_selector "[data-presence-more-narrow]:not([hidden])", text: "+1", exact_text: true

    render_marker(people: %w[DW], count: 1, shown: 2)
    assert_selector "[data-presence-more-narrow][hidden]", visible: :all
    assert_selector "[data-presence-avatar]:not([hidden])", count: 1
  end

  test "the circles and +N stand 2px apart with no ring, and the count circle holds the number, 9+ past nine" do
    render_marker(people: %w[DW JL], count: 3, shown: 2)

    assert_selector "span.admin-presence-marker.gap-0\\.5[data-presence-count='3']", count: 1
    assert_no_selector "[class*='-ml-'], [class*='ring-2'], [class*='avatar-ground']", visible: :all
    assert_selector "span.admin-presence-marker > [data-presence-total]:last-of-type, span.admin-presence-marker > [data-presence-total]", count: 1
    assert_selector "[data-presence-total] > span.size-\\[22px\\].bg-sunken.text-ink[aria-hidden=true]", text: "3", exact_text: true
    assert_equal %w[presence-avatar presence-avatar presence-more presence-more-narrow presence-total],
      page.all("span.admin-presence-marker > span[class~=flex]", visible: :all).map { |part| part.native.attributes.keys.find { |name| name.start_with?("data-presence-") }.delete_prefix("data-") }

    render_marker(people: %w[DW JL], count: 12, shown: 2)
    assert_selector "[data-presence-total] > span", text: "9+", exact_text: true

    render_marker(people: [], count: 0, label: "", shown: 2)
    assert_selector "[data-presence-total] > span", text: "", exact_text: true, visible: :all
  end

  test "ten and more people read 9+" do
    render_marker(people: %w[DW JL], count: 12, shown: 2)

    assert_selector "[data-presence-more] > span", text: "9+", exact_text: true
  end

  test "nobody is a hidden marker that still holds its slots" do
    render_marker(people: [], count: 0, label: "", shown: 2)

    assert_selector "span.admin-presence-marker[hidden]", visible: :all
    assert_selector "[data-presence-avatar][hidden]", count: 2, visible: :all
    assert_selector "[data-presence-more][hidden], [data-presence-more-narrow][hidden]", count: 2, visible: :all
    assert_selector "[data-presence-more][hidden] > span, [data-presence-more-narrow][hidden] > span", text: "", exact_text: true, count: 2, visible: :all
    assert_selector "span.sr-only[data-presence-marker-label]", text: "", exact_text: true, visible: :all
    assert_selector "[data-tooltip][hidden]", text: "", exact_text: true, visible: :all
  end

  test "the circles and +N are hidden from a screen reader; the label is the one text" do
    render_marker(lead: ", ")

    assert_selector "[data-presence-avatar] > span[aria-hidden=true]", count: 2
    assert_selector "[data-presence-more] > span[aria-hidden=true], [data-presence-more-narrow] > span[aria-hidden=true]", visible: :all
    assert_selector "span.sr-only[data-presence-marker-label][data-presence-lead=', ']", text: ", 2 people here: Dana Weiss, Jonas Lind", exact_text: true
    assert_selector "[data-tooltip]", text: "2 people here: Dana Weiss, Jonas Lind", exact_text: true, visible: :all
    assert_no_selector "a, button, [tabindex], [role], [title], [aria-live]", visible: :all
  end

  test "the caller's data goes on the root, beside the words the script writes the +N with" do
    render_marker(data: { presence_marker: "page-1", presence_count: 2 })

    assert_selector "span.admin-presence-marker[data-presence-marker='page-1'][data-presence-count='2'][data-messages]"
    messages = JSON.parse(page.find("span.admin-presence-marker", visible: :all)["data-messages"])
    assert_equal({ "@locale" => "en", "components.ui.avatar.more" => "+%{count}", "components.ui.avatar.many" => "9+" }, messages)
  end

  test "a name is text, whatever was typed as one" do
    render_marker(people: [ "<b>" ], count: 1, label: "<b>Dana</b> is here", shown: 1)

    assert_no_selector "b", visible: :all
    assert_selector "[data-presence-avatar] > span", text: "<b>", exact_text: true
  end
end
