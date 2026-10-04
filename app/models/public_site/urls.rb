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
      ENV["PUBLIC_HOST"].presence || ENV["SITEMAP_HOST"].presence
    end

    def self.default_host
      configured_host || "https://www.example.com"
    end

    def initialize(preview: false, host: self.class.default_host)
      @preview = preview
      @host = host
      @paths = {}
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

    def path_for(record, locale = I18n.locale)
      return nil if record.nil?

      path = @paths.fetch([ record.class.name, record.id, locale.to_s ]) do |key|
        @paths[key] = PublicSite::Paths.current_path(record, locale)
      end
      path && "#{prefix(locale)}#{path}"
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
  end
end
