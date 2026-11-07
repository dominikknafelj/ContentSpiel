module Admin
  module Ui
    # How CS Studio draws a library image (the grid, the panel, the picker, an
    # image field, a block's tile, the trash): a width the app made, else the
    # ~24px preview (blurred, since it is a placeholder and not the picture),
    # else a sunken box of the image's size with no `<img>` at all. It never
    # draws the original: the address is `Media::Asset#display_url`, which
    # only ever answers a width, the preview or nil.
    #
    # `width`/`height` are the image's own when known, so the box is laid out
    # before the file arrives. An image not decoded yet has none; the caller's
    # class then sizes it.
    class LibraryImageComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "An image with an empty alt, or an empty box hidden from a screen reader: whoever draws it names the image.",
        motion: :none,
        content_edges: %i[missing],
        widths: :from_container,
        interface: %i[asset min_width css_class loading],
        limits: [
          "It never draws the original, only a width the app made or the blurred preview.",
          "Its alt is always empty: the image's alt text is the caller's to say."
        ],
        states: %i[width preview empty],
        keys: [],
        slots: [],
        controller: nil
      )

      def initialize(asset:, min_width:, css_class: nil, loading: "lazy", **attributes)
        @asset = asset
        @url = asset.display_url(min_width: min_width)
        @css_class = css_class
        @loading = loading
        @attributes = attributes
      end

      def call
        @url ? picture : box
      end

      private

      attr_reader :asset, :url, :css_class, :loading, :attributes

      def picture
        tag.img(src: url, alt: "", width: asset.width, height: asset.height, loading: loading,
          class: class_names(css_class, "blur-sm": preview?), **attributes)
      end

      # No width and no preview: the same size, on the sunken ground.
      def box
        style = ("aspect-ratio: #{asset.width} / #{asset.height}" if asset.width && asset.height)
        tag.span(class: class_names(css_class, "block bg-sunken"), style: style, aria: { hidden: true },
          data: { image_empty: true })
      end

      def preview? = Media::Asset.preview_url?(url)
    end
  end
end
