class Theme
  # How the public layout takes the one public stylesheet (theming spec §4,
  # `docs/reference/theming.md`, "Drawn into the page, or linked"): its CSS
  # drawn into the head as a `<style>`, when the built file is at or under
  # `ThemeCss::INLINE_LIMIT` compressed (the reason is that constant's), or
  # the `<link>` every theme had before, above it: that is the site's
  # default mode, Automatic, and Settings → Page speed may fix it to either
  # way instead (`SiteSetting#stylesheet_mode`, `#inline?`). Every theme gets
  # this, the default included, and nothing of a theme decides it but the
  # size of its built stylesheet.
  #
  # WHAT IS DRAWN IN IS WHAT PROPSHAFT SERVES at the digested address: the
  # asset's compiled content, whose `url(…)` of a font or an image is
  # rewritten to its absolute `/assets/<name>-<digest>` address, so it
  # resolves from a `<style>` in a page at any depth as it did from the
  # stylesheet at `/assets/`. A stylesheet is still linked when drawing it
  # in could change what it does:
  # - a `url(…)` or an `@import` Propshaft left relative (an asset it could
  #   not find): from the page it would resolve against the page's address,
  #   and a visitor's browser would ask the public router for a font;
  # - the text `</style` anywhere (in a `content:` string, a comment): it
  #   would end the element and print the rest of the CSS into the page.
  #
  # READ ONCE PER PROCESS PER DIGEST. Propshaft's load path hands out one
  # asset object until its cache is swept (in development, when a file
  # under an asset path changed: a rebuild), so production reads, compiles
  # and weighs the file at the first public page and never again, and a
  # development rebuild is read at the next page. The digest is also a key
  # of the public ETag (`PagesController#show`), so a page drawn with the
  # old CSS is never confirmed by a 304 after the stylesheet changed.
  class Stylesheet
    LOGICAL_PATH = "theme.css".freeze

    RELATIVE_REFERENCE = %r{url\(\s*(?!["']?(?:[/#]|%23|data:|https?:))|@import\s+(?!url\(|["'](?:/|https?:))}i
    STYLE_END = %r{</style}i

    @mutex = Mutex.new

    class << self
      # The stylesheet as the layout draws it now: `nil` when there is no
      # built file (the layout then links it, as it did before, and the
      # asset helper says what is missing). Whether it is drawn in is asked
      # of it with the site's mode (`#inline?`), so one object serves every
      # mode and a change of the setting reads and weighs nothing again.
      def current
        asset = Rails.application.assets.load_path.find(LOGICAL_PATH)
        return unless asset

        @mutex.synchronize do
          @current = nil unless @current && @current.digest == asset.digest && @current.limit == limit
          @current ||= new(asset, limit: limit)
        end
      end

      def limit = @limit || ThemeCss::INLINE_LIMIT

      # FOR TESTS ONLY: another limit for the length of the block, as
      # `Theme.with` is another theme. Process-wide, like it.
      def with_limit(bytes)
        before = @limit
        @limit = bytes
        yield
      ensure
        @limit = before
      end
    end

    # `compressed_size` is the built file gzipped, in bytes, what the
    # decision weighs (`ThemeCss.kilobytes` says it in KB). `css` is the
    # compiled content when a `<style>` would not change what it does, nil
    # otherwise: it is drawn in only when `#inline?` says so too.
    attr_reader :digest, :limit, :compressed_size, :css

    def initialize(asset, limit:)
      @digest = asset.digest
      @limit = limit
      @compressed_size = ThemeCss.compressed_size(asset.content)
      css = asset.compiled_content.to_s.dup.force_encoding(Encoding::UTF_8)
      @css = css if drawable?(css)
    end

    # Drawn in for the site's `mode` (`SiteSetting#stylesheet_mode`,
    # `ThemeCss::MODES`): what `ThemeCss.inline_for?` decides from the mode
    # and the size, and never a stylesheet a `<style>` would change, whatever
    # the mode ("Always in the page" included).
    def inline?(mode) = !css.nil? && ThemeCss.inline_for?(mode, compressed_size, limit: limit)

    private

    # Whatever the mode: a `<style>` would not change what the CSS does.
    def drawable?(css) = css.valid_encoding? && !css.match?(RELATIVE_REFERENCE) && !css.match?(STYLE_END)
  end
end
