require "test_helper"

class Admin::MindGraphScreen::LegendComponentTest < ViewComponent::TestCase
  test "lists only the content types it is given, once each, with their names" do
    render_inline(Admin::MindGraphScreen::LegendComponent.new(content_types: %w[resume_entry resume_entry]))

    assert_selector "[data-legend-type]", count: 1
    assert_selector "[data-legend-type=resume_entry] .admin-type-dot", text: ContentTypes.fetch("resume_entry").label
    assert_no_selector "[data-legend-type=blog]"
  end

  test "types come in registry order" do
    render_inline(Admin::MindGraphScreen::LegendComponent.new(content_types: %w[resume_entry blog]))

    assert_equal %w[blog resume_entry], page.all("[data-legend-type]").map { |li| li["data-legend-type"] }
  end

  # Mind graph canvas spec §5.1: a post whose type is no longer registered is
  # a grey ring with a stroke through it, and the legend says so once -- the
  # stored name is not a label, and the type has no colour slot for a dot.
  test "a retired type adds the Retired type entry, drawn with a stroke through it, and gets no dot of its own" do
    render_inline(Admin::MindGraphScreen::LegendComponent.new(content_types: %w[gone/type resume_entry gone/other]))

    assert_selector "[data-legend=retired]", text: "Retired type", count: 1
    assert_selector "[data-legend=retired] circle.mg-key-retired"
    assert_selector "[data-legend=retired] line.mg-key-retired"
    assert_equal %w[resume_entry], page.all("[data-legend-type]").map { |li| li["data-legend-type"] }
    assert_no_text "gone/type"
  end

  test "without a retired type there is no Retired type entry" do
    render_inline(Admin::MindGraphScreen::LegendComponent.new(content_types: %w[blog resume_entry]))

    assert_no_selector "[data-legend=retired]"
  end

  test "always names the tag node, draft, and both edge kinds, as text" do
    render_inline(Admin::MindGraphScreen::LegendComponent.new(content_types: []))

    assert_selector "ul[aria-label='Legend']"
    assert_selector "[data-legend=tag]", text: "Tag"
    assert_selector "[data-legend=hollow]", text: "Draft or scheduled"
    assert_selector "[data-legend=related]", text: "Related post"
    assert_selector "[data-legend=tag-edge]", text: "Shares a tag"
    assert_selector "[data-legend=related] .mg-edge-related"
    assert_selector "[data-legend=tag-edge] .mg-edge-tag"
  end

  # The mark of a node that stays where it was dropped (the round of
  # 2026-10-08): the canvas draws a small ink dot at the node's top-right, and
  # the legend names it.
  test "names the pin mark" do
    render_inline(Admin::MindGraphScreen::LegendComponent.new(content_types: []))

    assert_selector "li[data-legend=pinned]", text: "Pinned"
    assert_selector "[data-legend=pinned] circle.mg-key-pin"
  end

  # A post with open notes (notes spec §4.4): the canvas draws its count in a
  # small badge at the node's top-left, opposite the pin, and the legend
  # names it after the pin.
  test "names the notes badge, last, after the pin" do
    render_inline(Admin::MindGraphScreen::LegendComponent.new(content_types: []))

    assert_selector "li[data-legend=pinned] + li:last-child[data-legend=notes]", text: "Open notes"
    assert_selector "[data-legend=notes] rect.mg-key-notes"
  end
end
