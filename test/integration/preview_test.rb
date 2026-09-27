require "test_helper"

class PreviewTest < ActionDispatch::IntegrationTest
  setup do
    @root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    @draft = Page.create!(parent: @root, page_type: :standard, title: "Draft page")
    @blog = Page.create!(parent: @root, page_type: :standard, title: "Blog", published_at: Time.current)
    @blog.content_blocks.create!(block_type: :post_list, position: 0)
    @scheduled = Post.create!(content_type: :blog, title: "Coming soon", published_at: 2.days.from_now)
  end

  test "anonymous visitors get 404 for drafts and scheduled posts, in any locale" do
    get "/draft-page"
    assert_response :not_found
    get "/de/draft-page"
    assert_response :not_found
    get "/blog/coming-soon"
    assert_response :not_found
  end

  test "signed-in editors preview a draft page with a banner and no caching" do
    sign_in_as(users(:one))
    get "/draft-page"

    assert_response :success
    assert_includes response.body, "Preview · Draft"
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "signed-in editors preview a scheduled post" do
    sign_in_as(users(:one))
    get "/blog/coming-soon"

    assert_response :success
    assert_includes response.body, "Preview · Scheduled"
  end

  test "live pages show an edit link only to signed-in editors, and no banner" do
    get "/blog"
    assert_select "a", text: "Edit this page", count: 0

    sign_in_as(users(:one))
    get "/blog"
    assert_select "a[href='/avo/resources/pages/#{@blog.id}/edit']", text: "Edit this page"
    assert_not_includes response.body, "Preview ·"
  end
end
