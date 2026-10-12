require "test_helper"

# A page under the second theme (theming spec §2 and "Testing"): the theme's
# frame, page template and block template; the default theme's header, image
# block and 404 where the theme holds none; and the CMS's head whatever the
# theme does.
class ThemePagesTest < ActionDispatch::IntegrationTest
  # What the CMS writes into <head> and a theme cannot remove (spec §2).
  CMS_HEAD = [
    "title", "meta[name=viewport]", "meta[property='og:title']", "meta[property='og:type']", "meta[property='og:url']",
    "meta[property='og:locale']", "link[rel=canonical]", "link[rel=alternate][hreflang=en]",
    "link[rel=alternate][hreflang=x-default]", "link[rel=stylesheet]", "script[type=importmap]"
  ].freeze

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

  test "every tag the CMS writes into the head is there under both themes" do
    get "/about"
    default_head = head
    with_plain_theme { get "/about" }
    themed_head = head

    CMS_HEAD.each do |selector|
      assert default_head.at_css(selector), "the default theme's head has no #{selector}"
      assert themed_head.at_css(selector), "the second theme's head has no #{selector}"
    end
    assert_includes themed_head.to_html, 'localStorage.getItem("cs-theme")'
    assert_equal default_head.css("meta[property^='og:'], link[rel=canonical], link[rel=alternate]").map(&:to_html),
      themed_head.css("meta[property^='og:'], link[rel=canonical], link[rel=alternate]").map(&:to_html)
    assert_nil themed_head.at_css("meta[name=csrf-token]")
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

  test "nothing of a theme reaches CS Studio, sign-in or setup" do
    with_plain_theme do
      get admin_sign_in_path
      assert_response :success
      assert_no_match(/plain-frame|plain-mark|plain-page/, response.body)

      sign_in_as users(:one)
      get "/cs-studio"
      assert_response :success
      assert_no_match(/plain-frame|plain-mark|plain-page/, response.body)
      assert_select "head meta[name='theme-color'][content='#123456']", count: 0
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
