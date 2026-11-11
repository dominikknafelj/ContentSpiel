require "test_helper"

# The one segmented control, in its two modes: links (a navigation, the
# chosen one `aria-current`) and radios (a fieldset of sr-only radios, the
# chosen one `checked`), one track, one segment, one count.
class Admin::Ui::SegmentedComponentTest < ViewComponent::TestCase
  test "links: a navigation named by its label, the chosen link aria-current, a count only where one is given, 0 included" do
    render_inline Admin::Ui::SegmentedComponent.new(mode: :links, label: "Screens", control_data: { turbo_frame: "content" }, segments: [
      { label: "Form", href: "/f", current: false }, { label: "Submissions", href: "/s", current: true, count: 3 }, { label: "Spam", href: "/x", count: 0 }
    ])

    assert_equal [ "Form", "Submissions 3", "Spam 0" ], page.all("nav[aria-label='Screens'] a").map { |a| a.text.squish }
    assert_selector "a[aria-current=page][href='/s']", count: 1
    assert_selector "a[href='/f'][data-turbo-frame=content]:not([aria-current])"
    assert_no_selector "a[href='/f'] span.text-count", wait: 0
    assert_selector "a[href='/x'] span.text-count", text: "0"
  end

  test "links: the chosen look and the focus ring are behind the link's own variants" do
    render_inline Admin::Ui::SegmentedComponent.new(mode: :links, label: "Screens", segments: [
      { label: "All", href: "/a", count: 4 }, { label: "Unread", href: "/u", current: true, count: 2 }
    ])

    link = page.find("a[href='/u']")[:class].split
    %w[aria-[current=page]:bg-accent-tint aria-[current=page]:text-accent aria-[current=page]:font-semibold aria-[current=page]:inset-ring
       aria-[current=page]:inset-ring-accent aria-[current=page]:hover:bg-accent-tint focus-visible:outline-2 focus-visible:outline-offset-2
       focus-visible:outline-accent text-dim hover:bg-sunken hover:text-ink].each { |name| assert_includes link, name }
    assert_empty link.grep(/has-\[/), "a link's looks are not a radio's"
    assert_equal page.find("a[href='/a']")[:class], page.find("a[href='/u']")[:class], "the chosen one differs by its aria-current alone"
  end

  test "radios: a fieldset with an sr-only legend, each segment a label around its sr-only radio, the count with its id" do
    render_inline Admin::Ui::SegmentedComponent.new(mode: :radios, name: :filter, label: "Show", segments: [
      { label: "All", value: "", id: "f-all", current: true, count: 7, count_id: "count-all" },
      { label: "Unused", value: "unused", id: "f-unused", count: 0, data: { port: 1 } }
    ])

    assert_selector "fieldset > legend.sr-only", text: "Show"
    assert_selector "fieldset > div > label[for='f-all'] > input[type=radio][name=filter][value=''][checked].sr-only#f-all"
    assert_selector "label[for='f-unused'] > input#f-unused[data-port='1']:not([checked]):not([disabled]):not([required])"
    assert_selector "label[for='f-all'] span#count-all.text-count", text: "7"
    assert_selector "label[for='f-unused'] span.text-count", text: "0"
    assert_no_selector "nav", wait: 0

    label = page.find("label[for='f-all']")[:class].split
    %w[has-[:checked]:bg-accent-tint has-[:checked]:text-accent has-[:checked]:inset-ring-accent has-[:focus-visible]:outline-2
       has-[:focus-visible]:outline-offset-2 has-[:focus-visible]:outline-accent has-[:disabled]:not-has-[:checked]:text-meta].each { |name| assert_includes label, name }
  end

  test "radios: a visible legend is the field's label, and the fieldset takes an id, a description and required radios" do
    render_inline Admin::Ui::SegmentedComponent.new(mode: :radios, name: "note[kind]", label: "Kind", legend: :visible, id: "kind", describedby: "kind-help",
      required: true, segments: [ { label: "Info", value: "info", id: "kind-info", current: true }, { label: "Warn", value: "warn", id: "kind-warn", disabled: true } ])

    assert_selector "fieldset#kind[aria-describedby='kind-help'] > legend:not(.sr-only)", text: "Kind"
    assert_selector "input[name='note[kind]'][required]", count: 2
    assert_selector "input#kind-warn[disabled]"
    assert_no_selector "span.text-count", wait: 0
  end

  test "one track and one count look: the field line on the surface, the button radius, 2px apart, and a count that turns accent with its own segment" do
    render_inline Admin::Ui::SegmentedComponent.new(mode: :radios, name: :s, label: "S", segments: [ { label: "A", value: "a", id: "a", count: 1 } ])

    assert_selector "fieldset > div.admin-segmented.inline-flex.flex-wrap.gap-0\\.5.rounded-button.border.border-field-line.bg-surface.p-0\\.5"
    assert_selector "label.group\\/segment.min-h-8.rounded-field.whitespace-nowrap.px-3.text-sm"
    count = page.find("span.text-count")[:class].split
    %w[text-meta tabular-nums group-has-[:checked]/segment:text-accent group-aria-[current=page]/segment:text-accent].each { |name| assert_includes count, name }
    assert_empty Admin::Ui::SegmentedComponent::TRACK_CLASS.split.grep(/overflow|divide|border-r/), "no dividers, and a wrapped track is never clipped"
  end

  test "no segments draw nothing, and a segment of the other mode or missing its own keys, an argument of the other mode, an unknown mode or a nameless radio group is refused" do
    render_inline Admin::Ui::SegmentedComponent.new(mode: :links, label: "S", segments: [])
    assert_no_selector "nav", wait: 0

    assert_raises(ArgumentError) { Admin::Ui::SegmentedComponent.new(mode: :tabs, label: "S", segments: []) }
    assert_raises(ArgumentError) { Admin::Ui::SegmentedComponent.new(mode: :radios, label: "S", segments: []) }
    assert_raises(ArgumentError) { Admin::Ui::SegmentedComponent.new(mode: :links, label: "S", segments: [ { label: "A", value: "a" } ]) }
    assert_raises(ArgumentError) { Admin::Ui::SegmentedComponent.new(mode: :radios, name: :s, label: "S", segments: [ { label: "A", href: "/a", id: "a" } ]) }
    assert_raises(ArgumentError) { Admin::Ui::SegmentedComponent.new(mode: :links, label: "S", segments: [ { label: "A", href: "/a", key: "a" } ]) }
    assert_raises(ArgumentError) { Admin::Ui::SegmentedComponent.new(mode: :radios, name: :s, label: "S", segments: [ { label: "A", id: "a" } ]) }
    assert_raises(ArgumentError) { Admin::Ui::SegmentedComponent.new(mode: :links, label: "S", segments: [ { label: "A", href: "/a", disabled: false } ]) }
    { name: :s, required: true, describedby: "d", legend: :visible }.each do |key, value|
      assert_raises(ArgumentError, key.to_s) { Admin::Ui::SegmentedComponent.new(mode: :links, label: "S", segments: [], **{ key => value }) }
    end
  end
end
