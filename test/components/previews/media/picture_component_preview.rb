require_relative "../preview_fixtures"

module Media
  # `Media::PictureComponent` (media library design spec §4, Task 5): a
  # processed asset with a real `srcset`, an unprocessed one (no `srcset`
  # attribute at all, Review Focus 3), and a missing asset (renders
  # nothing).
  class PictureComponentPreview < ViewComponent::Preview
    def with_srcset
      render Media::PictureComponent.new(asset: processed_asset, alt: "A bright, plant-filled room")
    end

    def unprocessed_asset_has_no_srcset
      render Media::PictureComponent.new(asset: PreviewFixtures.media_asset, alt: "A bright, plant-filled room")
    end

    def missing_asset_renders_nothing
      render Media::PictureComponent.new(asset: nil, alt: "Gone")
    end

    private

    # `PreviewFixtures.media_asset` alone has no generation -- this preview
    # needs a real `srcset`, so it records one (no file is made). `wide.png`
    # (`test/fixtures/files`, already used for exactly this in that test)
    # is a real 3000x2000 PNG, so every one of the four declared widths is
    # smaller than the original and ends up in `srcset`.
    def processed_asset
      asset = Media::Asset.new
      asset.file.attach(io: File.open(Rails.root.join("test/fixtures/files/wide.png")), filename: "wide.png")
      asset.save!
      asset.file.analyze
      metadata = asset.file.blob.metadata || {}
      asset.update_columns(width: metadata["width"], height: metadata["height"])
      settings = ImageSettings.current
      files = Media::Renditions.widths_for(original_width: asset.width, configured: settings.widths).map do |width|
        variation = ActiveStorage::Variation.wrap(Media::Renditions.transformations(
          width: width, format: settings.format, quality: settings.quality, content_type: asset.content_type
        ))
        { "width" => width, "key" => variation.key, "digest" => variation.digest }
      end
      asset.update_columns(renditions: { "current" => { "fingerprint" => settings.fingerprint, "files" => files } }) # version: none (a preview's recorded generation)
      asset
    end
  end
end
