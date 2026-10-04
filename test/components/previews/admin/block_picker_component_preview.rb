module Admin
  # `Admin::BlockPickerComponent` (design pass round 2): the one dashed
  # "+ Add block" row at the end of the block list, with an inline button per
  # registered block type.
  class BlockPickerComponentPreview < ViewComponent::Preview
    def at_the_end
      page = PreviewFixtures.page(title: "Block picker preview")
      render Admin::BlockPickerComponent.new(page: page, locale: "en")
    end
  end
end
