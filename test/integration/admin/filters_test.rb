require "test_helper"

# The instant filter forms (design pass spec §4): wired to `admin--auto-submit`
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
      assert_select "form[data-controller='admin--auto-submit'][data-turbo-frame='content'][data-turbo-action='replace'][method=get]" do
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
end
