require "test_helper"

# System status (design spec §6.1): the setup wizard's own read-only
# `Setup::SystemCheck` results, re-run on every load ("Run again" is a
# plain reload).
class Admin::SystemStatusTest < ActionDispatch::IntegrationTest
  setup { site_settings(:default).update!(setup_completed_at: Time.current) }

  test "requires sign-in" do
    get "/cs-studio/system_status"
    assert_redirected_to "/cs-studio/sign-in"
  end

  test "renders every SystemCheck result, with Run again" do
    sign_in_as(users(:one))

    get "/cs-studio/system_status"

    assert_response :success
    Setup::SystemCheck.run.each do |result|
      assert_select "li", text: /#{result.ok? ? "OK" : "Warning"}.*#{Regexp.escape(result.label)}/m
    end
    assert_select "a[href='/cs-studio/system_status']", text: "Run again"
    assert_select "nav[aria-label='Modules'] a[href='/cs-studio/system_status']", text: "System status"
  end
end
