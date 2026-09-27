# View helpers for the public default theme (spec §9). Everything the public
# layout shows comes from SiteSetting and the page tree, so editors' settings
# have a visible effect.
module ThemeHelper
  SAFE_LINK_SCHEMES = %w[http https mailto].freeze

  LanguageLink = Data.define(:code, :name, :path, :current)

  # Current.site memoizes itself for the process/request; no ivar of our own
  # needed the way SetupController's @site_setting is.
  def theme_site
    Current.site
  end

  # Social links become real hrefs here for the first time, so only
  # http/https/mailto URLs render -- a `javascript:` link typed into the
  # settings must never reach the page.
  def safe_social_links
    theme_site.social_links.to_h.select { |_name, url| safe_link?(url) }
  end

  def safe_link?(url)
    scheme = URI.parse(url.to_s.strip).scheme
    scheme.present? && SAFE_LINK_SCHEMES.include?(scheme.downcase)
  rescue URI::InvalidURIError
    false
  end

  def theme_root_page
    return @theme_root_page if defined?(@theme_root_page)

    @theme_root_page = Page.find_by(parent_id: nil)
  end

  def navigation_pages
    theme_root_page ? theme_root_page.children.published.to_a : []
  end

  def home_url_path
    theme_root_page ? page_url_path(theme_root_page) : "/"
  end

  def post_date(post)
    post.published_at&.strftime("%-d %b %Y")
  end

  # Resume periods show years only; an empty end date is the current role.
  def resume_period(post)
    start_year = post.start_date.to_s[0, 4].presence
    end_year = post.end_date.to_s[0, 4].presence || "now"
    start_year ? "#{start_year} – #{end_year}" : end_year
  end

  # The current page -- or, at a permalink, the current post -- in each
  # locale. A post's slug is read inside that locale, falling back to the
  # default-locale slug exactly as the router does.
  def language_links(page, post = nil)
    return [] if page.nil?

    I18n.available_locales.map(&:to_s).map do |code|
      path = I18n.with_locale(code) { post ? post_url_path(page, post, code) : page_url_path(page, code) }
      LanguageLink.new(code:, name: SetupHelper::LANGUAGE_NAMES.fetch(code, code.upcase), path:,
        current: code == I18n.locale.to_s)
    end
  end

  # Reads a Mobility-translated attribute for the public theme, falling back
  # (when the current locale's own value is blank) to the *site's* runtime
  # default locale, then to the first present locale walking
  # Mobility.available_locales -- the exact order SlugGeneration already uses
  # to fill a blank slug (see its comment for why: a site set up in German
  # titles its pages only in German, and every other locale has to show
  # *something* rather than nothing).
  #
  # Mobility's own `fallbacks` plugin (config/initializers/mobility.rb) falls
  # back to a fixed I18n.default_locale (:en) -- correct for `config.i18n
  # .fallbacks`, wrong here: a `de`-default site has nothing in :en to fall
  # back to, and the plain reader would render blank. Passing an explicit
  # `fallback:` list (Mobility 1.3's per-read override, see
  # Mobility::Plugins::Fallbacks) bypasses the fixed default for this one
  # read without touching that global config.
  #
  # Every public view that shows a translated title/subtitle/excerpt/caption/
  # alt/meta field should read it through here rather than the plain Mobility
  # accessor. Does not apply to ActionText bodies (`Page`/`Post`/
  # `ContentBlock#body`) -- out of scope for this fix, see the fix's report.
  def translated(record, attribute)
    return nil if record.nil?

    record.public_send(attribute, fallback: translated_fallback_locales)
  end

  private

  def translated_fallback_locales
    default_locale = theme_site.default_locale.to_sym
    current_locale = I18n.locale.to_sym

    ([ default_locale ] + ::Mobility.available_locales.map(&:to_sym)).uniq - [ current_locale ]
  end
end
