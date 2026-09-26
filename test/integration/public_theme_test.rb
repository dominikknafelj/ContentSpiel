require "test_helper"

class PublicThemeTest < ActionDispatch::IntegrationTest
  setup do
    SiteSetting.instance.update!(title: "Dana's Notes", social_links: {
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

  test "the language switcher links the current page in every locale" do
    get "/about"

    assert_select "[aria-label=Language] a[href='/about'][aria-current=true]", text: "en"
    assert_select "[aria-label=Language] a[href='/de/uber']", text: "de"
    assert_select "[aria-label=Language] a[href='/es/about']", text: "es"
  end

  test "the switcher link for a post without a German slug still resolves" do
    blog = Page.create!(parent: @root, page_type: :standard, title: "Blog", published_at: Time.current)
    blog.content_blocks.create!(block_type: :post_list, position: 0)
    Post.create!(content_type: :blog, title_en: "Hello", published_at: 1.day.ago)

    get "/blog/hello"
    german = css_select("[aria-label=Language] a[hreflang=de]").first["href"]

    get german
    assert_response :success
    assert_includes response.body, "Hello"
  end

  test "the document title includes the site name" do
    get "/about"
    assert_includes response.body, "<title>About – Dana&#39;s Notes</title>"

    get "/"
    assert_includes response.body, "<title>Dana&#39;s Notes</title>"
  end
end
