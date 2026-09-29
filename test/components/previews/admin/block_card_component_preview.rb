module Admin
  # `Admin::BlockCardComponent` (cs-studio spec §5.1): one example per block
  # type family -- a `uses_columns` type with an attached image, a schema
  # type with typed fields, and the "Unavailable type" card an unregistered
  # `block_type` falls back to (spec §8).
  class BlockCardComponentPreview < ViewComponent::Preview
    def image_block
      page = PreviewFixtures.page(title: "Image block preview")
      block = page.content_blocks.create!(block_type: "image", position: 0, media_asset: PreviewFixtures.media_asset)

      render Admin::BlockCardComponent.new(page: page, block: block, locale: "en")
    end

    def post_list_block
      page = PreviewFixtures.page(title: "Post list block preview")
      block = PreviewFixtures.post_list_block(page, { "limit" => 3 })

      render Admin::BlockCardComponent.new(page: page, block: block, locale: "en")
    end

    def unavailable_type
      page = PreviewFixtures.page(title: "Unavailable block preview")
      block = page.content_blocks.create!(block_type: "rich_text", position: 0)
      block.update_column(:block_type, "gone/thing")

      render Admin::BlockCardComponent.new(page: page, block: block.reload, locale: "en")
    end
  end
end
