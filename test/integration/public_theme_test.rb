require "test_helper"

class PublicThemeTest < ActionDispatch::IntegrationTest
  setup do
    # `update_columns`: SiteSetting refuses an unsafe link on save now, but
    # the footer's own filter (`ThemeHelper#safe_social_links`) stays as
    # defence in depth for a row written some other way, which is what this
    # checks.
    SiteSetting.instance.update!(title: "Dana's Notes")
    SiteSetting.instance.update_columns(social_links: {
      "GitHub" => "HTTPS://github.com/dana", "Mail" => "mailto:dana@example.com",
      "Evil" => "javascript:alert(1)", "Broken" => "ht tp://nope"
    })
    @root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    @about = Page.create!(parent: @root, page_type: :standard, title_en: "About", title_de: "Über", published_at: Time.current)
    Page.create!(parent: @root, page_type: :standard, title: "Secret draft")
  end

  test "the header shows the site title and published top-level pages" do
    get "/"

    assert_select "header a", text: "Dana's Notes"
    assert_select "header nav a[href='/about']", text: "About"
    assert_select "header nav a", text: "Secret draft", count: 0
  end

  test "the footer shows only safe social links and the theme toggle" do
    get "/"

    assert_select "footer a[href='HTTPS://github.com/dana']", text: "GitHub"
    assert_select "footer a[href='mailto:dana@example.com']", text: "Mail"
    assert_select "footer a", text: "Evil", count: 0
    assert_select "footer a", text: "Broken", count: 0
    assert_select "footer [data-controller=theme]"
  end

  test "the page head carries hreflang alternates for every enabled language, plus x-default" do
    get "/about"

    assert_select "head link[rel=alternate][hreflang=en][href='http://www.example.com/about']"
    assert_select "head link[rel=alternate][hreflang=de][href='http://www.example.com/de/uber']"
    assert_select "head link[rel=alternate][hreflang=es][href='http://www.example.com/es/about']"
    assert_select "head link[rel=alternate][hreflang=x-default][href='http://www.example.com/about']"
  end

  test "the language switcher links the current page in every locale" do
    get "/about"

    assert_select "[aria-label=Language] a[href='/about'][aria-current=true]", text: "en"
    assert_select "[aria-label=Language] a[href='/de/uber']", text: "de"
    assert_select "[aria-label=Language] a[href='/es/about']", text: "es"
  end

  test "the switcher link for a post without a German slug still resolves" do
    blog = Page.create!(parent: @root, page_type: :standard, title: "Blog", published_at: Time.current)
    blog.content_blocks.create!(block_type: :post_list, position: 0)
    post = Post.create!(content_type: :blog, title_en: "Hello", published_at: 1.day.ago)
    # Since Task 8c every post gets a German slug by LocalizedSlug's
    # fallback the moment it has a title anywhere, so this scenario can no
    # longer arise through a validated save -- `update_columns` forces the
    # pre-fallback, no-German-slug state directly, the same way
    # test/models/post_test.rb does to test the fallback itself.
    post.update_columns(slug: post.read_attribute(:slug).except("de"))

    get "/blog/hello"
    german = css_select("[aria-label=Language] a[hreflang=de]").first["href"]

    get german
    assert_response :success
    assert_includes response.body, "Hello"
  end

  test "the document title includes the site name" do
    get "/about"
    assert_includes response.body, "<title>About – Dana&#39;s Notes</title>"
    # I18n.locale at render time is the locale the URL was requested in, not
    # a fixed default -- application.html.erb's <html lang> has to agree.
    assert_select "html[lang=en]"

    get "/"
    assert_includes response.body, "<title>Dana&#39;s Notes</title>"
  end
end
