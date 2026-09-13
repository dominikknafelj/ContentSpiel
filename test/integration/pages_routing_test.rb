require "test_helper"

class PagesRoutingTest < ActionDispatch::IntegrationTest
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
end
