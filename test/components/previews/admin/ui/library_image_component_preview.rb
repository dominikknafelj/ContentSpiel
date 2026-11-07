require_relative "../../preview_fixtures"

module Admin
  module Ui
    # `Admin::Ui::LibraryImageComponent`: a width the app made, the blurred
    # preview while none is made, and the sunken box of the image's size with
    # neither.
    class LibraryImageComponentPreview < ViewComponent::Preview
      def width
        render Admin::Ui::LibraryImageComponent.new(asset: PreviewFixtures.processed_media_asset, min_width: 480, css_class: "w-60")
      end

      def preview
        render Admin::Ui::LibraryImageComponent.new(asset: PreviewFixtures.media_asset, min_width: 480, css_class: "w-60")
      end

      def empty
        asset = PreviewFixtures.media_asset
        asset.update_columns(preview: nil) # version: none (a preview's own sample with no preview)
        render Admin::Ui::LibraryImageComponent.new(asset: asset, min_width: 480, css_class: "w-60")
      end
    end
  end
end
