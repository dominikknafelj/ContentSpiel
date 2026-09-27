require "test_helper"

class Blocks::ImageComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper

  test "alt and caption fall back along the fallback chain" do
    with_locales(%w[en de], default: "en") do
      page = root_page
      block = page.content_blocks.create!(block_type: :image, position: 0)
      block.image.attach(io: File.open(Rails.root.join("public/icon.png")), filename: "icon.png")
      block.alt = "A bright room"
      block.caption = "Our studio"
      block.save!

      I18n.with_locale(:de) do
        render_inline(Blocks::ImageComponent.new(block: block, page: page))
      end

      assert_selector "img[alt='A bright room']"
      assert_selector "figcaption", text: "Our studio"
    end
  end
end
