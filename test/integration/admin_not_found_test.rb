require "test_helper"

class AdminNotFoundTest < ActionDispatch::IntegrationTest
  setup { site_settings(:default).update!(setup_completed_at: Time.current) }

  # The page's own content: the sidebar and account block differ per
  # viewer by design, so what must be word-for-word the same is the frame.
  def content_frame = css_select("turbo-frame#content").map(&:to_html).join

  test "a missing record gets the Studio 404 inside the layout" do
    sign_in_as users(:one)
    get admin_post_path(id: 999_999)
    assert_response :not_found
    assert_select "nav[aria-label='Modules']"
    assert_select "h1", "Not found"
    assert_select "p", "This doesn't exist, or you don't have access to it."
  end

  test "a missing record and an out-of-scope record answer identically" do
    sign_in_as users(:one)
    get admin_post_path(id: 999_999)
    missing = content_frame
    assert_includes missing, "Not found"

    post = Post.create!(title: "Hidden", content_type: :blog, author: users(:one))
    reader = User.create!(email_address: "scoped@example.com", password: "a long enough password")
    group = AccessControl::Group.create!(name: "No posts")
    group.memberships.create!(user: reader)
    group.grants.create!(permission: "posts.read", scope: { "own" => true })
    sign_in_as reader
    get admin_post_path(post)
    assert_response :not_found
    assert_equal missing, content_frame
  end

  test "an autosave to a missing record still answers a bare 404" do
    sign_in_as users(:one)
    patch admin_post_path(id: 999_999), params: { post: { title: "x" } }, as: :turbo_stream
    assert_response :not_found
    assert_no_match(/Not found/, response.body)
    assert_no_match(/turbo-stream/, response.media_type, "a fetch must not take the bare 404 for a stream")
  end

  test "a Turbo Frame request still gets the content frame" do
    sign_in_as users(:one)
    get admin_post_path(id: 999_999), headers: { "Turbo-Frame" => "content" }
    assert_response :not_found
    assert_select "turbo-frame#content h1", "Not found"
  end

  test "the 403 page offers the way back to the dashboard" do
    reader = User.create!(email_address: "plain@example.com", password: "a long enough password")
    sign_in_as reader
    get admin_users_path
    assert_response :forbidden
    assert_select "h1", "No access"
    assert_select "a[href='#{admin_root_path}']", "Back to the dashboard"
  end
end
