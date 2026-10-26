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
  # ADDING A BLOCK TYPE (decision 18; block types spec, decisions 4 and 5)
  # is its declarations, not an entry here: `theme_methods` (its component's
  # line, which makes its template replaceable and `theme:new` copy it) and
  # `tokens` (its themed and fixed tokens), which `components`,
  # `themed_tokens` and `fixed_tokens` below read from `BlockTypes` on every
  # call. A derived list makes removing a name as easy as adding one, so the
  # built-in types' part is held by the ledger
  # (`test/values/theme/contract_ledger_test.rb`), the one hand list kept on
  # purpose. Content types are not part of this: their three components stay
  # written in POST_COMPONENTS. `test/values/theme/contract_test.rb` fails for
  # a component a type registry hands out that `components` does not hold,
  # and for a `--th-` token that tokens.css defines and no list names, each
  # with the missing entry in its message.
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
    # The shared ones, which no block type brings; a type's own follow them
    # in `themed_tokens`.
    SHARED_THEMED_TOKENS = %w[
      paper surface sunken ink dim meta line line-strong
      accent accent-hover accent-tint on-accent
      ok ok-ink ok-tint warn warn-ink warn-tint danger danger-ink danger-tint
      shadow-menu
      band-tinted band-strong on-band-strong on-band-strong-dim on-band-strong-accent
    ].freeze

    # Tokens with one value (the last block): type, tracking, spacing, shape.
    # The shared ones; a type's own follow them in `fixed_tokens`.
    SHARED_FIXED_TOKENS = %w[
      font mono
      t-display t-h1 t-h2 t-h3 t-body t-small t-label
      track-mono track-wide
      sp-1 sp-2 sp-3 sp-4 sp-5 sp-6 sp-7
      radius radius-pill ease
    ].freeze

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

    # The content types' components, written here: a content type declares
    # no line of its own (block types spec, "not part of this").
    POST_COMPONENTS = {
      "posts/blog_list_component" => %w[posts page],
      "posts/resume_list_component" => %w[posts page],
      "posts/now_list_component" => %w[posts page],
      "posts/detail_component" => %w[post]
    }.freeze

    def self.path_of(component) = component.name.underscore

    # Every component whose template a theme may replace, with the methods
    # it may call: each registered block type's line (its `theme_methods`),
    # in registration order, then the post components. Read on every call,
    # never kept in a constant: a constant is read when this file loads,
    # before `to_prepare` has registered anything.
    def self.components
      blocks = ::BlockTypes.all.filter_map do |definition|
        next unless definition.component

        path = path_of(definition.component)
        [ path, definition.theme_methods ]
      end
      blocks.to_h.merge(POST_COMPONENTS).freeze
    end

    def self.themed_tokens = SHARED_THEMED_TOKENS + ::BlockTypes.all.flat_map(&:themed_tokens)

    def self.fixed_tokens = SHARED_FIXED_TOKENS + ::BlockTypes.all.flat_map(&:fixed_tokens)

    def self.tokens = (themed_tokens + fixed_tokens).map { |name| "--th-#{name}" }

    # The default template a theme's `components/<path>.html.erb` replaces:
    # the CMS's own under `root`, else the registered type's component's
    # template (an engine's, beside its source).
    def self.template_for(path, root: Rails.root)
      file = Pathname(root).join("app/components/#{path}.html.erb")
      return file if file.file?

      definition = ::BlockTypes.all.find { |each| each.component && path_of(each.component) == path }
      definition&.component_template || file
    end

    # What every component's template may call beside its own methods
    # (`ApplicationComponent` delegates them to the view), and `helpers`,
    # through which the rest of HELPERS is reached.
    COMPONENT_HELPERS = %w[translated rich_text post_date resume_period post_url_path page_url_path render_block site_string helpers].freeze

    # What a page or layout template may call. `public_urls.preview?` is the
    # one question a template may ask of `public_urls`.
    HELPERS = %w[
      theme_site translated rich_text render_block block_outline published_views navigation_pages
      language_links safe_social_links home_url_path page_url_path post_url_path post_date resume_period
      page_found? page_ancestors page_section page_tree pages_in_reading_order neighbouring_pages with_heading_ids site_string
    ].freeze

    # What a rendered text is made of (spec §5): the elements, and the two
    # things a text embeds with their class names. How each looks is the
    # theme's; that it is this element is the CMS's (decision 12: a theme
    # styles a text and does not replace the HTML it is rendered to, so
    # `RichText::ImageComponent` and `YoutubeComponent` are not in `components`).
    RICH_TEXT = [
      "h2", "h3", "h4", "p", "ul", "ol", "li", "blockquote", "a", "strong", "em", "s", "code", "pre", "pre code", "hr", "br",
      "figure.content-block--image", "figure", "img", "figcaption",
      ".content-block--youtube-embed", ".youtube-embed__frame", "div", "iframe"
    ].freeze
  end
end
