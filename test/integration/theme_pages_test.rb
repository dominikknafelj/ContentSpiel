require "test_helper"

# A page under the second theme (theming spec §2 and "Testing"): the theme's
# frame, page template and block template; the default theme's header, image
# block and 404 where the theme holds none; and the CMS's head whatever the
# theme does.
class ThemePagesTest < ActionDispatch::IntegrationTest
  # What the CMS writes into <head> and a theme cannot remove (spec §2), in
  # two groups by where the layout prints them: ahead of the theme's own
  # tags (`layouts/public/_icons`, `_head`) and after them. Each is there
  # EXACTLY ONCE as the CMS's own. The CSP tag is `meta[name=csp-nonce]`,
  # which is what `csp_meta_tag` prints.
  CMS_HEAD_BEFORE_THEME = [
    "title", "meta[name=viewport]", "meta[name=csp-nonce]", "script:not([type])",
    "meta[property='og:title']", "meta[property='og:type']", "meta[property='og:url']", "meta[property='og:locale']",
    "link[rel=canonical]", "link[rel=alternate][hreflang=en]", "link[rel=alternate][hreflang=x-default]"
  ].freeze
  CMS_HEAD_AFTER_THEME = [ "link[rel=stylesheet]", "script[type=importmap]" ].freeze

  # A `_head` that prints tags that are the CMS's to print, behind a marker
  # that says where the theme's part of the head starts.
  GREEDY_HEAD = <<~ERB.freeze
    <meta name="theme-head-starts">
    <link rel="canonical" href="https://elsewhere.example/not-this-page">
    <%= csp_meta_tag %>
    <meta name="csrf-token" content="a-theme-wrote-this">
  ERB

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    SiteSetting.instance.update!(title: "Dana's Notes")
    @home = root_page
    @about = create_page(title: "About")
    result = ContentBlocks::Save.call(ContentBlock.new(owner: @about), attributes: { block_type: "rich_text" },
      translations: { "en" => { body: rich_doc("Words of the about page") } })
    assert result.ok?, result.errors.to_sentence
    publish_changes(@about)
  end

  def head = Nokogiri::HTML5(response.body).at_css("head")

  test "a page under the second theme has the theme's frame, page template and rich-text wrapper, and the default header and footer" do
    with_plain_theme { get "/about" }

    assert_response :success
    assert_select "body > div.plain-frame > main.plain-main > article.plain-page h1", text: "About"
    assert_select "article.plain-page div.plain-text", text: "Words of the about page"
    assert_select ".cs-prose", count: 0
    assert_select "p.plain-crumb a[href='/']", text: "Dana's Notes"
    assert_select "div.plain-frame > header nav[aria-label=Main] a[href='/about']", text: "About"
    assert_select "div.plain-frame > footer [data-controller=theme]"
  end

  test "the default theme draws the same page with its own frame and wrapper" do
    get "/about"

    assert_response :success
    assert_select "body > div > main h1", text: "About"
    assert_select "div.cs-prose", text: "Words of the about page"
    assert_select ".plain-frame, .plain-text, .plain-page", count: 0
  end

  # The elements of <head> in the order they are printed, cut where the
  # theme's part starts: at the first tag `_icons` prints (the default
  # theme's and the second theme's start with a `link[rel=icon]`) or at the
  # greedy theme's marker.
  def head_parts(cut)
    elements = head.element_children.to_a
    at = elements.index { |element| element.matches?(cut) } or flunk "the head has no #{cut}"
    [ fragment(elements[0...at]), fragment(elements[at..]) ]
  end

  def fragment(elements) = Nokogiri::HTML5.fragment(elements.map(&:to_html).join)

  def assert_cms_head(before, whole, theme)
    CMS_HEAD_BEFORE_THEME.each do |selector|
      assert_equal 1, before.css(selector).size, "#{theme}: #{selector} is not there exactly once ahead of the theme's own tags"
    end
    CMS_HEAD_AFTER_THEME.each do |selector|
      assert_equal 1, whole.css(selector).size, "#{theme}: #{selector} is not there exactly once"
    end
    assert_includes before.at_css("script:not([type])").text, 'localStorage.getItem("cs-theme")'
    assert_nil before.at_css("meta[name=csrf-token]"), "#{theme}: the CMS wrote a CSRF token on a public page"
  end

  test "every tag the CMS writes into the head is there exactly once under both themes, ahead of the theme's own" do
    get "/about"
    default_before, default_after = head_parts("link[rel=icon]")
    assert_cms_head default_before, head, "the default theme"

    with_plain_theme { get "/about" }
    themed_before, themed_after = head_parts("link[rel=icon]")
    assert_cms_head themed_before, head, "the second theme"

    described = "meta[property^='og:'], link[rel=canonical], link[rel=alternate]"
    assert_equal default_before.css(described).map(&:to_html), themed_before.css(described).map(&:to_html)
    [ default_after, themed_after ].each do |theme_part|
      assert_empty theme_part.css("title, meta[name=viewport], meta[name=csp-nonce], link[rel=canonical], link[rel=alternate], meta[property^='og:'], meta[name=csrf-token]").map(&:to_html)
    end
  end

  # The rule (spec §2): a theme cannot REMOVE or REPLACE a tag of the CMS's,
  # because each is a line of the layout and none of a replaceable template.
  # Nothing in the rendering stops a theme's `_head` from printing more
  # markup, a tag of the same name included: what holds is that the CMS's
  # own is there once, unchanged, and FIRST, ahead of everything the theme
  # prints. Refusing a `_head` that names such a tag is the contract check's
  # (Task 4), not the renderer's.
  test "a theme whose head prints a canonical link, a CSP tag and a CSRF tag of its own takes none of the CMS's away: each is there once, unchanged and first" do
    get "/about"
    default_before, = head_parts("link[rel=icon]")

    with_theme_copy do |dir|
      dir.join("views/layouts/public/_icons.html.erb").write("")
      dir.join("views/layouts/public/_head.html.erb").write(GREEDY_HEAD)
      Theme.with(Theme.new(path: dir)) { get "/about" }
    end
    before, after = head_parts("meta[name=theme-head-starts]")

    assert_cms_head before, head, "the greedy theme"
    assert_equal "http://www.example.com/about", before.at_css("link[rel=canonical]")["href"]
    assert_equal default_before.css("meta, link").map(&:to_html), before.css("meta, link").map(&:to_html)
    # What the theme printed is on the page, after the CMS's: it is extra
    # markup, which only the contract check can refuse.
    assert_equal [ "https://elsewhere.example/not-this-page" ], after.css("link[rel=canonical]").map { |link| link["href"] }
    assert_equal 1, after.css("meta[name=csp-nonce]").size
    assert_equal 1, after.css("meta[name=csrf-token]").size
    assert_equal 2, head.css("link[rel=canonical]").size
  end

  # `content_for` appends: a second write to the title's slot would be put
  # behind the first, and <title> would read "HijackAbout – Site".
  test "a theme's template that writes to the title's slot changes no title: on a page, on a 404 and with a meta title" do
    with_theme_copy do |dir|
      dir.join("views/pages/show.html.erb").write(%(<% content_for :title, "Hijack" %><article class="plain-page"></article>\n))
      dir.join("views/pages/not_found.html.erb").write(%(<% content_for :title, "Hijack" %><p>Nothing here</p>\n))
      dir.join("views/layouts/public/_frame.html.erb").write(%(<% content_for :title, "Hijack" %><main><%= yield %></main>\n))

      Theme.with(Theme.new(path: dir)) do
        get "/about"
        assert_select "article.plain-page"
        assert_includes response.body, "<title>Dana&#39;s Notes | About</title>"

        get "/no-such-page"
        assert_response :not_found
        assert_select "p", text: "Nothing here"
        assert_includes response.body, "<title>Dana&#39;s Notes</title>"

        assert Pages::Save.call(@about, translations: { "en" => { meta_title: "About us" } }).ok?
        publish_changes(@about)
        get "/about"
        assert_includes response.body, "<title>About us</title>"
      end
    end
  end

  # The head's slot is not a theme's either, for the reason the title's is
  # not: `content_for` appends, so a page or block template that wrote to
  # `:head` would put its tags in the middle of the CMS's part of the head,
  # ahead of the description and the Open Graph tags (and on a 404, alone
  # there). The layout reads no slot: it prints the CMS's tags itself. A
  # theme's own head tags are `layouts/public/_head`, and the folder check
  # refuses a template that writes to the slot
  # (`test/values/theme/check_test.rb`), which is why this folder is handed
  # to `Theme.new`, which checks nothing: what is shown here is that the
  # rendering holds without the check.
  test "a theme's template that writes to the head's slot puts nothing into the head: on a page, in a block and on a 404" do
    with_theme_copy do |dir|
      slot = ->(name) { "<% content_for :head do %><meta name=\"slot-#{name}\" content=\"x\"><link rel=\"canonical\" href=\"https://elsewhere.example/\"><% end %>\n" }
      dir.join("views/pages/show.html.erb").write(slot.("page") + dir.join("views/pages/show.html.erb").read)
      dir.join("views/pages/not_found.html.erb").write(slot.("missing") + "<h1>Nothing here</h1>\n")
      dir.join("views/layouts/public/_frame.html.erb").write(slot.("frame") + "<main><%= yield %></main>\n")
      dir.join("components/blocks/rich_text_component.html.erb").write(slot.("block") + "<div class=\"plain-text\"><%= rich_text(block) %></div>\n")

      Theme.with(Theme.new(path: dir)) do
        get "/about"
        assert_response :success
        assert_select "div.plain-text", minimum: 1
        assert_no_match(/slot-|elsewhere\.example/, response.body)
        assert_select "head meta[property='og:title'][content='About']", count: 1
        assert_select "head meta[property='og:url']", count: 1
        assert_select "head link[rel=canonical]", count: 1

        get "/no-such-page"
        assert_response :not_found
        assert_select "h1", text: "Nothing here"
        assert_no_match(/slot-|elsewhere\.example/, response.body)
      end
    end
  end

  test "an empty theme draws the homepage as the default theme does" do
    get "/"
    default = response.body

    Dir.mktmpdir("theme") do |dir|
      Theme.with(Theme.load(ThemeFolder.new(dir))) { get "/" }
    end

    assert_response :success
    assert_equal default, response.body
  end

  test "the title is the theme's pattern on one line, escaped once" do
    with_plain_theme do
      get "/about"
      assert_includes response.body, "<title>Dana&#39;s Notes | About</title>"

      get "/"
      assert_includes response.body, "<title>Dana&#39;s Notes</title>"

      get "/no-such-page"
      assert_response :not_found
      assert_includes response.body, "<title>Dana&#39;s Notes</title>"
    end

    get "/about"
    assert_includes response.body, "<title>About – Dana&#39;s Notes</title>"
    get "/no-such-page"
    assert_includes response.body, "<title>Dana&#39;s Notes</title>"
  end

  test "a meta title an editor typed is taken as written, whatever the theme's pattern" do
    assert Pages::Save.call(@about, translations: { "en" => { meta_title: "About us & them" } }).ok?
    publish_changes(@about)

    with_plain_theme { get "/about" }

    assert_includes response.body, "<title>About us &amp; them</title>"
  end

  test "the icons and the theme's own head tags are the theme's, and the default theme keeps its own" do
    with_plain_theme { get "/about" }

    assert_select "head link[rel=icon][href*='plain-mark']", count: 1
    assert_select "head link[rel=icon][href='/icon.png']", count: 0
    assert_select "head link[rel='apple-touch-icon']", count: 0
    assert_select "head meta[name='theme-color'][content='#123456']"
    assert_select "head meta[name='application-name']", count: 0

    get "/about"

    assert_select "head link[rel=icon][href='/icon.png']"
    assert_select "head link[rel='apple-touch-icon'][href='/icon.png']"
    assert_select "head meta[name='application-name'][content='ContentSpiel']"
    assert_select "head meta[name='theme-color']", count: 0
  end

  test "a template the theme does not hold is the default theme's: the 404 inside the theme's frame" do
    with_plain_theme { get "/no-such-page" }

    assert_response :not_found
    assert_select "div.plain-frame > main.plain-main h1", text: "Page not found"
  end

  test "a post list the theme replaced is drawn by it, and the post's page by the default" do
    blog = create_page(title: "Blog")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).ok?
    publish_changes(blog)
    create_post(title: "First post")

    with_plain_theme { get "/blog" }

    assert_select "ol.plain-posts li a[href='/blog/first-post']", text: "First post"

    with_plain_theme { get "/blog/first-post" }

    assert_select "div.plain-frame article.content-block--post-list-detail h1", text: "First post"
  end

  test "the preview is drawn by the theme too, with the CMS's preview bar" do
    sign_in_as users(:one)

    with_plain_theme { get "/preview/about" }

    assert_response :success
    assert_equal "noindex", response.headers["X-Robots-Tag"]
    assert_select "body > [role=region][aria-label=Preview]"
    assert_select "body > div.plain-frame article.plain-page h1", text: "About"
    assert_select "head link[rel=canonical]", count: 0
  end

  # The dispatch's ruling: the head tags and the bar moved from pages/show
  # into the layout so that a theme which replaces pages/show keeps them.
  # The second theme's pages/show renders neither (it is five lines).
  test "a theme that replaces the page template still gets the description, the Open Graph tags and the preview bar" do
    assert Pages::Save.call(@about, translations: { "en" => { meta_description: "Who writes here" } }).ok?
    publish_changes(@about)
    assert_no_match(/seo_meta|preview_banner/, ThemeTestHelper::PLAIN.join("views/pages/show.html.erb").read)

    with_plain_theme { get "/about" }

    assert_select "article.plain-page"
    assert_select "head meta[name=description][content='Who writes here']", count: 1
    assert_select "head meta[property='og:title'][content='About']", count: 1
    assert_select "head meta[property='og:description'][content='Who writes here']", count: 1
    assert_select "head meta[property='og:url'][content='http://www.example.com/about']", count: 1
    assert_select "[role=region][aria-label=Preview]", count: 0

    sign_in_as users(:one)
    with_plain_theme { get "/preview/about" }

    assert_select "article.plain-page"
    assert_select "head meta[property='og:title'][content='About']", count: 1
    assert_select "html.scroll-pt-9 > body.pt-9 > [role=region][aria-label=Preview]:first-child", count: 1
  end

  # `assign_record` can leave @page and @post set and still answer false (a
  # post no block of its page lists any more), and the preview answers 404
  # for a post whose listing page the editor may not read. The layout
  # collects the head tags itself now, so it must not describe a record on a
  # response that says there is none.
  test "a 404 that had a record in hand describes none: the site's title and no description or Open Graph tag" do
    blog = create_page(title: "Blog", translations: { "en" => { title: "Blog", meta_description: "The blog of secrets" } })
    assert ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).ok?
    publish_changes(blog)
    create_post(title: "Hello")
    # The address is the copy's, the preview draws the rows: the rows list
    # the post no longer, so the page and the post are both in hand when the
    # preview answers that there is nothing to draw the post on.
    assert ContentBlocks::Destroy.call(blog.content_blocks.sole).ok?

    sign_in_as users(:one)
    get "/preview/blog/hello"

    assert_response :not_found
    assert_includes response.body, "<title>Dana&#39;s Notes</title>"
    assert_select "head meta[property^='og:'], head meta[name=description]", count: 0
    assert_no_match(/The blog of secrets/, response.body)
  end

  # The same 404s name no address either: a canonical link or an hreflang
  # alternate on a response that says "not found" tells a search engine that
  # the missing page is the record's own address in every language. The
  # preview never prints a canonical, so the public site's 404 is made here
  # the one way it comes about: the post's stored address outlives the list
  # that gave it one (`PublicPageRendering#assign_record`), which no write
  # path leaves behind and a test can only say by answering for the list.
  test "a 404 that had a record in hand names no canonical address and no other language's, in the preview and in public" do
    blog = create_page(title: "Blog")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).ok?
    publish_changes(blog)
    create_post(title: "Hello")

    get "/blog/hello"
    assert_response :success
    assert_select "head link[rel=canonical]", count: 1
    assert_select "head link[rel=alternate][hreflang]", minimum: 2

    # The address is answered as it is (`PublicSite::Paths.canonical_page`
    # asks with `tags:`), and the controller's own question, the one that
    # finds the page and the post in hand with no list between them, "no".
    listing = Publishing::Listing.method(:lists?)
    asked = 0
    Publishing::Listing.define_singleton_method(:lists?) do |block, post, tags: nil|
      next listing.call(block, post, tags: tags) if tags

      asked += 1
      false
    end
    begin
      get "/blog/hello"
    ensure
      Publishing::Listing.define_singleton_method(:lists?, listing)
    end
    assert_equal 1, asked, "the 404 is the controller's, after it assigned the page and the post"
    assert_response :not_found
    assert_select "head link[rel=canonical], head link[rel=alternate]", count: 0

    assert ContentBlocks::Destroy.call(blog.content_blocks.sole).ok?
    sign_in_as users(:one)
    get "/preview/blog/hello"

    assert_response :not_found
    assert_select "head link[rel=canonical], head link[rel=alternate]", count: 0
  end

  # NOTHING OF A THEME REACHES CS STUDIO, SIGN-IN OR SETUP. A theme's views
  # are on the view path of the two public controllers only
  # (`PublicPageRendering#look_in_the_theme_first`). These tests can fail:
  # the theme they use holds a file at the very name of each private layout
  # and of one view of each private screen, every one of them the marker and
  # nothing else, so a controller that gained the theme's path would draw
  # the marker in place of its own page. (Seen failing, all three, with the
  # `before_action` moved to `ApplicationController`.) The files are written
  # into a copy and not kept in `test/fixtures/themes/plain`: a folder that
  # holds `views/layouts/admin.html.erb` is not a theme, and the folder
  # check refuses it (`lib/theme_folder.rb`); the copy is handed to
  # `Theme.new`, which checks nothing, because what is tested here is the
  # second fence, behind the check.
  LEAK = "THEME-LEAK".freeze
  PRIVATE_VIEWS = %w[
    layouts/admin layouts/product layouts/setup layouts/mailer
    admin/dashboard/show admin/sessions/new setup/token setup/system_check
  ].freeze

  def with_leaking_theme
    with_theme_copy do |dir|
      PRIVATE_VIEWS.each do |name|
        assert Rails.root.join("app/views/#{name}.html.erb").file?, "#{name} is no view of the CMS any more: name one that is"
        file = dir.join("views/#{name}.html.erb")
        file.dirname.mkpath
        file.write("#{LEAK}\n")
      end
      # The control: the same folder IS where a public page's template comes from.
      dir.join("views/pages/not_found.html.erb").write("<p>THEME-FOUND</p>\n")
      @leaking_views = dir.join("views").to_s
      Theme.with(Theme.new(path: dir)) { yield }
    end
  end

  def assert_theme_reached_the_public_page
    get "/no-such-page"
    assert_includes response.body, "THEME-FOUND", "the control failed: the theme's folder is on no path at all"
    assert_equal @leaking_views, controller.lookup_context.view_paths.first.to_s
  end

  def assert_no_theme_here
    assert_response :success
    assert_no_match(/#{LEAK}|plain-frame|plain-mark|plain-page/, response.body)
    assert_not_includes controller.lookup_context.view_paths.map(&:to_s), @leaking_views
  end

  test "nothing of a theme reaches sign-in: a theme's file named as the product layout or the sign-in view is never drawn" do
    with_leaking_theme do
      assert_theme_reached_the_public_page

      get admin_sign_in_path
      assert_no_theme_here
      assert_select "form input[type=password]"
    end
  end

  test "nothing of a theme reaches CS Studio: a theme's file named as the admin layout or the dashboard is never drawn" do
    with_leaking_theme do
      assert_theme_reached_the_public_page

      sign_in_as users(:one)
      get "/cs-studio"
      assert_no_theme_here
      assert_select "head meta[name='theme-color'][content='#123456']", count: 0
    end
  end

  test "nothing of a theme reaches setup: a theme's file named as the setup layout or a step is never drawn" do
    start_fresh_install

    with_leaking_theme do
      get setup_path
      follow_redirect! while response.redirect?
      assert_no_theme_here
      assert_equal "SetupController", controller.class.name

      verify_setup_token
      get setup_step_path("system_check")
      assert_no_theme_here
      assert_includes response.body, "File storage"
    end
  end

  test "a theme's page template that raises is an error that names the theme's file, not a fallback" do
    with_theme_copy do |dir|
      dir.join("views/pages/show.html.erb").write("<p><%= no_such_helper_anywhere %></p>\n")

      error = assert_raises(ActionView::Template::Error) do
        Theme.with(Theme.new(path: dir)) { get "/about" }
      end

      assert_includes error.message, "no_such_helper_anywhere"
      assert_includes error.backtrace.join("\n"), dir.join("views/pages/show.html.erb").to_s
    end
  end
end
