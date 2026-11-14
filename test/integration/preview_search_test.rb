require "test_helper"

# A search in the preview searches the live site, as the public site does,
# never the rows the preview otherwise draws, and says so; an editor's
# searches count in the visitors' counters (search spec §7.2, §8.3).
class PreviewSearchTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
  end

  def preview_search(text) = get("/cs-studio/preview", params: { q: text })

  test "words in a page's rows are not found in the preview, and the note is drawn" do
    place_search_block(root_page)
    page = create_page(title: "Albatross")
    assert Pages::Save.call(page.reload, translations: { "en" => { title: "Pelican" } }).ok?

    preview_search "pelican"
    assert_response :success
    assert_equal "none", search_drawn[:state]
    assert search_drawn[:live_note], "the preview says its results are the live site's"

    preview_search "albatross"
    assert_equal [ [ "Albatross", "/albatross" ] ], search_drawn[:results], "the live title, at its public address"
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal "noindex", response.headers["X-Robots-Tag"]
    assert_equal "origin", response.headers["Referrer-Policy"]

    get "/", params: { q: "albatross" }
    assert_not search_drawn[:live_note], "the public site draws no note"
  end

  test "an editor's searches in the preview count against the visitor limit" do
    place_search_block(root_page)
    half = SiteSearch::QueryLimit::VISITOR_LIMIT / 2

    half.times { preview_search "albatross" }
    (SiteSearch::QueryLimit::VISITOR_LIMIT - half).times do
      get "/", params: { q: "albatross" }
      assert_response :success
    end

    preview_search "albatross"
    assert_response :too_many_requests
    assert_equal "limited", search_drawn[:state]
    get "/", params: { q: "albatross" }
    assert_response :too_many_requests, "the same counter, whichever door counted"
  end
end
