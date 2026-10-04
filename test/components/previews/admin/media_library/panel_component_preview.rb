module Admin
  module MediaLibrary
    # `Admin::MediaLibrary::PanelComponent` (media library design spec §6):
    # an unused image (editable, Move to trash offered), and one already placed as
    # a page's hero (Delete disabled, "Used on" naming that page).
    class PanelComponentPreview < ViewComponent::Preview
      def unused
        asset = PreviewFixtures.media_asset.tap(&:reload)

        render Admin::MediaLibrary::PanelComponent.new(asset: asset, locale: "en")
      end

      def used_as_a_hero
        asset = PreviewFixtures.media_asset
        page = PreviewFixtures.page(title: "Hero preview")
        page.update!(hero_media_asset: asset)
        Media::UsageIndex.refresh(page)

        render Admin::MediaLibrary::PanelComponent.new(asset: asset.reload, locale: "en")
      end
    end
  end
end
