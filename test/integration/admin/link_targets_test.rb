require "test_helper"

# `Admin::LinkTargetsController#index` (design spec §4.1/§4.2): the Tiptap
# editor's own internal-link picker searches this for pages and posts by
# title, in the admin's editing locale. Unpublished pages/posts are
# included on purpose (editors link ahead of publishing; the public HTML
# renderer already degrades an invisible target's link to plain text --
# `RichText::BuiltIns#render_internal_link`).
class Admin::LinkTargetsTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
  end

  test "finds a page and a post by title, published or not" do
    sign_in_as(users(:one))
    page = create_page(title: "About the Team", published: false)
    post_record = create_post(title: "About Our Culture", published: false)
    create_page(title: "Unrelated")

    get "/cs-studio/link_targets", params: { q: "about", locale: "en" }

    results = response.parsed_body
    assert_equal 2, results.size

    page_result = results.find { |r| r["type"] == "page" }
    post_result = results.find { |r| r["type"] == "post" }
    assert_equal page.id, page_result["id"]
    assert_equal "About the Team", page_result["title"]
    assert_equal post_record.id, post_result["id"]
    assert_equal "About Our Culture", post_result["title"]
  end

  test "a % in the query is escaped, not treated as a SQL wildcard" do
    sign_in_as(users(:one))
    create_page(title: "100% Guaranteed")
    create_page(title: "Totally Different")

    get "/cs-studio/link_targets", params: { q: "100%", locale: "en" }

    results = response.parsed_body
    assert_equal 1, results.size
    assert_equal "100% Guaranteed", results.first["title"]
  end

  test "type=page filters to only pages, type=post to only posts" do
    sign_in_as(users(:one))
    create_page(title: "Shared Title")
    create_post(title: "Shared Title")

    only_pages = get_results(q: "Shared", type: "page")
    assert_equal [ "page" ], only_pages.map { |r| r["type"] }.uniq

    only_posts = get_results(q: "Shared", type: "post")
    assert_equal [ "post" ], only_posts.map { |r| r["type"] }.uniq
  end

  # The related-posts chip input shows "· Draft" / "· Scheduled" next to a
  # post, and the type's colour dot.
  test "each row carries its publish status, and a post row its type dot" do
    sign_in_as(users(:one))
    create_page(title: "Chip Page", published: false)
    create_post(title: "Chip Draft", published: false)
    create_post(title: "Chip Live")
    scheduled = create_post(title: "Chip Later")
    scheduled.update_columns(published_at: 2.days.from_now)

    rows = get_results(q: "Chip").index_by { |r| r["title"] }

    assert_equal "draft", rows["Chip Page"]["status"]
    assert_equal "draft", rows["Chip Draft"]["status"]
    assert_equal "live", rows["Chip Live"]["status"]
    assert_equal "scheduled", rows["Chip Later"]["status"]
    assert_match(/\A(bg|border)[ -]/, rows["Chip Live"]["dot"])
    assert_nil rows["Chip Page"]["dot"]
  end

  test "an unknown type is rejected" do
    sign_in_as(users(:one))
    get "/cs-studio/link_targets", params: { q: "x", type: "snippet" }

    assert_response :unprocessable_entity
  end

  test "includes the public path, or nil when the target has none" do
    sign_in_as(users(:one))
    page = create_page(title: "Reachable Page")

    results = get_results(q: "Reachable")
    assert_equal PublicSite::Urls.new.path_for(page, "en"), results.first["path"]
  end

  # Fix round 1's I1: a malformed locale isn't an *enabled* one, so this
  # must fall back to the admin's own current editing locale (same as
  # `Admin::BaseController#admin_locale`), not reach Mobility with
  # something it can't parse as a locale code at all and 500.
  test "a malformed locale falls back to the admin locale instead of raising" do
    sign_in_as(users(:one))
    create_page(title: "Fallback Page")

    get "/cs-studio/link_targets", params: { q: "Fallback", locale: "en US" }

    assert_response :success
    assert_equal "Fallback Page", response.parsed_body.first["title"]
  end

  test "caps results at 20" do
    sign_in_as(users(:one))
    25.times { |i| create_page(title: "Bulk Page #{i}") }

    results = get_results(q: "Bulk")
    assert_operator results.size, :<=, 20
  end

  test "signed out is redirected to sign in" do
    get "/cs-studio/link_targets", params: { q: "x" }

    assert_response :redirect
    assert_redirected_to admin_sign_in_path
  end

  private

  def get_results(**params)
    get "/cs-studio/link_targets", params: params
    assert_response :success
    response.parsed_body
  end
end
