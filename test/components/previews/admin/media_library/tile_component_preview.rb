module Admin
  module MediaLibrary
    # `Admin::MediaLibrary::TileComponent` (round 3, Task 8): an image with no alt
    # text and no use (both chips), one that is selected, and a plain one.
    class TileComponentPreview < ViewComponent::Preview
      def with_both_chips
        render Admin::MediaLibrary::TileComponent.new(asset: PreviewFixtures.media_asset.tap(&:reload), url: "#", unused: true)
      end

      def selected
        render Admin::MediaLibrary::TileComponent.new(asset: PreviewFixtures.media_asset.tap(&:reload), url: "#", unused: false, selected: true)
      end
    end
  end
end
