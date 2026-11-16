require "test_helper"

class Blocks::GalleryComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper

  test "a gallery draws nothing yet" do
    block = ContentBlock.new(owner: root_page, block_type: "gallery")
    block.assign_settings({ "label" => "Harbour" }, locale: "en")

    render_inline Blocks::GalleryComponent.new(block: block, page: root_page)
    assert_no_selector ".content-block--gallery"
  end
end
