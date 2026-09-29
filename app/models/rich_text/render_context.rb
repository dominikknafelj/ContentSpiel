# The three pieces of ambient state every `html`/`markdown_out` block
# (design spec §3.2/§3.3) needs but that the schema DSL can't hand them any
# other way, since a block only ever receives `(node, children, ctx)` --
# `RichText::HtmlRenderer` walks the tree, this is what it passes as `ctx`.
#
# `locale` and `urls` are exactly what `RichText::Document#to_html(locale:,
# urls:)` was given; `preview` is `urls.preview?`, captured once here rather
# than read fresh off `urls` wherever it's needed, both so every reader of
# a `RenderContext` sees one unambiguous flag (`ctx.preview`, no reaching
# back into `ctx.urls` for it) and so it's cheap to fold into the render
# cache key (`RichText::Document#to_html`) without the cache key builder
# needing to know `PublicSite::Urls` has a `#preview?` at all.
#
# `content_version` (fix round 1) is `PublicSite.current_content_version` --
# the site's content fingerprint, memoised per request -- captured here for
# the same reason as `preview`: the render cache key needs it, because a
# rendered body bakes in link hrefs and image URLs that change without the
# document itself changing (see `RichText::Document#to_html`).
#
# `document:` (media library Task 5) is the whole `RichText::Document`
# being rendered -- handed through so `#media_asset` can preload every
# `image` node's `Media::Asset` in one query, rather than
# `RichText::BuiltIns.render_image` running `Media::Asset.find_by` once per
# image node while `RichText::HtmlRenderer` walks the tree. Optional (`nil`
# default): this class is exposed directly for a caller that builds its own
# context without going through `RichText::Document#to_html` (this file's
# own top comment), and `#media_asset` degrades to a plain per-id lookup
# rather than requiring every such caller to also hand over a document.
module RichText
  class RenderContext
    attr_reader :locale, :urls, :preview, :content_version

    def initialize(locale:, urls:, document: nil, content_version: PublicSite.current_content_version)
      @locale = locale
      @urls = urls
      @preview = urls.preview?
      @content_version = content_version
      @document = document
    end

    # The `Media::Asset` an `image` node's `asset_id` names, or `nil` for a
    # missing/deleted one -- `RichText::BuiltIns.render_image`'s own lookup,
    # centralized here so the whole document's assets load in one query
    # (`#preloaded_media_assets`) instead of one per node. `id` may be
    # anything a hostile/never-validated document hands it (the built-in's
    # own comment on "hostile documents render inert") -- `Hash#[]`/`fetch`
    # against a `nil` or malformed key just misses, same as a `find_by`
    # would.
    def media_asset(id)
      return nil if id.nil?
      return Media::Asset.find_by(id: id) if @document.nil?

      preloaded_media_assets[id]
    end

    private

    # `Media::Asset.with_variants` (not a bare `where`): every asset this
    # loads is about to have `#srcset` called on it by
    # `Media::PictureComponent`, and that scope is exactly what lets
    # `#srcset` answer "is this variant processed" without a second query
    # per asset (`Media::Asset.with_variants`'s own comment) -- the same
    # N+1 this preload exists to close in the first place, just one join
    # deeper.
    def preloaded_media_assets
      @preloaded_media_assets ||= begin
        ids = @document.references.filter_map { |type, attribute, value| value if type == "image" && attribute == "asset_id" }
        Media::Asset.with_variants.where(id: ids).index_by(&:id)
      end
    end
  end
end
