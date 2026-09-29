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
        t.uses :image, :caption, :alt
        t.component Blocks::ImageComponent
      end
    end
  end
end
