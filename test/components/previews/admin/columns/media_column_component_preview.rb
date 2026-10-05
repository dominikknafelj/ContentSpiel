module Admin
  module Columns
    # `Admin::Columns::MediaColumnComponent` (media library Task 8): a
    # library image field before and after an image is chosen, and what a
    # viewer without `media.upload` gets -- no Choose (the picker isn't on
    # their page), the line that says why, and Remove while an image is set.
    class MediaColumnComponentPreview < ViewComponent::Preview
      def empty
        render Admin::Columns::MediaColumnComponent.new(name: "hero_image", id: "page-hero_image", html_name: "page[hero_media_asset_id]",
          value: nil, section_id: "page-hero-image-section")
      end

      def with_chosen_image
        render Admin::Columns::MediaColumnComponent.new(name: "image", id: "block-1-image", html_name: "block[media_asset_id]",
          value: PreviewFixtures.media_asset, section_id: "block-1-image-section")
      end

      def without_media_upload
        act_without_grants
        render Admin::Columns::MediaColumnComponent.new(name: "hero_image", id: "page-hero_image", html_name: "page[hero_media_asset_id]",
          value: nil, section_id: "page-hero-image-section")
      end

      def without_media_upload_with_an_image
        asset = PreviewFixtures.media_asset
        act_without_grants
        render Admin::Columns::MediaColumnComponent.new(name: "image", id: "block-1-image", html_name: "block[media_asset_id]",
          value: asset, section_id: "block-1-image-section")
      end

      private

      # A signed-in user in no group holds nothing. Set for the rest of this
      # preview request: a preview renders lazily, after its method returns, so
      # a `Current.set` block would already be over.
      def act_without_grants
        Current.actor = User.new(email_address: "viewer-preview@example.com")
        Current.channel = :admin
      end
    end
  end
end
