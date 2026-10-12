require "test_helper"

class Admin::EditorScreen::NoAddressChipComponentTest < ViewComponent::TestCase
  test "the chip says there is no address, and the tooltip says why" do
    render_inline(Admin::EditorScreen::NoAddressChipComponent.new)

    assert_selector "span[data-no-address]", text: "No address"
    assert_selector "span[data-no-address][title*='Another page or post holds this address']"
  end
end
