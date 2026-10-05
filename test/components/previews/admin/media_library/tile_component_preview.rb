module Admin
  module MediaLibrary
    # `Admin::MediaLibrary::TileComponent` (round 3, Task 8): an image with no alt
    # text and no use (both chips), a plain one, the picker's button and the
    # selected one.
    class TileComponentPreview < ViewComponent::Preview
      def with_both_chips
        render Admin::MediaLibrary::TileComponent.new(asset: PreviewFixtures.media_asset.tap(&:reload), url: "#", unused: true)
      end

      def plain
        asset = PreviewFixtures.media_asset.tap(&:reload)
        asset.update!(alt: { Locales.default => "A described image" })
        render Admin::MediaLibrary::TileComponent.new(asset: asset, url: "#", unused: false)
      end

      # The picker's tile (round 3, Task 9): a button; `aria-pressed` draws the ring.
      def in_the_picker
        render Admin::MediaLibrary::TileComponent.new(asset: PreviewFixtures.media_asset.tap(&:reload), unused: true, pick: true)
      end

      def selected
        render Admin::MediaLibrary::TileComponent.new(asset: PreviewFixtures.media_asset.tap(&:reload), url: "#", unused: false, selected: true)
      end
    end
  end
end
