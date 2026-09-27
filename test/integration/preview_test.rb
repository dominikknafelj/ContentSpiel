require "test_helper"

class PreviewTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @root = Page.create!(title: "Home", slug: "", published_at: 1.day.ago)
    @draft = Page.create!(parent: @root, title: "Draft", published_at: nil)
  end

  test "preview requires sign-in" do
    get "/preview/draft"
    assert_redirected_to new_session_path
  end

  test "signed-in editors preview drafts with a banner, no-store and noindex" do
    sign_in_as(users(:one))
    get "/preview/draft"
    assert_response :success
    assert_select "[role=status]", /Draft/
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal "noindex", response.headers["X-Robots-Tag"]
    assert_select "a[href=?]", "/avo/resources/pages/#{@draft.id}/edit"
  end

  test "links inside a preview stay in preview" do
    sign_in_as(users(:one))
    get "/preview/de/draft"
    assert_response :success
    assert_select "header a[href^='/preview']"
  end

  test "the public URL of a draft still 404s" do
    get "/draft"
    assert_response :not_found
  end
end
