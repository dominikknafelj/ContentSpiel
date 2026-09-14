require "test_helper"

class PagesRoutingTest < ActionDispatch::IntegrationTest
  # The site has no unprefixed public URLs: "/" exists only to send a visitor
  # to the default locale's root page.
  #
  # Temporarily (302), not permanently: a 301 is cached by browsers for good
  # and cannot be taken back, so it is not something to ship before the
  # mapping is final.
  test "the bare root redirects to the default locale root" do
    get "/"

    assert_redirected_to "/en/"
    assert_response :found
  end

  test "the root page renders at the locale root" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    ContentBlock.create!(page: root, block_type: :rich_text, position: 0, body: "<p>Welcome</p>")

    get "/en/"

    assert_response :success
    assert_includes response.body, "Welcome"
  end

  test "a nested page renders at its full path" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    about = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root, published_at: Time.current)
    ContentBlock.create!(page: about, block_type: :rich_text, position: 0, body: "<p>About us</p>")

    get "/en/about"

    assert_response :success
    assert_includes response.body, "About us"
  end

  test "an unmatched path returns 404" do
    get "/en/does-not-exist"

    assert_response :not_found
  end

  # The catch-all is declared with `format: false`, so Rails appends no
  # implicit `(.:format)` group to it. Without that, a dot anywhere in the last
  # segment of a URL is read as a format separator, which breaks the route in
  # two directions -- the two tests below are one for each.
  #
  # Direction one: a crawler appending an extension to a real page. The path
  # still matches the page, so the controller renders `show` -- in a format
  # that has no template. `ActionView::MissingTemplate` is not in
  # `ActionDispatch::ExceptionWrapper.rescue_responses`, so it is not mapped to
  # a status at all and surfaces as an uncaught 500 on a public URL.
  test "an extension appended to a real page's path does not reach the page" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    Page.create!(page_type: :standard, title: "About", slug: "about", parent: root, published_at: Time.current)

    get "/en/about.json"

    assert_response :not_found
  end

  # Direction two: a page whose own slug contains a dot. `Page#full_path` (and
  # so config/sitemap.rb, which emits those paths verbatim) advertises
  # "/en/v1.0" -- with an implicit format group the trailing ".0" is sliced off
  # into `params[:format]`, the controller looks up "/v1", and the page 404s at
  # the very URL the sitemap hands to search engines.
  test "a page whose slug contains a dot is reachable at its real path" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    release = Page.create!(page_type: :standard, title: "Release v1.0", slug: "v1.0", parent: root,
      published_at: Time.current)
    ContentBlock.create!(page: release, block_type: :rich_text, position: 0, body: "<p>Release notes</p>")

    assert_equal "/v1.0", release.full_path(:en)

    get "/en/v1.0"

    assert_response :success
    assert_includes response.body, "Release notes"
  end

  # `format: false` must not narrow what the route otherwise matches: the
  # locale root, a single segment and a deep glob all still dispatch to
  # `pages#show` with the same parameters as before.
  test "the catch-all still recognizes the locale root and nested paths" do
    assert_recognizes({ controller: "pages", action: "show", locale: "en", path: "" }, "/en")
    assert_recognizes({ controller: "pages", action: "show", locale: "en", path: "about" }, "/en/about")
    assert_recognizes({ controller: "pages", action: "show", locale: "de", path: "a/b/c" }, "/de/a/b/c")
    assert_recognizes({ controller: "pages", action: "show", locale: "es", path: "v1.0" }, "/es/v1.0")
  end

  test "a page's meta_title and meta_description render in the head" do
    Page.create!(
      page_type: :standard,
      title: "Home",
      slug: "",
      meta_title: "ContentSpiel — Home",
      meta_description: "The personal site of a software developer.",
      published_at: Time.current
    )

    get "/en/"

    assert_response :success
    assert_includes response.body, "<title>ContentSpiel — Home</title>"
    assert_includes response.body, %(<meta name="description" content="The personal site of a software developer.")
  end

  # `meta_title` is the optional override: a page that doesn't set one is still
  # entitled to a title, and the one it has is its own.
  test "meta_title falls back to the page's title when blank" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    Page.create!(page_type: :standard, title: "About", slug: "about", parent: root,
      meta_title: "", published_at: Time.current)

    get "/en/"

    assert_response :success
    assert_includes response.body, "<title>Home</title>"

    # Not only an absent override: one the admin typed and then cleared is just
    # as blank, and must fall back the same way rather than emptying the title.
    get "/en/about"

    assert_response :success
    assert_includes response.body, "<title>About</title>"
  end

  # A page with neither a meta_description nor (below) a post to describe emits
  # no description tag at all -- an empty one is worse than none.
  test "a page without a meta_description renders no description tag" do
    Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)

    get "/en/"

    assert_response :success
    assert_not_includes response.body, %(<meta name="description")
  end

  test "a page renders Open Graph tags for the URL it was requested at" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    Page.create!(page_type: :standard, title: "About", slug: "about", parent: root,
      meta_description: "Who I am.", published_at: Time.current)

    get "/en/about"

    assert_response :success
    assert_includes response.body, %(<meta property="og:title" content="About")
    assert_includes response.body, %(<meta property="og:description" content="Who I am.")
    assert_includes response.body, %(<meta property="og:type" content="website")
    assert_includes response.body, %(<meta property="og:url" content="http://www.example.com/en/about")
    assert_includes response.body, %(<meta property="og:locale" content="en")
  end

  # The SEO tags describe what the response actually shows. A post permalink
  # renders one post inside its listing page, so every post under a listing
  # would otherwise share that page's title and description.
  test "a post detail view's meta tags describe the post, not its listing page" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    blog_page = Page.create!(page_type: :standard, title: "Blog", slug: "blog", parent: root,
      meta_description: "Everything I've written.", published_at: Time.current)
    ContentBlock.create!(page: blog_page, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    post = Post.create!(content_type: :blog, title: "My First Post", excerpt: "A short summary.",
      body: "<p>Full post content</p>", published_at: Time.current)

    get "/en/blog/#{post.slug}"

    assert_response :success
    assert_includes response.body, "<title>My First Post</title>"
    assert_includes response.body, %(<meta name="description" content="A short summary.")
    assert_includes response.body, %(<meta property="og:type" content="article")
    assert_not_includes response.body, "Everything I&#39;ve written."
  end

  # The page is read in the requested locale, so the tags describing it have to
  # be too.
  test "meta tags render in the locale the page was requested under" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    about = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root,
      meta_title: "About me", meta_description: "Who I am.", published_at: Time.current)
    Mobility.with_locale(:de) do
      about.update!(slug: "ueber-uns", meta_title: "Ueber mich", meta_description: "Wer ich bin.")
    end

    get "/de/ueber-uns"

    assert_response :success
    assert_includes response.body, "<title>Ueber mich</title>"
    assert_includes response.body, %(<meta name="description" content="Wer ich bin.")
    assert_includes response.body, %(<meta property="og:locale" content="de")
  end

  # The locale prefix isn't only a lookup key for the path: it has to be the
  # locale the page's translated content is read in for the length of the
  # request, or a German URL renders English text.
  test "a page renders in the locale its path was requested under" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    about = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root, published_at: Time.current)
    block = ContentBlock.create!(page: about, block_type: :rich_text, position: 0, body: "<p>About us</p>")
    Mobility.with_locale(:de) do
      about.update!(slug: "ueber-uns")
      block.update!(body: "<p>Ueber uns</p>")
    end

    get "/de/ueber-uns"

    assert_response :success
    assert_includes response.body, "Ueber uns"
    assert_not_includes response.body, "About us"
  end

  # A page with no `published_at` is a draft: it has a path the moment it is
  # saved, and must not be reachable at it until it is published.
  test "an unpublished page returns 404" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    Page.create!(page_type: :standard, title: "Draft", slug: "draft", parent: root, published_at: nil)

    get "/en/draft"

    assert_response :not_found
  end

  test "a page published in the future returns 404" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    Page.create!(page_type: :standard, title: "Scheduled", slug: "scheduled", parent: root, published_at: 1.day.from_now)

    get "/en/scheduled"

    assert_response :not_found
  end

  test "a page renders its blocks in position order" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    ContentBlock.create!(page: root, block_type: :rich_text, position: 1, body: "<p>Second</p>")
    ContentBlock.create!(page: root, block_type: :rich_text, position: 0, body: "<p>First</p>")

    get "/en/"

    assert_response :success
    assert_operator response.body.index("First"), :<, response.body.index("Second")
  end

  test "a post_list block renders matching posts" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    blog_page = Page.create!(page_type: :standard, title: "Blog", slug: "blog", parent: root, published_at: Time.current)
    ContentBlock.create!(page: blog_page, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    Post.create!(content_type: :blog, title: "My First Post", published_at: Time.current)

    get "/en/blog"

    assert_response :success
    assert_includes response.body, "My First Post"
  end

  # A post with no `published_at` (or one dated in the future) is a draft: the
  # admin can see it, the public listing may not.
  test "a post_list block omits unpublished posts" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    blog_page = Page.create!(page_type: :standard, title: "Blog", slug: "blog", parent: root, published_at: Time.current)
    ContentBlock.create!(page: blog_page, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    Post.create!(content_type: :blog, title: "Published Post", published_at: 1.day.ago)
    Post.create!(content_type: :blog, title: "Draft Post", published_at: nil)
    Post.create!(content_type: :blog, title: "Scheduled Post", published_at: 1.day.from_now)

    get "/en/blog"

    assert_response :success
    assert_includes response.body, "Published Post"
    assert_not_includes response.body, "Draft Post"
    assert_not_includes response.body, "Scheduled Post"
  end

  test "a post_list block respects its limit setting" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    blog_page = Page.create!(page_type: :standard, title: "Blog", slug: "blog", parent: root, published_at: Time.current)
    ContentBlock.create!(page: blog_page, block_type: :post_list, position: 0,
      settings: { "content_type" => "blog", "limit" => 2 })
    Post.create!(content_type: :blog, title: "Newest Post", published_at: 1.hour.ago)
    Post.create!(content_type: :blog, title: "Middle Post", published_at: 1.day.ago)
    Post.create!(content_type: :blog, title: "Oldest Post", published_at: 1.week.ago)

    get "/en/blog"

    assert_response :success
    assert_includes response.body, "Newest Post"
    assert_includes response.body, "Middle Post"
    assert_not_includes response.body, "Oldest Post"
  end

  test "a post_list block only lists its own content type" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    blog_page = Page.create!(page_type: :standard, title: "Blog", slug: "blog", parent: root, published_at: Time.current)
    ContentBlock.create!(page: blog_page, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    Post.create!(content_type: :blog, title: "A Blog Entry", published_at: 1.day.ago)
    Post.create!(content_type: :resume_entry, title: "A Resume Entry", published_at: 1.day.ago)

    get "/en/blog"

    assert_response :success
    assert_includes response.body, "A Blog Entry"
    assert_not_includes response.body, "A Resume Entry"
  end

  # An empty "Content type" in the admin's block form means "every content
  # type" -- the reading ContentBlock's own settings validation is written
  # against. `posts.content_type` is NOT NULL, so handing that blank straight
  # to `where` would compile to `content_type IS NULL` and list nothing.
  test "a post_list block with no content type lists posts of every type" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    everything = Page.create!(page_type: :standard, title: "Everything", slug: "everything", parent: root,
      published_at: Time.current)
    ContentBlock.create!(page: everything, block_type: :post_list, position: 0, settings: {})
    Post.create!(content_type: :blog, title: "A Blog Entry", published_at: 1.day.ago)
    Post.create!(content_type: :resume_entry, title: "A Resume Entry", published_at: 1.day.ago)

    get "/en/everything"

    assert_response :success
    assert_includes response.body, "A Blog Entry"
    assert_includes response.body, "A Resume Entry"
  end

  # The permalinks such a page serves have to match what it lists, or a post is
  # on the page but its detail URL 404s.
  test "a post_list block with no content type serves permalinks for every type" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    everything = Page.create!(page_type: :standard, title: "Everything", slug: "everything", parent: root,
      published_at: Time.current)
    ContentBlock.create!(page: everything, block_type: :post_list, position: 0, settings: {})
    resume_entry = Post.create!(content_type: :resume_entry, title: "A Resume Entry",
      body: "<p>Where I worked</p>", published_at: 1.day.ago)

    get "/en/everything/#{resume_entry.slug}"

    assert_response :success
    assert_includes response.body, "Where I worked"
  end

  # No Page node exists per Post (page-tree design spec section 4): a post's
  # permalink is served by the very page whose post_list block lists it, with
  # the trailing segment read as the post's slug.
  test "a trailing slug that matches a post under a post_list block renders that post's detail view" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    blog_page = Page.create!(page_type: :standard, title: "Blog", slug: "blog", parent: root, published_at: Time.current)
    ContentBlock.create!(page: blog_page, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    post = Post.create!(content_type: :blog, title: "My First Post", body: "<p>Full post content</p>",
      published_at: Time.current)

    get "/en/blog/#{post.slug}"

    assert_response :success
    assert_includes response.body, "Full post content"
    assert_not_includes response.body, "<ul>" # the list markup shouldn't also render
  end

  # The detail view replaces the block that matched, not the whole page: the
  # rest of the listing page's blocks are its chrome and still belong there.
  test "a post detail view still renders the page's other blocks" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    blog_page = Page.create!(page_type: :standard, title: "Blog", slug: "blog", parent: root, published_at: Time.current)
    ContentBlock.create!(page: blog_page, block_type: :rich_text, position: 0, body: "<p>Blog intro</p>")
    ContentBlock.create!(page: blog_page, block_type: :post_list, position: 1, settings: { "content_type" => "blog" })
    post = Post.create!(content_type: :blog, title: "My First Post", body: "<p>Full post content</p>",
      published_at: Time.current)

    get "/en/blog/#{post.slug}"

    assert_response :success
    assert_includes response.body, "Blog intro"
    assert_includes response.body, "Full post content"
  end

  test "a trailing segment that matches no post under a post_list block, and no Page, is 404" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    blog_page = Page.create!(page_type: :standard, title: "Blog", slug: "blog", parent: root, published_at: Time.current)
    ContentBlock.create!(page: blog_page, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })

    get "/en/blog/no-such-post"

    assert_response :not_found
  end

  # A page that lists nothing serves no permalinks: without a post_list block
  # there is no criteria by which a trailing segment could name a post.
  test "a trailing slug under a page with no post_list block is 404" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    about = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root, published_at: Time.current)
    ContentBlock.create!(page: about, block_type: :rich_text, position: 0, body: "<p>About us</p>")
    post = Post.create!(content_type: :blog, title: "My First Post", published_at: Time.current)

    get "/en/about/#{post.slug}"

    assert_response :not_found
  end

  test "a trailing slug under a path with no page at all is 404" do
    Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    post = Post.create!(content_type: :blog, title: "My First Post", published_at: Time.current)

    get "/en/nowhere/#{post.slug}"

    assert_response :not_found
  end

  # The listing page's own draft status governs the permalinks it serves, or a
  # post detail URL becomes a back door into an unpublished page's content.
  test "a post detail under an unpublished page is 404" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    draft_page = Page.create!(page_type: :standard, title: "Blog", slug: "blog", parent: root, published_at: nil)
    ContentBlock.create!(page: draft_page, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    post = Post.create!(content_type: :blog, title: "My First Post", body: "<p>Full post content</p>",
      published_at: Time.current)

    get "/en/blog/#{post.slug}"

    assert_response :not_found
  end

  # A draft post is kept out of the listing; its permalink has to be just as
  # closed, or the post is public to anyone who guesses the slug.
  test "an unpublished post's detail view is 404" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    blog_page = Page.create!(page_type: :standard, title: "Blog", slug: "blog", parent: root, published_at: Time.current)
    ContentBlock.create!(page: blog_page, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    draft = Post.create!(content_type: :blog, title: "Draft Post", body: "<p>Secret draft</p>", published_at: nil)
    scheduled = Post.create!(content_type: :blog, title: "Scheduled Post", body: "<p>Not yet</p>",
      published_at: 1.day.from_now)

    get "/en/blog/#{draft.slug}"
    assert_response :not_found

    get "/en/blog/#{scheduled.slug}"
    assert_response :not_found
  end

  # The block's own criteria decide which posts it serves: a resume entry is
  # not reachable under a page listing blog posts.
  test "a post of another content type is not reachable under a post_list block" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    blog_page = Page.create!(page_type: :standard, title: "Blog", slug: "blog", parent: root, published_at: Time.current)
    ContentBlock.create!(page: blog_page, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    resume_entry = Post.create!(content_type: :resume_entry, title: "A Resume Entry", published_at: 1.day.ago)

    get "/en/blog/#{resume_entry.slug}"

    assert_response :not_found
  end

  # The fallback resolves inside the requested locale, like the exact-match
  # path does: a German URL has to find the post by its German slug and render
  # its German body.
  test "a post detail resolves and renders in the locale it was requested under" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    blog_page = Page.create!(page_type: :standard, title: "Blog", slug: "blog", parent: root, published_at: Time.current)
    ContentBlock.create!(page: blog_page, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    post = Post.create!(content_type: :blog, title: "My First Post", body: "<p>Full post content</p>",
      published_at: Time.current)
    Mobility.with_locale(:de) do
      blog_page.update!(slug: "blogeintraege")
      post.update!(slug: "mein-erster-beitrag", title: "Mein erster Beitrag", body: "<p>Ganzer Beitrag</p>")
    end

    get "/de/blogeintraege/mein-erster-beitrag"

    assert_response :success
    assert_includes response.body, "Ganzer Beitrag"
    assert_not_includes response.body, "Full post content"
  end

  # Slugs fall back the same way `Page#full_path` builds its paths: a post left
  # untranslated in the requested locale keeps the default locale's slug, so
  # that is the URL it has to answer to there.
  test "a post untranslated in the requested locale is reachable at its default-locale slug" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    blog_page = Page.create!(page_type: :standard, title: "Blog", slug: "blog", parent: root, published_at: Time.current)
    ContentBlock.create!(page: blog_page, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    post = Post.create!(content_type: :blog, title: "My First Post", body: "<p>Full post content</p>",
      published_at: Time.current)
    Mobility.with_locale(:de) { post.update!(body: "<p>Ganzer Beitrag</p>") }

    get "/de/blog/#{post.slug}"

    assert_response :success
    assert_includes response.body, "Ganzer Beitrag"
  end

  # An exact match in the requested locale wins over another post that is only
  # reachable there by fallback -- otherwise the fallback would shadow the very
  # post whose German URL this is.
  test "a post's own localized slug wins over another post's fallback slug" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    blog_page = Page.create!(page_type: :standard, title: "Blog", slug: "blog", parent: root, published_at: Time.current)
    ContentBlock.create!(page: blog_page, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    Post.create!(content_type: :blog, title: "Shared Slug", slug: "geteilt", body: "<p>English only</p>",
      published_at: Time.current)
    german = Post.create!(content_type: :blog, title: "Another Post", slug: "another-post",
      body: "<p>English body</p>", published_at: Time.current)
    Mobility.with_locale(:de) { german.update!(slug: "geteilt", body: "<p>Deutscher Beitrag</p>") }

    get "/de/blog/geteilt"

    assert_response :success
    assert_includes response.body, "Deutscher Beitrag"
    assert_not_includes response.body, "English only"
  end

  # `format: false` on the route (added earlier) only stops a URL segment like
  # ".json" from being read as a format -- it says nothing about a request that
  # names a format through its `Accept` header instead. Without pinning the
  # format, `render :show` still negotiates against the header, finds no
  # `show.json.erb`, and raises `ActionView::MissingTemplate` -- a class Rails'
  # own rescue table doesn't map to a 404, so it reaches a requester as a raw
  # 500.
  test "a request with a non-HTML Accept header still renders the page" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    ContentBlock.create!(page: root, block_type: :rich_text, position: 0, body: "<p>Welcome</p>")

    get "/en/", headers: { "Accept" => "application/json" }

    assert_response :success
    assert_includes response.body, "Welcome"
  end

  # A landing page's title/subtitle/hero image are the reason `page_type`
  # exists at all (page-tree design spec section 3) -- Avo has always been able
  # to edit them, but nothing on the public side ever read them back.
  test "a landing page renders its title, subtitle, and hero image" do
    root = Page.create!(page_type: :landing, title: "Welcome", subtitle: "A warm welcome", slug: "",
      published_at: Time.current)
    root.hero_image.attach(io: StringIO.new("fake image data"), filename: "hero.jpg", content_type: "image/jpeg")
    root.save!

    get "/en/"

    assert_response :success
    assert_includes response.body, "<h1>Welcome</h1>"
    assert_includes response.body, "A warm welcome"
    assert_match(/<img[^>]*src="[^"]*hero/, response.body)
  end

  # `page_type` gates the hero fields defensively rather than trusting that a
  # `standard` page's `subtitle`/`hero_image` are blank: the columns aren't
  # otherwise enforced empty outside `landing`, and the view is the last place
  # that distinction can still be honored.
  test "a standard page does not render subtitle or hero image even if set" do
    root = Page.create!(page_type: :standard, title: "Home", subtitle: "Should not appear", slug: "",
      published_at: Time.current)

    get "/en/"

    assert_response :success
    assert_not_includes response.body, "Should not appear"
  end

  # A post's detail view already renders its own <h1> (the post's title) --
  # showing the listing page's title above it too would put two <h1>s on one
  # response for no reader's benefit.
  test "a post's detail view does not also render its listing page's title" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    blog_page = Page.create!(page_type: :standard, title: "Blog", slug: "blog", parent: root, published_at: Time.current)
    ContentBlock.create!(page: blog_page, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    post = Post.create!(content_type: :blog, title: "My First Post", body: "<p>Full post content</p>",
      published_at: Time.current)

    get "/en/blog/#{post.slug}"

    assert_response :success
    assert_not_includes response.body, "<h1>Blog</h1>"
    assert_includes response.body, "<h1>My First Post</h1>"
  end

  # Before this, the page tree and every post permalink existed only for a
  # visitor who already knew the exact URL -- nothing rendered anywhere linked
  # to them.
  test "a post_list block links each post's title to its permalink" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    blog_page = Page.create!(page_type: :standard, title: "Blog", slug: "blog", parent: root, published_at: Time.current)
    ContentBlock.create!(page: blog_page, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    post = Post.create!(content_type: :blog, title: "My First Post", published_at: Time.current)

    get "/en/blog"

    assert_response :success
    assert_includes response.body, %(href="/en/blog/#{post.slug}")
    assert_includes response.body, "My First Post</a>"
  end

  # Same fix, the root-hosted case: a post_list block living directly on the
  # homepage has no page path segment to join against, so the permalink is
  # "/en/<slug>" rather than "/en//<slug>".
  test "a post_list block on the root page links to a root-level permalink" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    ContentBlock.create!(page: root, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    post = Post.create!(content_type: :blog, title: "My First Post", published_at: Time.current)

    get "/en/"

    assert_response :success
    assert_includes response.body, %(href="/en/#{post.slug}")
  end

  test "a page lists its published child pages as links" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    Page.create!(page_type: :standard, title: "About", slug: "about", parent: root, published_at: Time.current)

    get "/en/"

    assert_response :success
    assert_includes response.body, %(href="/en/about")
    assert_includes response.body, "About</a>"
  end

  test "a page does not list an unpublished child page" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    Page.create!(page_type: :standard, title: "Draft Child", slug: "draft-child", parent: root, published_at: nil)

    get "/en/"

    assert_response :success
    assert_not_includes response.body, "draft-child"
    assert_not_includes response.body, "Draft Child"
  end
end
