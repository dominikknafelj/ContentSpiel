module Admin
  module Columns
    # `Admin::Columns::MediaColumnComponent` (media library Task 8): a
    # library image field before and after an image is chosen.
    class MediaColumnComponentPreview < ViewComponent::Preview
      def empty
        render Admin::Columns::MediaColumnComponent.new(name: "hero_image", id: "page-hero_image", html_name: "page[hero_media_asset_id]",
          value: nil, section_id: "page-hero-image-section")
      end

      def with_chosen_image
        render Admin::Columns::MediaColumnComponent.new(name: "image", id: "block-1-image", html_name: "block[media_asset_id]",
          value: PreviewFixtures.media_asset, section_id: "block-1-image-section")
      end
    end
  end
end
