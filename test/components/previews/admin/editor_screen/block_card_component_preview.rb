module Admin
  module EditorScreen
    # `Admin::EditorScreen::BlockCardComponent` (cs-studio spec §5.1, design pass round 2):
    # one example per block type family -- a `uses_columns` type with an
    # attached image (alt and caption as per-use overrides), a post list with
    # Type / Tag / Limit in one row, and the "Unavailable type" card an
    # unregistered `block_type` falls back to (spec §8) -- plus the first and
    # last card of a list, whose Move up / Move down are disabled.
    class BlockCardComponentPreview < ViewComponent::Preview
      def image_block
        page = PreviewFixtures.page(title: "Image block preview")
        block = page.content_blocks.create!(block_type: "image", position: 0, media_asset: PreviewFixtures.media_asset)

        render Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en")
      end

      def post_list_block
        page = PreviewFixtures.page(title: "Post list block preview")
        block = PreviewFixtures.post_list_block(page, { "limit" => 3 })

        render Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en")
      end

      def first_of_a_list
        page = PreviewFixtures.page(title: "First block preview")
        block = page.content_blocks.create!(block_type: "rich_text", position: 0)

        render Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en", first: true)
      end

      def last_of_a_list
        page = PreviewFixtures.page(title: "Last block preview")
        block = page.content_blocks.create!(block_type: "rich_text", position: 0)

        render Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en", last: true)
      end

      def unavailable_type
        page = PreviewFixtures.page(title: "Unavailable block preview")
        block = page.content_blocks.create!(block_type: "rich_text", position: 0)
        block.update_column(:block_type, "gone/thing")

        render Admin::EditorScreen::BlockCardComponent.new(page: page, block: block.reload, locale: "en")
      end
    end
  end
end
