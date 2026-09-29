module Admin
  module MediaLibrary
    # `Admin::MediaLibrary::GridComponent` (media library design spec §6): a
    # handful of cards, and the empty state an unfiltered library with
    # nothing uploaded yet (or a filter matching nothing) falls back to.
    class GridComponentPreview < ViewComponent::Preview
      def with_assets
        assets = Array.new(3) { PreviewFixtures.media_asset }.each(&:reload)

        render Admin::MediaLibrary::GridComponent.new(assets: Media::Asset.with_variants.where(id: assets.map(&:id)))
      end

      def empty
        render Admin::MediaLibrary::GridComponent.new(assets: Media::Asset.none)
      end
    end
  end
end
