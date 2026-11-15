module BlockTypes
  # A single library image with a caption and alt text (spec §3.1, media
  # library design spec §3.3). `caption`/`alt` are the block's own
  # translated per-use overrides (Mobility jsonb columns); `image` names the
  # block's image slot in CS Studio's block card -- stored as
  # `content_blocks.media_asset_id`, a reference to a `Media::Asset`
  # (`ContentBlock#media_asset`), no longer an attachment of the block's own.
  #
  # No presence validation on the image, before or after the move to the
  # library: the block picker creates an empty image block first and the
  # editor chooses its image afterwards, and the public component simply
  # renders nothing until one is set.
  module Image
    def self.register
      BlockTypes.register :image do |t|
        t.label "Image"
        t.icon "image", family: :media
        t.uses :image, :caption, :alt
        t.component Blocks::ImageComponent
        t.theme_methods :block, :page, :asset, :alt, :caption, :sizes
        t.search_text ->(block, locale:) { Image.search_text(block, locale: locale) }
        t.sample image: true, translations: { "en" => { caption: "Sample caption words", alt: "Sample alt words" } },
                 shows: [ "Sample caption words", %(alt="Sample alt words") ]
      end
    end

    # The block's own caption and alt override, drawn only with an image: the
    # library image's own alt text and caption are the asset's, looked up
    # live and in no copy (`Publishing::Snapshot`), so they would drift with
    # every library edit and are not searched.
    def self.search_text(block, locale:)
      return [] unless block.media_asset&.file&.attached?

      [ ::Locales.read(block, :caption, locale: locale), ::Locales.read(block, :alt, locale: locale) ]
    end
  end
end
