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
module RichText
  class RenderContext
    attr_reader :locale, :urls, :preview

    def initialize(locale:, urls:)
      @locale = locale
      @urls = urls
      @preview = urls.preview?
    end
  end
end
