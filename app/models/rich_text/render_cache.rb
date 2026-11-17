module RichText
  # The public render cache of rich text (`Document#to_html`, a body's HTML,
  # and `Document#table_cells_html`, a table's cells): its key, and the reads.
  #
  # THE KEY is what a public render is drawn from, each part's reason in
  # `Document#to_html`'s comment: the kind (a body's render and a table's
  # cells are drawn from one document), the document (`#cache_identity`: the
  # published copy and the block for a body read from a copy, else the
  # document's digest), `Schema.version`, the locale, the site's content
  # version and `RichText.code_revision`. It names no preview and no actor,
  # because neither ever reaches it: a preview is drawn every time, and is
  # never prefetched. It names no theme either, by design: a theme styles a
  # rendered body and does not change its HTML (`docs/reference/theming.md`,
  # "The render cache and the ETag").
  #
  # A COPY'S BODY IS NAMED BY THE COPY because a copy never changes: what a
  # copy holds is written once, when it is taken. The writes that rewrite
  # copies' `blocks` are a merge of tags, which rewrites a list's
  # `listed_tag_id` and no body, and a migration, which ships with a deploy
  # and so with a new `code_revision`. A restored backup gives copy ids out
  # again, and needs `Rails.cache.clear` already for the content version
  # (`docs/reference/rich-text.md`).
  #
  # ONE READ PER PAGE: a page asks for every block's render at once
  # (`prefetch`, from `ThemeHelper#block_outline`), one `read_multi`, which
  # Solid Cache answers in one statement where one read per block was one
  # round trip each (117 for the guide's largest page). What it read, and
  # which keys it found missing, are kept for the request on `Current`, and
  # `fetch` answers from them; a key nobody prefetched is an ordinary
  # `Rails.cache.fetch`. The prefetch is only ever an optimisation: it asks
  # the same keys `fetch` would, so a block it guessed wrong (another kind,
  # another language) is read on its own, as before.
  module RenderCache
    KINDS = { html: "rich_text", table_cells: "rich_text_table_cells" }.freeze

    module_function

    def key(kind, document, locale, content_version)
      [ KINDS.fetch(kind), document.cache_identity, RichText::Schema.version, locale.to_s, content_version, RichText.code_revision ]
    end

    # Reads the renders of `wanted` (`[kind, document]` pairs) in one
    # `read_multi` and keeps them for the request. Nothing for a preview
    # (`urls.preview?`), which never meets the cache.
    def prefetch(wanted, locale:, urls:, content_version: PublicSite.current_content_version)
      return if urls.preview? || wanted.empty?

      keys = wanted.map { |kind, document| key(kind, document, locale, content_version) }.uniq
      found = Rails.cache.read_multi(*keys)
      kept = (Current.rich_text_renders ||= {})
      keys.each { |k| kept[name(k)] = found.key?(k) ? [ :hit, found[k] ] : [ :miss ] }
    end

    # The render under `key`: the one the page's prefetch read, else the
    # block's answer written under it when the prefetch found none, else an
    # ordinary `Rails.cache.fetch`.
    def fetch(key)
      kept = Current.rich_text_renders
      state, value = kept&.[](name(key))
      case state
      when :hit then value
      when :miss
        yield.tap do |drawn|
          Rails.cache.write(key, drawn)
          kept[name(key)] = [ :hit, drawn ]
        end
      else Rails.cache.fetch(key) { yield }
      end
    end

    def name(key) = ActiveSupport::Cache.expand_cache_key(key)
  end
end
