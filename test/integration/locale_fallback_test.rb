require "test_helper"

# Fix 1 (editor-experience final wave): on a site whose default_locale isn't
# English, a page or post titled only in that default locale used to render
# blank everywhere else -- Mobility's own `fallbacks` plugin falls back to a
# fixed :en, not the site's runtime default (see ThemeHelper#translated).
#
# Reproduction this guards against: SiteSetting default_locale "de", a child
# page of Home titled only in German. Its en/es slugs are filled from the
# German title by LocalizedSlug, so GET /en/<slug> resolves (200), but
# before this fix rendered an empty <title>, an empty <h1>, and the nav link
# rendered its own href as visible text (`link_to nil, path`).
class LocaleFallbackTest < ActionDispatch::IntegrationTest
  setup do
    SiteSetting.instance.update!(title: "Dana's Notes", default_locale: "de")
    @root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
  end

  test "a page titled only in the site's default locale renders that title in <title>, <h1> and the nav link" do
    kontakt = Mobility.with_locale(:de) do
      Page.create!(page_type: :standard, title: "Kontaktprobe", parent: @root, published_at: Time.current)
    end
    # en/es slugs come from LocalizedSlug's fallback, not an
    # editor typing one -- confirms the page really is reachable at /en/...
    assert_equal "kontaktprobe", kontakt.slug_en

    get "/en/kontaktprobe"
    assert_response :success

    assert_includes response.body, "<title>Kontaktprobe – Dana&#39;s Notes</title>"
    assert_select "h1", text: "Kontaktprobe"
    assert_select "header nav a[href='/en/kontaktprobe']", text: "Kontaktprobe"
  end

  test "a post titled only in the site's default locale shows that title in an /en/... listing" do
    blog = Mobility.with_locale(:de) do
      Page.create!(page_type: :standard, title: "Blog", parent: @root, published_at: Time.current)
    end
    blog.content_blocks.create!(block_type: :post_list, position: 0)
    Mobility.with_locale(:de) do
      Post.create!(content_type: :blog, title: "Hallo Welt", published_at: 1.day.ago)
    end

    get "/en/blog"
    assert_response :success

    assert_select "header nav a", text: "Blog"
    assert_select "li a", text: "Hallo Welt"
  end

  test "an existing English title wins over the German one" do
    both = Page.create!(page_type: :standard, title_en: "Contact", title_de: "Kontakt", parent: @root,
      published_at: Time.current, slug_en: "contact")

    get "/en/contact"
    assert_response :success

    assert_select "h1", text: "Contact"
    assert_select "h1", text: "Kontakt", count: 0
  end

  # ThemeHelper#rich_text (backed by Locales.read) covers rich-text bodies
  # too, not just jsonb attributes -- the same "titled only in German" gap
  # applied to a rich text block's body before this task.
  test "a German-only rich text block renders its body on the English page" do
    seite = Mobility.with_locale(:de) do
      page = Page.create!(page_type: :standard, title: "Kontaktseite", parent: @root, published_at: Time.current)
      page.content_blocks.create!(block_type: :rich_text, position: 0, body: rich_doc("German body"))
      page
    end

    get "/en/#{seite.slug_en}"
    assert_response :success

    assert_includes response.body, "German body"
  end
end
