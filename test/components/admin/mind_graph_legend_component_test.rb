require "test_helper"

class Admin::MindGraphLegendComponentTest < ViewComponent::TestCase
  test "lists only the content types it is given, once each, with their names" do
    render_inline(Admin::MindGraphLegendComponent.new(content_types: %w[resume_entry resume_entry]))

    assert_selector "[data-legend-type]", count: 1
    assert_selector "[data-legend-type=resume_entry] .admin-type-dot", text: ContentTypes.fetch("resume_entry").label
    assert_no_selector "[data-legend-type=blog]"
  end

  test "types come in registry order, an unregistered one last" do
    render_inline(Admin::MindGraphLegendComponent.new(content_types: %w[gone/type resume_entry blog]))

    assert_equal %w[blog resume_entry gone/type], page.all("[data-legend-type]").map { |li| li["data-legend-type"] }
    assert_selector "[data-legend-type='gone/type']", text: "gone/type"
  end

  test "always names the tag node, draft, and both edge kinds, as text" do
    render_inline(Admin::MindGraphLegendComponent.new(content_types: []))

    assert_selector "[data-legend=tag]", text: "Tag"
    assert_selector "[data-legend=hollow]", text: "Draft or scheduled"
    assert_selector "[data-legend=related]", text: "Related post"
    assert_selector "[data-legend=tag-edge]", text: "Shares a tag"
    assert_selector "[data-legend=related] .mg-edge-related"
    assert_selector "[data-legend=tag-edge] .mg-edge-tag"
  end
end
