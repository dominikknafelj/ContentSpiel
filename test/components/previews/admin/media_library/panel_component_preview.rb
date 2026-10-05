module Admin
  module MediaLibrary
    # `Admin::MediaLibrary::PanelComponent` (media library design spec §6):
    # an unused image (editable, Move to trash offered), and one already placed as
    # a page's hero (Move to trash disabled with the reason, "Used on" naming that page), and
    # the view-only panel of someone who may not edit it (handoff B19).
    class PanelComponentPreview < ViewComponent::Preview
      def unused
        asset = PreviewFixtures.media_asset.tap(&:reload)

        render Admin::MediaLibrary::PanelComponent.new(asset: asset, locale: "en")
      end

      def view_only
        asset = PreviewFixtures.media_asset.tap(&:reload)
        viewer = User.new(email_address: "viewer-preview@example.com")

        # Set for the rest of this preview request (a preview renders lazily, after
        # this method returns, so a `Current.set` block would already be over).
        Current.actor = viewer
        Current.channel = :admin

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
