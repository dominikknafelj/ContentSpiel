module Admin
  module Columns
    # The slug input in a prefix cell (spec §4.3/§5.1) -- `base_url` is the
    # parent path this slug is appended to (a page's parent
    # `cached_paths[locale]`, or the listing page a post resolves under, spec
    # §3.3's permalink scheme), already resolved by the caller through
    # `PublicSite::Urls` (global constraints: public URLs only go through that
    # module) rather than this component building one itself.
    #
    # The address is shown once, as the prefix and the slug in the field; there
    # is no line under it. What the line used to say for a blank slug, the
    # slug the title will give, is the field's placeholder, which the editors'
    # `admin--editor--slug-preview` controller keeps (the caller passes the
    # input's target through `**html`).
    class SlugColumnComponent < Base
      def initialize(value:, base_url:, name: "slug", original: nil, errors: [], locale: nil, id: nil, html_name: nil, help: nil, **html)
        super(name: name, value: value, original: original, errors: errors, locale: locale, id: id, html_name: html_name, **html)
        @base_url = base_url
        @help = help
      end

      # The part of the public URL in front of the slug, shown in the prefix
      # cell: host and parent path, ending in exactly one slash. Callers pass
      # bases with and without a trailing slash (the root page's children,
      # a non-default language's prefix), which is how "//about" and
      # "/de//about" got on screen (design pass bug 1). The callers now strip
      # theirs at the source; this stays defensive for any other caller.
      def prefix
        base = base_url.to_s.sub(%r{\Ahttps?://}, "").gsub(%r{/+\z}, "")
        "#{base}/"
      end

      private

      # One line under the live URL telling an editor what editing the slug
      # does ("Changing it leaves a redirect from the old address") -- the
      # caller's, because it names the record ("page's", "post's").
      attr_reader :base_url, :help
    end
  end
end
