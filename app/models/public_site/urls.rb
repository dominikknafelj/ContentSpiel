# The only place a public URL is built (spec §6.2). Paths come from
# public_paths; this adds the language prefix (none for the site's default
# language) and, for absolute URLs, the host. Memoizes lookups per instance:
# one instance per request renders every nav/listing link off it.
module PublicSite
  class Urls
    # The site's public origin when one is configured (`PUBLIC_HOST`, else
    # `SITEMAP_HOST`), nil otherwise -- a local checkout has neither. Callers
    # that sit inside a request (CS Studio's "Copy" address) fall back to
    # the request's own origin then, rather than to the placeholder below,
    # which would hand an editor a link to a domain that isn't theirs.
    def self.configured_host
      SiteAddress.current.origin
    end

    def self.default_host
      configured_host || "https://www.example.com"
    end

    # The origin every absolute address of this instance starts with.
    attr_reader :host

    def initialize(preview: false, host: self.class.default_host)
      @preview = preview
      @host = host
      @paths = {}
      @targets = {}
    end

    # Whether this instance builds preview URLs -- read back by
    # `RichText::RenderContext` (design spec §3.3), which needs to know
    # (for the HTML render cache key) whether the `urls` it was handed
    # resolves internal links under `/preview` or not, without duplicating
    # the `preview:` flag as a second constructor argument that could drift
    # out of sync with this instance's own.
    def preview? = @preview

    def prefix(locale)
      code_prefix = locale.to_s == Locales.default ? "" : "/#{locale}"
      @preview ? "/preview#{code_prefix}" : code_prefix
    end

    # `listed_on:` is the page whose list a post is being drawn in, and it
    # matters in the PREVIEW only: the preview draws the rows, an address
    # follows the published copies (`PublicSite::Paths.canonical_pages`), so
    # a post in a list block that exists only in a live page's rows has no
    # address yet. Its link then is that page's preview address plus the
    # post's slug, which the preview's resolver answers with the post drawn
    # on that page (`Resolver#listing_fallback`) -- never the bare prefix,
    # which is the preview's homepage. Publicly a record without an address
    # has no path, as before.
    def path_for(record, locale = I18n.locale, listed_on: nil)
      return nil if record.nil?

      path = @paths.fetch([ record.class.name, record.id, locale.to_s ]) do |key|
        @paths[key] = PublicSite::Paths.current_path(record, locale)
      end
      path ||= PublicSite::Paths.post_path(record, locale, PublicSite::Paths.current_path(listed_on, locale)) if @preview && listed_on
      path_from(path, locale)
    end

    # The address of a page or a post named by its type and id, for a link
    # drawn in a body or on a card, or nil: no such record, one a visitor can't
    # reach, or no address in this language. Nothing but a live target with an
    # address gets one, so a draft's address never reaches a page. In the
    # preview the gate is off, because editors are the audience that needs to
    # follow links to what is not public yet (`Resolver` draws the same line).
    # This instance is all that is kept: what keeps a rendered link honest is
    # the public content version, which every input of this answer moves
    # (`PublicSite`, "WHO BUMPS"; `Paths.write_all` for an address, `Publishable`
    # for a state, the clock for a time that passes).
    #
    # NO ACTOR, on purpose: a rich-text render is cached with no actor in its
    # key. What only some people may see is decided above this (`link_for`).
    def target_path(type, id, locale = I18n.locale)
      # Base 10 from a string: a stored "010" is not octal 8, another page.
      id = Integer(id.to_s, 10, exception: false)
      return nil if id.nil? || LinkTargets.model(type).nil?

      read_targets([ [ type, id ] ], locale)
      path_for(@targets[[ type, id ]], locale)
    end

    # What a stored `:link` value is to a browser, or nil for no link: the
    # current address of the page or post it names (`target_path`), or the typed
    # address while `FieldTypes.link?` accepts it (a value accepted once and
    # refused now, or written around the service, draws no link). Always an
    # address or nil, never the reference, so the theme contract's `link` means
    # what it always did.
    #
    # In the preview the gate is off, so the reader's own rights stand in for it:
    # someone previewing a page they may read is told nothing of a draft outside
    # their read scope. Nothing renders a card under a cache, so the actor can be
    # asked here.
    def link_for(value, locale = I18n.locale)
      reference = ContentModel::LinkReference.parse(value)
      return (value if ContentModel::FieldTypes.link?(value)) unless reference
      return nil if @preview && !LinkTargets.readable(reference)

      target_path(reference.type, reference.id, locale)
    end

    # Reads what `target_path` needs for all of `references` at once, so that a
    # page of linked cards costs the same statements as one: the records, a
    # post's canonical page (one pass, `Resolver.visible_among`), one closure
    # query and the addresses. Only a target that may be drawn is kept. The page's
    # outline asks this (`ThemeHelper#block_outline`), past `stale?`, so a 304
    # pays nothing; a target it was not told of is read alone, by the same path.
    def prefetch_targets(references, locale = I18n.locale)
      read_targets(references.map { |reference| [ reference.type, reference.id ] }, locale)
      self
    end

    # Reads the current paths of `records` in `locale` in one statement and
    # keeps them for `path_for` (nil for a record that has none), so a list
    # drawn as links costs one read for its addresses and not one per link.
    # Records of several types are read type by type. Answers self.
    def prefetch(records, locale = I18n.locale)
      records.group_by { |record| record.class.polymorphic_name }.each do |type, group|
        ids = group.map(&:id)
        paths = PublicSite::Paths.current_paths(type, ids)
        ids.each { |id| @paths[[ group.first.class.name, id, locale.to_s ]] = paths.dig(id, locale.to_s) }
      end
      self
    end

    # The address made of a path ALREADY READ from `public_paths` (several
    # at once, `PublicSite::Paths.current_paths`): the same prefix, here and
    # nowhere else. nil for no path.
    def path_from(stored, locale = I18n.locale)
      stored && "#{prefix(locale)}#{stored}"
    end

    def url_for(record, locale = I18n.locale)
      path = path_for(record, locale)
      path && "#{@host}#{path}"
    end

    def alternates(record)
      Locales.enabled.filter_map { |locale| (url = url_for(record, locale)) && [ locale, url ] }.to_h
    end

    # An explicit prefix naming the current default language: that URL has an
    # unprefixed twin, so PagesController 302s it there (302 because the
    # default can change at runtime).
    def redundant_prefix?(locale_param)
      locale_param.present? && locale_param.to_s == Locales.default
    end

    private

    def read_targets(wanted, locale)
      wanted = wanted.uniq.reject { |key| @targets.key?(key) }
      return if wanted.empty?

      records = wanted.group_by(&:first).flat_map { |type, keys| LinkTargets.model(type).where(id: keys.map(&:last)).to_a } # public: rows (a link's target is judged by its state, and its address is the rows')
      drawn = @preview ? records : PublicSite::Resolver.visible_among(records) # public: rows (visibility is the tree and publish state, which no copy holds)
      wanted.each { |key| @targets[key] = nil }
      drawn.each { |record| @targets[[ record.model_name.element, record.id ]] = record }
      prefetch(drawn, locale)
    end
  end
end
