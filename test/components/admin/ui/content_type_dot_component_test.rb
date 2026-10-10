require "test_helper"

class Admin::Ui::ContentTypeDotComponentTest < ViewComponent::TestCase
  test "types 1-6 get a filled dot in their own colour, with the type name" do
    render_inline(Admin::Ui::ContentTypeDotComponent.new(content_type: "blog"))
    assert_selector ".admin-type-dot span[aria-hidden=true].bg-cat-1"
    assert_text ContentTypes.fetch("blog").label
  end

  test "an index above six wraps to a ring in the same six hues" do
    component = Admin::Ui::ContentTypeDotComponent.new(content_type: "blog")
    assert_equal "bg-cat-1", component.mark_class(1)
    assert_equal "border border-cat-1", component.mark_class(7)
    assert_equal "bg-cat-1", component.mark_class(13)
    assert_equal "border border-cat-6", component.mark_class(12)
  end

  test "an unregistered type still renders, as a neutral ring and its raw name" do
    render_inline(Admin::Ui::ContentTypeDotComponent.new(content_type: "gone/type"))
    assert_selector ".admin-type-dot span.border-meta"
    assert_text "gone/type"
  end
end
