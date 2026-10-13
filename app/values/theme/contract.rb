class Theme
  # THE THEME CONTRACT (theming spec §7): the names a theme outside this
  # repository may rely on. Everything on these lists is stable: the CMS says
  # in its release notes when one changes. Everything that is not may change
  # freely, and a theme that uses it is on its own.
  #
  # One list, read by all of: the check when the application starts
  # (`Theme::Check`), `bin/rails theme:check`, `bin/rails theme:new`
  # (`Theme::Scaffold`), the tests (`test/values/theme/contract_test.rb`) and
  # the reference file (`docs/reference/theming.md`, which a test holds to
  # this file).
  #
  # ADDING A BLOCK TYPE (decision 18) is one entry here per thing it brings:
  # its component's line in COMPONENTS, which makes its template replaceable
  # and `theme:new` copy it, and its tokens' lines in THEMED_TOKENS or
  # FIXED_TOKENS. Nothing else in the mechanism names a block, and the type
  # cannot be added without them: `test/values/theme/contract_test.rb` fails
  # for a component a type registry hands out that COMPONENTS does not hold
  # ("a block type registered with a component the list does not hold fails,
  # and the message names the missing entry") and for a `--th-` token that
  # tokens.css defines and no list names, each with the missing entry in its
  # message.
  #
  # The lists are data and name no class: a component is written as its path
  # (`blocks/image_component`), which is also where a theme puts its
  # template, so this value knows no component
  # (`test/lib/dependency_direction_test.rb`).
  module Contract
    # Tokens with a value for the light scheme and one for the dark
    # (`app/assets/tailwind/themes/default/tokens.css`, the first two
    # blocks), without the `--th-` prefix. A theme changes one by declaring
    # it again in its own stylesheet, under the same selectors.
    #
    # The last seven are the Code block's syntax colours, one per role of
    # `CodeHighlight::ROLES` and in its order (the highlighter is not named
    # here: `test/values/theme/contract_test.rb` holds the two together).
    THEMED_TOKENS = %w[
      paper surface sunken ink dim meta line line-strong
      accent accent-hover accent-tint on-accent
      ok ok-ink ok-tint warn warn-ink warn-tint danger danger-ink danger-tint
      shadow-menu
      band-tinted band-strong on-band-strong on-band-strong-dim on-band-strong-accent
      syn-comment syn-keyword syn-string syn-constant syn-tag syn-attribute syn-embed
    ].freeze

    # Tokens with one value (the last block): type, tracking, spacing, shape.
    FIXED_TOKENS = %w[
      font mono
      t-display t-h1 t-h2 t-h3 t-body t-small t-label
      track-mono track-wide
      sp-1 sp-2 sp-3 sp-4 sp-5 sp-6 sp-7
      radius radius-pill ease
    ].freeze

    TOKENS = (THEMED_TOKENS + FIXED_TOKENS).map { |name| "--th-#{name}" }.freeze

    # The CMS's own under the same prefix, and not a theme's to rely on: the
    # preview bar's two colours and the image placeholder's two.
    OWN_TOKENS = /\A--th-(?:preview|ph)-/

    # The templates a theme may replace through its `views/` folder, by
    # their path under it, with what each is. The default is the file of the
    # same path under app/views.
    TEMPLATES = {
      "layouts/public/_frame.html.erb" => "everything inside <body> but the preview bar; `yield` is the page",
      "layouts/public/_title.html.erb" => "the pattern of the page title; locals `page_title` (nil on the homepage and a 404) and `site_title`",
      "layouts/public/_icons.html.erb" => "the favicon and the touch icon links",
      "layouts/public/_head.html.erb" => "the theme's own head tags, after the CMS's and before the stylesheet",
      "layouts/public/_header.html.erb" => "the site's header: its title, logo and menu",
      "layouts/public/_footer.html.erb" => "the site's footer: the copyright line, the social links, the light/dark switch",
      "layouts/public/_language_switcher.html.erb" => "the links to the shown page in the other languages",
      "layouts/public/_theme_toggle.html.erb" => "the light/dark switch; its script is the CMS's `theme` controller",
      "pages/show.html.erb" => "a page: its heading, hero and blocks, and the list of its subpages",
      "pages/not_found.html.erb" => "the page for an address that is nobody's"
    }.freeze

    # A theme's own partials, under any name: `views/theme/_anything.html.erb`,
    # rendered as `render "theme/anything"`.
    OWN_PARTIALS = "theme/".freeze

    # The components whose template a theme may replace through its
    # `components/` folder, by the component's path, with the methods its
    # template may call. A method not listed is the CMS's to change.
    COMPONENTS = {
      "blocks/rich_text_component" => %w[block page],
      "blocks/image_component" => %w[block page asset alt caption sizes],
      # `lines` is one array per line of [role, text] pairs, the role nil or
      # one of the seven a `syn-` token exists for; `string(key)` is one of
      # the copy button's four words (:copy, :copy_code, :copied, :failed) in
      # the visitor's language, and of nothing else. When the bar around the
      # copy button is the script's to show, and the id of the file name's
      # element, are a template's own layout and no method: the default
      # template writes both out from these names. The markup the copy script
      # asks of any template is in docs/reference/theming.md, "The Code block".
      "blocks/code_component" => %w[block page lines code language language_label filename caption string],
      "blocks/post_list_component" => %w[block page list_component],
      "blocks/section_component" => %w[block page columns layout background width],
      "posts/blog_list_component" => %w[posts page],
      "posts/resume_list_component" => %w[posts page],
      "posts/now_list_component" => %w[posts page],
      "posts/detail_component" => %w[post]
    }.freeze

    # What every component's template may call beside its own methods
    # (`ApplicationComponent` delegates them to the view), and `helpers`,
    # through which the rest of HELPERS is reached.
    COMPONENT_HELPERS = %w[translated rich_text post_date resume_period post_url_path page_url_path render_block helpers].freeze

    # What a page or layout template may call. `public_urls.preview?` is the
    # one question a template may ask of `public_urls`.
    HELPERS = %w[
      theme_site translated rich_text render_block block_outline published_views navigation_pages
      language_links safe_social_links home_url_path page_url_path post_url_path post_date resume_period
      page_found? page_ancestors page_section page_tree pages_in_reading_order neighbouring_pages with_heading_ids
    ].freeze

    # What a rendered text is made of (spec §5): the elements, and the two
    # things a text embeds with their class names. How each looks is the
    # theme's; that it is this element is the CMS's (decision 12: a theme
    # styles a text and does not replace the HTML it is rendered to, so
    # `RichText::ImageComponent` and `YoutubeComponent` are not in COMPONENTS).
    RICH_TEXT = [
      "h2", "h3", "h4", "p", "ul", "ol", "li", "blockquote", "a", "strong", "em", "s", "code", "pre", "pre code", "hr", "br",
      "figure.content-block--image", "figure", "img", "figcaption",
      ".content-block--youtube-embed", ".youtube-embed__frame", "div", "iframe"
    ].freeze
  end
end
