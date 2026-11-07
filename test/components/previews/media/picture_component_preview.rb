require_relative "../preview_fixtures"

module Media
  # `Media::PictureComponent`: a processed asset with a real `srcset`, an
  # unprocessed one (no `srcset` attribute at all), and a missing asset
  # (renders nothing).
  class PictureComponentPreview < ViewComponent::Preview
    def with_srcset
      render Media::PictureComponent.new(asset: PreviewFixtures.processed_media_asset, alt: "A bright, plant-filled room")
    end

    def unprocessed_asset_has_no_srcset
      render Media::PictureComponent.new(asset: PreviewFixtures.media_asset, alt: "A bright, plant-filled room")
    end

    def missing_asset_renders_nothing
      render Media::PictureComponent.new(asset: nil, alt: "Gone")
    end
  end
end
