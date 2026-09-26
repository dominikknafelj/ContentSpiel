# View helpers for the public default theme (spec §9). Everything the public
# layout shows comes from SiteSetting and the page tree, so editors' settings
# have a visible effect.
module ThemeHelper
  SAFE_LINK_SCHEMES = %w[http https mailto].freeze

  LanguageLink = Data.define(:code, :name, :path, :current)

  # Memoized under a theme-specific ivar: controllers (e.g. SetupController)
  # use @site_setting themselves.
  def theme_site
    @theme_site ||= SiteSetting.instance
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
end
