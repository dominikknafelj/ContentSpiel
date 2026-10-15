require "test_helper"

class Admin::Ui::UnpublishedChipComponentTest < ViewComponent::TestCase
  test "full: the label in the chip, with a warn dot a screen reader skips" do
    render_inline(Admin::Ui::UnpublishedChipComponent.new)

    assert_selector "span[data-unpublished-changes].bg-sunken:not([class*=border])", text: "Unpublished changes"
    assert_selector "span[data-unpublished-changes] span.bg-warn[aria-hidden=true]"
  end

  test "there is no compact mode any more: the tree draws its own mark" do
    assert_raises(ArgumentError) { Admin::Ui::UnpublishedChipComponent.new(compact: true) }
  end
end
