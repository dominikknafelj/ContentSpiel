require "test_helper"

# The instant filter forms (design pass spec §4): wired to `admin--ui--auto-submit`
# and aimed at the `content` frame, no Filter button outside a <noscript>, and
# a Clear link only while a filter is set.
class Admin::FiltersTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
  end

  {
    "posts" => "/cs-studio/posts",
    "media" => "/cs-studio/media",
    "audit log" => "/cs-studio/audit_events"
  }.each do |name, path|
    test "the #{name} filter form applies as you change it" do
      get path
      assert_response :success
      assert_select "form[data-controller='admin--ui--auto-submit'][data-turbo-frame='content'][data-turbo-action='replace'][method=get]" do
        assert_select "form > button[type=submit]", count: 0 # the only Filter button lives in <noscript>
        assert_select "noscript button[type=submit]", text: "Filter"
        assert_select "a", text: "Clear", count: 0
      end
    end
  end

  test "Clear appears only while a filter is set" do
    get "/cs-studio/posts", params: { q: "zzz-no-such-title" }
    assert_select "a[href='/cs-studio/posts']", text: "Clear"
  end

  test "a filtered list with no matches says which filters, and offers Clear filters" do
    get "/cs-studio/posts", params: { q: "zzz-no-such-title", status: "draft" }
    assert_select "h3", text: "No matches"
    assert_select "p", text: /status draft and title zzz-no-such-title/
    assert_select "a[href='/cs-studio/posts']", text: "Clear filters"

    get "/cs-studio/audit_events", params: { event_action: "no.such.action" }
    assert_select "h3", text: "No matches"
    assert_select "a", text: "Clear filters"
  end

  # Pager and "Load older" links are built from each list's known filter
  # keys (`Admin::ListLinksHelper#list_params`), never the raw query string:
  # route-option keys in it (`script_name`, `host`, `anchor`) would otherwise
  # shape the URL itself.
  EVIL = { script_name: "//evil.example", host: "evil.example", anchor: "x" }.freeze

  test "route-option params never reach the media pager, and real filters are kept" do
    50.times { |i| create_media_asset.update!(title: "needle #{i}") }
    get "/cs-studio/media", params: EVIL.merge(q: "needle")
    assert_response :success
    assert_no_match(/evil\.example/, response.body)
    assert_select "nav[aria-label='Pagination'] a[href*='q=needle'][href*='page=2']"
    assert_select "nav[aria-label='Pagination']", text: /1–48 OF 50/ # the searched total, not the whole library
  end

  test "route-option params never reach the media picker pager" do
    50.times { create_media_asset }
    get "/cs-studio/media", params: EVIL.merge(picker: 1, filter: "unused")
    assert_response :success
    assert_no_match(/evil\.example/, response.body)
    assert_select "nav[aria-label='Pagination'] a[href*='picker=1'][href*='page=2']"
  end

  test "route-option params never reach the trash pager" do
    Current.set(actor: users(:one)) { 51.times { |n| Trash::Move.call(create_post(title: "Gone #{n}")) } }
    get "/cs-studio/trash", params: EVIL.merge(type: "post")
    assert_response :success
    assert_no_match(/evil\.example/, response.body)
    assert_select "nav[aria-label='Pagination'] a[href*='type=post'][href*='page=2']"
  end

  test "route-option params never reach the translations pager" do
    51.times { |n| create_post(title: "Post #{n}") }
    get "/cs-studio/translations", params: EVIL.merge(locale: "de", type: "post")
    assert_response :success
    assert_no_match(/evil\.example/, response.body)
    assert_select "nav[aria-label='Pagination'] a[href*='type=post'][href*='locale=de'][href*='page=2']"
  end

  test "route-option params never reach the audit log's Load older link" do
    51.times { |n| Audit::Event.create!(action: "test.evil", subject_label: "Item #{n}", channel: "admin", occurred_at: n.minutes.ago, last_occurred_at: n.minutes.ago) }
    get "/cs-studio/audit_events", params: EVIL.merge(event_action: "test.evil")
    assert_response :success
    assert_no_match(/evil\.example/, response.body)
    assert_select "a[href*='event_action=test.evil'][href*='offset=50']", text: "Load older"
  end

  test "the media pager's total counts matching assets once, searched or filtered" do
    5.times { |i| create_media_asset.update!(title: "needle #{i}") }
    3.times { |i| create_media_asset.update!(title: "other #{i}") }

    get "/cs-studio/media", params: { q: "needle" }
    assert_select "li[id^='media-asset-']", 5

    # One page only: no pager to read the total from, so pin the count the
    # pager is built on -- `with_variants` is an `includes`, which must not
    # inflate or break `count`.
    scope = Media::Asset.kept.with_variants
    assert_equal 8, scope.count
    assert_equal 5, Media::Search.call(scope, "needle").count
    assert_equal 8, scope.unused.count
  end
end
