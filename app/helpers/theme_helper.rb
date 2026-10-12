# The view helpers of the public site, for the default theme and for a
# site's own alike: the ones `Theme::Contract::HELPERS` names are what a
# theme's template may call and are kept stable (theming spec §5 to §7);
# the rest are the CMS's own and say so. Everything the public layout shows
# comes from SiteSetting and the page tree, so editors' settings have a
# visible effect.
module ThemeHelper
  LanguageLink = Data.define(:code, :name, :path, :current)

  # A heading of an article as `with_heading_ids` lists it.
  Heading = Data.define(:id, :text, :level) do
    # What is taken out of a heading's words before anything else: the
    # characters nobody sees. Format characters (a zero-width joiner or
    # space, a soft hyphen), the variation selectors (what makes "⚠" the
    # coloured sign) and the marks that combine with a SYMBOL (the keycap of
    # "1️⃣"). Ruby counts the last two as marks, and a mark is kept below.
    UNSEEN = /[\p{Cf}\u{FE00}-\u{FE0F}\u{20D0}-\u{20FF}\u{E0100}-\u{E01EF}]/

    # The id a heading's words give, before a number makes it unique. For
    # Latin text it is what `parameterize` answers ("Über uns" is
    # "uber-uns"). For every other script it is the words themselves, lower
    # case, with a hyphen for each run of anything that is not a letter, a
    # mark or a digit: `parameterize` alone answers nothing for Greek, Arabic
    # or Japanese, and a page in one of them would get "section",
    # "section-2", … , ids that follow a heading's PLACE and move when a
    # heading is added above it. A Latin letter the transliteration does not
    # know (Vietnamese "ư") loses its marks and stays a letter, where
    # `parameterize` would put a hyphen in the middle of the word; only a
    # letter that is not ASCII is asked of it (a rule lookup each). A mark
    # stays where it follows a letter or a digit (Hindi, Thai and Arabic
    # are written with them) and nowhere else, so an id never starts with a
    # character nobody can see or type: "⚠️ Warning" is "warning". HTML
    # takes any character but a space in an id, and a browser encodes the
    # link to it. "" when the words hold no letter and no digit.
    def self.id_from(words)
      words.to_s.unicode_normalize(:nfc).gsub(UNSEEN, "")
        .gsub(/(?=\P{ASCII})\p{Latin}/) { |letter| ActiveSupport::Inflector.transliterate(letter, "").presence || letter.unicode_normalize(:nfd).gsub(/\p{M}/, "") }
        .gsub(/(?<![\p{L}\p{N}\p{M}])\p{M}+/, "")
        .downcase.gsub(/[^\p{L}\p{M}\p{N}_]+/, "-").gsub(/\A-+|-+\z/, "")
    end

    # A heading's words as read: its text, a space for each line break in it.
    def self.words_of(node)
      node.xpath(".//text() | .//br").map { |part| part.name == "br" ? " " : part.text }.join.squish
    end
  end

  # The elements whose headings are not the article's own
  # (`with_heading_ids`). A list item is the sixth and is not on this list,
  # because it is not always one: `template_item?`.
  NOT_THE_ARTICLE = %w[nav aside header footer a].freeze
  OUTSIDE_THE_ARTICLE = NOT_THE_ARTICLE.map { |name| "ancestor::#{name}" }.join(" | ").freeze

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

    @theme_root_page = Page.find_by(parent_id: nil) # public: rows (only its address and its children are read; a title goes through published_views)
  end

  # Other records a page shows by their title, as a visitor sees them: each
  # as published (`Publishing.published_all`, one statement per record type).
  # The preview shows the rows. The CALLER narrows first, on the rows
  # (`kept.published`): whether a record is shown at all is not in a copy.
  def published_views(records)
    public_urls.preview? ? records.to_a : Publishing.published_all(records)
  end

  # Memoised for the render: a theme may draw the menu more than once (a
  # header, a drawer for narrow screens, a footer).
  def navigation_pages
    return @navigation_pages if defined?(@navigation_pages)

    @navigation_pages = theme_root_page ? published_views(theme_root_page.children.kept.published) : [] # public: rows (the menu's membership and order are the rows' (the tree); titles come from published_views)
  end

  def home_url_path
    theme_root_page ? page_url_path(theme_root_page) : "/"
  end

  # --- The page tree and the article, for a theme (theming spec §7) ---------
  #
  # Read-only, and as the public sees it: every page these answer is kept
  # and published, and every title comes from the page's copy
  # (`PublicSite::Branch`). Each is read once per render, however often a
  # template asks. "The shown page" is the page the controller resolved
  # (`@page`), never the request's path: a public page is one answer for
  # every visitor, and nothing here asks who is asking.
  #
  # WHAT A TEMPLATE GETS IS A NODE, NEVER A PAGE (`PublicSite::Branch::Node`:
  # `id`, `title`, `subtitle`, `slug`, `path`, `depth`, `children`,
  # `current?`, `open?`, `leaf?`): a value with nothing to walk rows from.
  #
  # NONE RAISES, AND A 404 IS NOWHERE. With no page (`nil`), and on every
  # answer that says "not found", each answers empty: no pages above, no
  # section, no tree, no neighbours. A 404 can have a page in hand
  # (`PublicPageRendering#assign_record`: a post whose list is gone; in the
  # preview a post on a page the editor may not read), and a 404 says
  # nothing of a record. So a frame may ask for the section on every page
  # without a condition of its own.

  # Whether a page is being shown: there is one, and the answer is not a
  # 404. What a frame or a partial asks before it draws something OF the
  # page (its title in a bar, its crumbs); the helpers below ask it
  # themselves.
  def page_found? = @page.present? && !not_found_answer?

  # The pages above `page`, the homepage first, as nodes. Empty for the
  # homepage. A page above that is not published is left out (only a preview
  # can show a page under one). The homepage's node has no `children` (its
  # branch is the whole site: `page_tree` reads it); the others are the
  # nodes of the section's tree.
  def page_ancestors(page) = page_surroundings(page).above

  # The page's branch directly under the homepage, as the node of its tree
  # with `page` marked: for /editors/pages/x it is /editors with everything
  # under it, and a page directly under the homepage is its own. nil for the
  # homepage, and when the section is not shown (the homepage or the page
  # under it is unpublished or in the trash, which only a preview can meet).
  # `page_tree(page_section(page))` is this same node and reads nothing.
  def page_section(page) = page_surroundings(page).section

  # The branch under and including `top` (a node, or a page), to any depth,
  # as nested nodes. nil when `top` is nil or not shown.
  def page_tree(top, current: (@page if page_found?))
    return nil if !in_the_tree?(top) || not_found_answer?

    current = nil unless in_the_tree?(current)
    @page_trees ||= {}
    key = [ top.id, current&.id ]
    @page_trees.fetch(key) { @page_trees[key] = page_branch.under(top, current: current) }
  end

  # A branch flattened in reading order: a page, then its subpages, each
  # followed by its own.
  def pages_in_reading_order(node) = node ? node.reading_order : []

  # [previous, next] of the shown page within `tree`, as nodes or nil.
  # `skip` is a callable that says which pages the walk passes over (a theme
  # hands in "the pages that only group others", so next after the last page
  # of a group is the first page of the next); the shown page is never
  # skipped.
  def neighbouring_pages(tree, skip: nil)
    walk = pages_in_reading_order(tree).reject { |node| !node.current? && skip&.call(node) }
    index = walk.index(&:current?) or return [ nil, nil ]

    [ (walk[index - 1] if index.positive?), walk[index + 1] ]
  end

  # The rendered blocks of a page with an id on each heading of `levels`,
  # and those headings as `id`, `text`, `level`: what a table of contents
  # and a link to a heading need.
  #
  # Made on the RENDERED page, from each heading's words, not stored in the
  # document (decision 17): an id must be unique on the whole page, and a
  # page's text is several blocks, each rendered and cached alone. So an id
  # follows its heading's words (`Heading.id_from`): REWORDING A HEADING
  # CHANGES ITS ID, and a link to it from elsewhere then opens the page at
  # its top. A number is added when two are alike, and a heading with no
  # letter and no digit in it is "section", numbered like any other. A line
  # break in a heading is a space. An id a heading already has is kept.
  #
  # THE ARTICLE is what the template hands in, less the pieces that list or
  # link OTHER content or are the page's furniture: a heading inside `nav`,
  # `aside`, `header`, `footer` or a link is not a heading of this text (a
  # card that is one link) and is neither listed nor given an id
  # (`NOT_THE_ARTICLE`). Nor is one inside a list item A TEMPLATE WROTE (a
  # post list's titles). One inside a list item of a RENDERED TEXT is: a
  # list item of a text holds blocks, an author may write a heading in one,
  # and spec §7 gives each heading of the text an id (`template_item?`). A
  # post's own text, which its template wraps in `article`, and a text in a
  # section's column are the article's too. The cost is one more parse of
  # the article for a request that is not a 304, paid only by a template
  # that calls this.
  #
  # AFTER THE RENDER CACHE, NEVER IN IT: a body is cached by its document's
  # digest and is the same HTML in CS Studio's preview and in the MCP
  # server's Markdown round trip (spec §5), so the ids are put on a copy of
  # what `rich_text` answered and the cached render never holds one
  # (`test/integration/theme_pages_test.rb`: "heading ids are on the page a
  # theme draws and not in the cached render of the text").
  #
  # `html_safe` on the way out, so what comes in is made safe first: rendered
  # blocks (a `capture`) already are and pass as they are, anything else is
  # escaped, or this would be the way to print a title as markup. The parse
  # adds one attribute, made of letters, marks, digits, "-" and "_", which
  # the serialiser quotes. A text with no heading of `levels` is handed back
  # as it came, unparsed where it holds no heading at all.
  def with_heading_ids(html, levels: 2..3)
    html = html.to_s
    html = ERB::Util.html_escape(html) unless html.html_safe?
    return [ html, [] ] unless html.include?("<h")

    fragment = Nokogiri::HTML5.fragment(html)
    nodes = fragment.css(levels.map { |level| "h#{level}" }.join(", ")).reject { |node| node.at_xpath(OUTSIDE_THE_ARTICLE) }
    nodes = nodes.reject { |node| template_item?(node) } # before an id is put on anything: an item is known by its markup
    return [ html, [] ] if nodes.empty?

    taken = fragment.css("[id]").map { |node| node["id"] }.to_set
    headings = nodes.map do |node|
      id = node["id"].presence || begin
        base = Heading.id_from(Heading.words_of(node)).presence || "section"
        candidate = base
        number = 1
        candidate = "#{base}-#{number += 1}" while taken.include?(candidate)
        taken << candidate
        node["id"] = candidate
      end
      Heading.new(id: id, text: Heading.words_of(node), level: node.name.delete_prefix("h").to_i)
    end

    [ fragment.to_html.html_safe, headings ]
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
  #
  # A text that holds a heading and a list is remembered for the render:
  # `with_heading_ids` asks whether a list item is a text's own
  # (`template_item?`).
  def rich_text(record)
    ::Locales.read(record, :body).to_html(locale: I18n.locale, urls: public_urls).tap do |html|
      (@texts_with_items ||= []) << html if html.include?("<li") && html.include?("<h")
    end
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

  # Whether a heading is in a list item that is NOT a rendered text's: a
  # template's own (`<li><h3>` of a post list). The CMS's own, for
  # `with_heading_ids`.
  #
  # HOW A TEXT'S ITEM IS KNOWN. A rendered text has no wrapper of the CMS's
  # (the element and the class around it are the theme's, decision 12), so
  # nothing in the article's markup says where a text begins. What is known
  # is what `rich_text` answered during this render: an item of the article
  # is a text's own when it is, tag for tag, an item of one of those texts
  # (both read by the same parser and written by the same serialiser). A
  # template's item is taken for a text's only when it is the same markup
  # as an item an author wrote on this page, heading and all. A text that
  # did not come through `rich_text` in this render (a string a template
  # built itself) is not known, and its items are a template's.
  def template_item?(heading)
    item = heading.at_xpath("ancestor::li[1]") or return false # the nearest one

    @items_of_texts ||= {}
    known = (@texts_with_items || []).flat_map do |text|
      @items_of_texts[text] ||= Nokogiri::HTML5.fragment(text).css("li").select { |li| li.at_css("h1, h2, h3, h4, h5, h6") }.map(&:to_html)
    end
    !known.include?(item.to_html)
  end

  # One `PublicSite::Branch` per render, on this request's urls and language.
  # The CMS's own: not in `Theme::Contract::HELPERS`, a template asks the
  # helpers above.
  def page_branch
    @page_branch ||= PublicSite::Branch.new(urls: public_urls, locale: I18n.locale)
  end

  # The pages above a page and its section, read together (four statements
  # whatever the section's size) and once per page per render. The section
  # is its tree, so `page_tree` of it is remembered here. The CMS's own.
  def page_surroundings(page)
    return PublicSite::Branch::NOWHERE if !in_the_tree?(page) || not_found_answer?

    @page_surroundings ||= {}
    @page_surroundings.fetch(page.id) do
      around = page_branch.around(page)
      (@page_trees ||= {})[[ around.section.id, page.id ]] ||= around.section if around.section
      @page_surroundings[page.id] = around
    end
  end

  # What a tree helper can be asked about: a page or a node, and nothing
  # else (`PublicSite::Branch.in_the_tree?`). The answers are remembered by
  # an id, and a post's id is some page's: `page_ancestors(@post || @page)`,
  # which is how `language_links` is called, would otherwise answer the
  # crumbs of the page with the post's number. The CMS's own.
  def in_the_tree?(thing) = PublicSite::Branch.in_the_tree?(thing)

  # The answer says "not found". The CMS's own: a template asks
  # `page_found?`.
  def not_found_answer? = response.not_found?
end
