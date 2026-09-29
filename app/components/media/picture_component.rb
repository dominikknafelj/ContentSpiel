module Media
  # One responsive `<img>` for a library `Media::Asset` (media library design
  # spec §4), the one place every image render on this site -- the page
  # hero, an image block, a rich-text `image` node -- builds its tag from.
  # Despite the name, this renders a plain `<img srcset sizes ...>`, not a
  # `<picture>` element: `srcset`/`sizes` alone are enough to offer the
  # browser every processed width (design spec §3.1's `w480`/`w960`/`w1600`/
  # `w2400`) without the `<source>`/art-direction machinery `<picture>`
  # exists for, which nothing here needs -- one image, several resolutions.
  #
  # `alt` arrives already resolved (`Media::Asset#alt_text(override:,
  # locale:)`) -- this component has no override/locale of its own to read,
  # since a rich-text node's alt, a block's alt, and a page's `hero_alt` are
  # three different resolution paths that only their own caller knows how
  # to walk.
  #
  # `src` always points at the original file (`Media::Asset#src`), matching
  # that method's own contract: whatever `srcset` comes back with is
  # additive, never a replacement -- a browser that ignores `srcset`
  # entirely (or one that's told to via `sizes`) still gets a real image,
  # and a variant that's missing, slow, or failed to process never breaks
  # the page around it (Review Focus 3).
  #
  # `loading="lazy"` by default, with `decoding="async"` always. The page
  # hero (`app/views/pages/show.html.erb`) passes `loading: "eager",
  # fetchpriority: "high"` instead (final fix wave, M4): it's the first
  # thing a landing page shows and usually its largest paint, so lazy-
  # loading it only delays it. `fetchpriority` is omitted unless given.
  class PictureComponent < ApplicationComponent
    def initialize(asset:, alt:, sizes: "100vw", css_class: nil, loading: "lazy", fetchpriority: nil)
      @asset = asset
      @alt = alt
      @sizes = sizes
      @css_class = css_class
      @loading = loading
      @fetchpriority = fetchpriority
    end

    # A missing asset, or one whose file is somehow gone (Review Focus 4's
    # "a page still points at it" is guarded against at the database layer,
    # but a caller can still hand this component a stale in-memory
    # reference, or `nil` outright, e.g. `page.hero_media_asset` when no
    # hero is set) -- renders nothing rather than a broken `<img>`, the same
    # posture every caller already took before this component existed
    # (`if hero&.file&.attached?`, `if asset&.file&.attached?`).
    def render? = asset&.file&.attached?

    private

    attr_reader :asset, :alt, :sizes, :css_class, :loading, :fetchpriority

    # The `srcset` attribute's own `"url widthw, url widthw"` shape, built
    # from `Media::Asset#srcset` -- already just the variants that exist,
    # are smaller than the original, and have actually finished processing
    # (that method's own comment). `nil` (not `""`) when there's nothing to
    # offer, so the template omits the attribute outright rather than
    # rendering an empty one -- an unprocessed asset, or a GIF (design spec:
    # "GIFs get no variants"), then renders `src` alone (Review Focus 3).
    #
    # The original is appended as the widest candidate when its width is
    # known (final fix wave, I3): once a `srcset` carries `w` descriptors, a
    # browser picks only among them and never falls back to `src`, so
    # without it a screen that wants more than the largest variant
    # (`#srcset` skips widths at or above the original's) would be capped
    # at a downscaled copy of a larger image. Without a known width there's
    # no descriptor to give it, and the variants alone still beat nothing.
    # Memoized: the template reads it twice (`srcset` and `sizes`).
    def srcset_attribute
      return @srcset_attribute if defined?(@srcset_attribute)

      pairs = asset.srcset
      pairs += [ [ asset.src, asset.width ] ] if pairs.any? && asset.width.present?
      @srcset_attribute = pairs.empty? ? nil : pairs.map { |url, width| "#{url} #{width}w" }.join(", ")
    end

    # `sizes` only means anything paired with a real `srcset` -- a browser
    # ignores it on an `<img>` with a single candidate, but shipping it
    # anyway would still claim widths this particular render has no
    # candidates for. `nil` here, like `srcset_attribute`, drops the
    # attribute from the tag entirely rather than rendering a misleading
    # one.
    def sizes_attribute
      sizes if srcset_attribute
    end
  end
end
