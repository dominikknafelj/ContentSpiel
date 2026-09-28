module Admin
  # `Admin::BlockPickerComponent` (cs-studio spec §5.1): the small collapsed
  # "+" between two cards, versus the page's own open-by-default "+ Add
  # block" at the end of the list.
  class BlockPickerComponentPreview < ViewComponent::Preview
    def at_the_end
      page = PreviewFixtures.page(title: "Block picker preview")
      render Admin::BlockPickerComponent.new(page: page, locale: "en")
    end

    def between_cards
      page = PreviewFixtures.page(title: "Block picker preview")
      block = page.content_blocks.create!(block_type: "rich_text", position: 0)
      render Admin::BlockPickerComponent.new(page: page, locale: "en", after_id: block.id)
    end
  end
end
