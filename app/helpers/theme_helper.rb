# View helpers for the public default theme (spec §9). Everything the public
# layout shows comes from SiteSetting and the page tree, so editors' settings
# have a visible effect.
module ThemeHelper
  LanguageLink = Data.define(:code, :name, :path, :current)

  # Current.site memoizes itself for the process/request; no ivar of our own
  # needed the way SetupController's @site_setting is.
  def theme_site
    Current.site
  end

  # Social links become real hrefs here for the first time, so only
  # http/https/mailto URLs render -- a `javascript:` link must never reach
  # the page. SiteSetting already refuses one on save
  # (`SiteSetting.safe_social_link?`); this is the same rule again for a row
  # written around its validations.
  def safe_social_links
    theme_site.social_links.to_h.select { |_name, url| SiteSetting.safe_social_link?(url) }
  end

  def theme_root_page
    return @theme_root_page if defined?(@theme_root_page)

    @theme_root_page = Page.find_by(parent_id: nil)
  end

  def navigation_pages
    theme_root_page ? theme_root_page.children.kept.published.to_a : []
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
  # excerpt, caption, alt, meta fields. The fallback order itself lives
  # entirely in `Locales.fallback_chain`, so this is a thin wrapper -- kept
  # as the call sites' entry point rather than inlined, so every public view
  # keeps reading translated copy through one helper. Rich-text bodies go
  # through `#rich_text` below instead, which also renders them.
  def translated(record, attribute)
    ::Locales.read(record, attribute)
  end

  # A record's rich-text body (tiptap spec §4.3), rendered to scrubbed HTML:
  # `Locales.read(record, :body)` picks the first non-blank language's
  # `RichText::Document` (a body left blank in German falls back exactly
  # like a blank title), and `to_html` renders it for the *request's*
  # locale -- even when the document itself came from a fallback language,
  # an internal link should still point at the German page on a German
  # URL. `urls:` is the controller's own `public_urls`, so `/preview`
  # renders internal links under `/preview` and the public site doesn't.
  def rich_text(record)
    ::Locales.read(record, :body).to_html(locale: I18n.locale, urls: public_urls)
  end
  # One block of a page, rendered: its registered type's ViewComponent
  # (`Theme.current.component_for`, open-types spec §5), not a partial named
  # after `block_type` -- the registry is what a plugin's block type or an
  # alternate theme hooks into. A helper rather than a loop in
  # `pages/show.html.erb` because a section draws the blocks in its columns
  # the same way (`Blocks::SectionComponent`), and both must agree on the two
  # exceptions below wherever a block sits.
  #
  # A post detail request (`/en/blog/my-post`): the block the controller
  # matched the post under renders that single post, through its content
  # type's `detail_component`, in place of its listing, while the page's
  # other blocks still render around it. Compared against `@post_list_block`
  # -- the block the controller resolved the post under -- rather than the
  # block's type, so that a page carrying more than one listing swaps out
  # only that block.
  #
  # A stored `block_type` that isn't (or is no longer) registered --
  # `block.definition` is nil -- renders nothing rather than 500ing the
  # public site (global constraints): a removed plugin's type must degrade
  # gracefully for whoever already has it on a page.
  #
  # With one thing more for a SECTION whose type is gone: the blocks in it
  # are ordinary blocks of types that are still here, and only the section
  # knew how to arrange them. Rendering nothing would take a page's texts
  # and pictures off the site because their wrapper's plugin was removed, so
  # they are drawn where the section was, once each, in reading order
  # (column by column), with no band and no grid. Once each because they are
  # not top-level blocks: the page walks `BlockOutline#top_level` and nothing
  # else reaches them. CS Studio shows the same section as an "Unavailable
  # type" card with its blocks listed under it (sections spec §6). A gone
  # block that holds nothing has an empty list here, which is the old rule.
  def render_block(block)
    if @post && block == @post_list_block
      definition = @post.definition
      render Theme.current.component_for(definition, :detail_component).new(post: @post) if definition
    elsif (definition = block.definition)
      render Theme.current.component_for(definition).new(block: block, page: @page)
    else
      Rails.logger.warn("Skipping block #{block.id}: unregistered block type #{block.block_type.inspect}")
      safe_join(block_outline(@page).blocks_in(block).map { |inner| render_block(inner) }) if @page
    end
  end

  # The page's blocks as an outline (`BlockOutline`: what is top-level, what
  # sits in which column of which section), built once per page per render.
  # `pages/show.html.erb` walks its top level, each `Blocks::SectionComponent`
  # asks it for its columns, and `render_block` for the blocks of a section
  # whose type is gone -- all through this, because building one sorts and
  # groups every block of the page. Kept on the view, never on the page: an
  # outline is a snapshot of the blocks as loaded, and a view lives exactly
  # as long as one render does.
  #
  # For a post's permalink the page's outline is already here when the view
  # starts: `PublicPageRendering#assign_record` built it to find which
  # listing the post stands in for, and assigned it to this same variable
  # (a controller's instance variables are copied to its view). Renaming
  # the variable here means renaming it there
  # (`test/integration/public_blocks_test.rb`, "a post's permalink builds
  # one outline, the one its page is drawn from").
  def block_outline(page)
    @block_outlines ||= {}
    @block_outlines[page] ||= BlockOutline.new(page.content_blocks)
  end
end
