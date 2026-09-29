module RichText
  # `<figure><img><figcaption>` for an `image{asset_id, alt, caption}` node
  # (design spec §3.3). Takes a plain `src` String rather than a
  # `Media::Asset` -- `Media::Asset` doesn't exist until Task 4
  # (`RichText::BuiltIns`'s `image` node `html` block guards on
  # `defined?(Media::Asset)` and renders nothing until then, see that file's
  # comment) -- so this component is written now against an interface that
  # never has to change once `Media::Asset` arrives: whatever URL Task 4
  # resolves a `Media::Asset` to, it hands this component a String, the same
  # as every other caller.
  #
  # Deliberately not shaped like `Blocks::ImageComponent` (which takes
  # `block:`/`page:` and reads `translated(block, :alt)` through Mobility):
  # a rich-text `image` node's `alt`/`caption` are plain attrs on the node
  # itself, already resolved by the time `RichText::HtmlRenderer` gets
  # here, not per-locale translated columns on an ActiveRecord model.
  class ImageComponent < ApplicationComponent
    def initialize(src:, alt: nil, caption: nil)
      @src = src
      @alt = alt
      @caption = caption
    end

    private

    attr_reader :src, :alt, :caption
  end
end
