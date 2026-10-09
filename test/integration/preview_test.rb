require "test_helper"

class PreviewTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @root = Page.create!(title: "Home", slug: "", published_at: 1.day.ago)
    @draft = Page.create!(parent: @root, title: "Draft", published_at: nil)
  end

  test "preview requires sign-in" do
    get "/preview/draft"
    assert_redirected_to admin_sign_in_path
  end

  test "signed-in editors preview drafts with a banner, no-store and noindex" do
    sign_in_as(users(:one))
    get "/preview/draft"
    assert_response :success
    assert_select "[role=region][aria-label=Preview]", /Draft/
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal "noindex", response.headers["X-Robots-Tag"]
    assert_select "a[href=?]", "/cs-studio/pages/#{@draft.id}"
  end

  test "the bar names the record, its status and the language's own name, and links Edit with the locale" do
    with_locales(%w[en de], default: "en") do
      Mobility.with_locale(:de) { @draft.update!(title: "Entwurf <b>", slug: "entwurf") }
      sign_in_as(users(:one))

      get "/preview/de/entwurf"

      assert_response :success
      assert_select "[role=region][aria-label=Preview]" do
        assert_select "span.truncate", text: "Entwurf <b>"
        assert_select "b", count: 0
        assert_select "span", text: "Draft"
        assert_select "span", text: "Deutsch"
        assert_select "a[href=?]", "/cs-studio/pages/#{@draft.id}?locale=de", text: "Edit"
      end
    end
  end

  test "Exit preview leaves for the public URL of a live record and for CS Studio's list otherwise" do
    live = Page.create!(parent: @root, title: "Live", published_at: 1.day.ago)
    sign_in_as(users(:one))

    get "/preview/live"
    assert_select "[role=region] a[href=?]", "/live", text: "Exit preview"

    get "/preview/draft"
    assert_select "[role=region] a[href=?]", "/cs-studio/pages", text: "Exit preview"
    assert_select "[role=region] a[href=?]", "/cs-studio/pages/#{@draft.id}", text: "Edit"
  end

  test "Exit preview of a live page in a non-default language keeps the language prefix" do
    with_locales(%w[en de], default: "en") do
      live = Page.create!(parent: @root, title: "Live", published_at: 1.day.ago)
      Mobility.with_locale(:de) { live.update!(title: "Lebendig", slug: "lebendig") }
      sign_in_as(users(:one))

      get "/preview/de/lebendig"
      assert_select "[role=region] a[href=?]", "/de/lebendig", text: "Exit preview"

      get "/preview/de/draft"
      assert_select "[role=region] a[href=?]", "/cs-studio/pages?locale=de", text: "Exit preview"
    end
  end

  test "Exit preview of a live post in German goes to its German public URL, and a draft post to the posts list" do
    with_locales(%w[en de], default: "en") do
      blog = Page.create!(parent: @root, title: "Blog", published_at: 1.day.ago)
      Mobility.with_locale(:de) { blog.update!(title: "Blog", slug: "blog") }
      blog.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
      post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)
      Mobility.with_locale(:de) { post.update!(title: "Hallo", slug: "hallo") }
      sign_in_as(users(:one))

      get "/preview/de/blog/hallo"
      assert_response :success
      assert_select "[role=region] a[href=?]", "/de/blog/hallo", text: "Exit preview"

      post.update!(published_at: nil)
      get "/preview/de/blog/hallo"
      assert_select "[role=region] a[href=?]", "/cs-studio/posts?locale=de", text: "Exit preview"
    end
  end

  test "a post's bar edits the post and exits to its public URL when live" do
    blog = Page.create!(parent: @root, title: "Blog", published_at: 1.day.ago)
    blog.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    post = Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)

    sign_in_as(users(:one))
    get "/preview/blog/hello"

    assert_response :success
    assert_select "[role=region] a[href=?]", "/cs-studio/posts/#{post.id}", text: "Edit"
    assert_select "[role=region] a[href=?]", "/blog/hello", text: "Exit preview"
  end

  test "the bar is the first thing in the body, outside the content column, and the body is padded for it" do
    sign_in_as(users(:one))
    get "/preview/draft"

    assert_select "body.pt-9 > [role=region][aria-label=Preview]:first-child"
    assert_select "html.scroll-pt-9"
    assert_select "div.max-w-3xl [role=region]", count: 0
  end

  test "a live public page has no bar and no padding" do
    Page.create!(parent: @root, title: "Live", published_at: 1.day.ago)

    get "/live"

    assert_response :success
    assert_select "[aria-label=Preview]", count: 0
    assert_select "body.pt-9", count: 0
  end

  test "links inside a preview stay in preview" do
    sign_in_as(users(:one))
    get "/preview/de/draft"
    assert_response :success
    assert_select "header a[href^='/preview']"
  end

  # Sections spec §5.7: the preview draws a section as the public page does.
  test "a draft page's section previews as its band and grid" do
    section = @draft.content_blocks.create!(block_type: :section, position: 0, settings: { "layout" => "three", "background" => "tinted" })
    @draft.content_blocks.create!(block_type: :rich_text, section: section, section_column: 2, position: 0, body: rich_doc("In the middle"))
    sign_in_as(users(:one))

    get "/preview/draft"

    assert_response :success
    assert_select "section.content-section.content-section--tinted.content-section--content .content-section__grid--three" do
      assert_select ".content-section__column", 3
      assert_select ".content-section__column:nth-child(2) .cs-prose", text: /In the middle/
    end
  end

  test "the public URL of a draft still 404s" do
    get "/draft"
    assert_response :not_found
  end

  # A post's current row can outlive its canonical page for a moment (a
  # block removed without callbacks, a sync that hasn't run yet): preview
  # doesn't gate on `Resolver.visible?`, so it finds the row -- and must
  # render the 404 rather than a NoMethodError on a nil page.
  # `Posts::BlogListComponent` builds its item links through `post_url_path`,
  # which reads the request's own `PublicSite::Urls` (`preview: true` here) --
  # pinned so a listing rendered inside preview can never leak a public-site
  # link for one of its items, the same guarantee "links inside a preview
  # stay in preview" already pins for nav/hreflang links.
  test "post-list item links inside a preview stay under /preview" do
    blog = Page.create!(parent: @root, title: "Blog", published_at: 1.day.ago)
    blog.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)

    sign_in_as(users(:one))
    get "/preview/blog"

    assert_response :success
    assert_select "a[href^='/preview/']", /Hello/
  end

  test "a post whose listing page is gone 404s in preview instead of raising" do
    blog = Page.create!(parent: @root, title: "Blog", published_at: 1.day.ago)
    block = blog.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    Post.create!(content_type: :blog, title: "Hello", published_at: 1.day.ago)
    ContentBlock.where(id: block.id).delete_all

    sign_in_as(users(:one))
    get "/preview/blog/hello"
    assert_response :not_found
  end
end
