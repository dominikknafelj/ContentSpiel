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
  # `post.fields` casts `start_date`/`end_date` to `Date` (or nil) now that
  # they live in the `resume_entry` content type's own field schema rather
  # than as plain ISO-string `store_accessor`s.
  def resume_period(post)
    fields = post.fields
    start_year = fields.start_date&.year
    end_year = fields.end_date&.year || "now"
    start_year ? "#{start_year} – #{end_year}" : end_year
  end

  # The record currently shown -- a page, or at a permalink the post itself
  # -- in each enabled locale that has a path for it. Callers pass
  # `@post || @page`: a post's own path already carries its canonical page's
  # segments (`PublicSite::Paths#post_path`), so nothing here needs to know
  # which kind of record it has.
  def language_links(record)
    return [] if record.nil?

    ::Locales.enabled.filter_map do |code|
      path = public_urls.path_for(record, code) or next
      LanguageLink.new(code:, name: ::Locales.name(code, native: true), path:, current: code == I18n.locale.to_s)
    end
  end

  # Reads a translated attribute for the public theme -- title, subtitle,
  # excerpt, caption, alt, meta fields, and (since this task) ActionText
  # bodies too, since a rich text block left blank in German has exactly the
  # same "renders nothing" failure mode as a blank title. The fallback order
  # itself now lives entirely in `Locales.fallback_chain`, so this is a thin
  # wrapper -- kept as the call sites' entry point rather than inlined, so
  # every public view keeps reading translated copy through one helper.
  def translated(record, attribute)
    ::Locales.read(record, attribute)
  end
end
