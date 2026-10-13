require "test_helper"

# One swatch of the Mind graph's legend or Status key: a canvas the graph's
# own renderer draws (`mind_graph/swatches.js`), sized here so the row does
# not move when it is drawn.
class Admin::MindGraphScreen::SwatchComponentTest < ViewComponent::TestCase
  test "a swatch is a canvas of its size that is no content: hidden from a screen reader, with nothing inside" do
    render_inline(Admin::MindGraphScreen::SwatchComponent.new(:page))

    assert_selector "canvas.mg-swatch[data-swatch=page][data-width='16'][data-height='12'][width='16'][height='12'][aria-hidden=true]", count: 1, text: ""
    assert_no_selector "canvas[tabindex], canvas[role]"
  end

  test "a swatch nobody defined is refused" do
    assert_raises(KeyError) { Admin::MindGraphScreen::SwatchComponent.new(:links_in_text) }
  end
end
