module Admin
  module Columns
    # The slug input plus its live URL preview line (spec §4.3/§5.1) --
    # `base_url` is the parent path this slug is appended to (a page's
    # parent `cached_paths[locale]`, or the listing page a post resolves
    # under, spec §3.3's permalink scheme), already resolved by the caller
    # through `PublicSite::Urls` (global constraints: public URLs only go
    # through that module) rather than this component building one itself.
    #
    # The preview line rendered here is a snapshot as of the page load, not
    # a live-updating one -- there's no JS wired up in this task to refresh
    # it as the slug input changes. `data-slug-preview-value` marks the
    # exact span a later task's autosave/slug controller can target to make
    # it actually live (mirroring `data-translate-slot`'s "reserved for
    # later" pattern in `Admin::FieldComponent`) without this component
    # needing to know about that controller yet.
    class SlugColumnComponent < Base
      def initialize(value:, base_url:, name: "slug", original: nil, errors: [], locale: nil)
        super(name: name, value: value, original: original, errors: errors, locale: locale)
        @base_url = base_url
      end

      def preview_url = "#{base_url.to_s.chomp('/')}/#{value}"

      private

      attr_reader :base_url
    end
  end
end
