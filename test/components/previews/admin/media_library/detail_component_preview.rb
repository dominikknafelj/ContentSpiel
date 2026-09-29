module Admin
  module MediaLibrary
    # `Admin::MediaLibrary::DetailComponent` (media library design spec §6):
    # an unused image (editable, Delete offered), and one already placed as
    # a page's hero (Delete disabled, "Used on" naming that page).
    class DetailComponentPreview < ViewComponent::Preview
      def unused
        asset = PreviewFixtures.media_asset.tap(&:reload)

        render Admin::MediaLibrary::DetailComponent.new(asset: asset, locale: "en")
      end

      def used_as_a_hero
        asset = PreviewFixtures.media_asset
        page = PreviewFixtures.page(title: "Hero preview")
        page.update!(hero_media_asset: asset)
        Media::UsageIndex.refresh(page)

        render Admin::MediaLibrary::DetailComponent.new(asset: asset.reload, locale: "en")
      end
    end
  end
end
