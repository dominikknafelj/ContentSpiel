require "test_helper"

class AvoSiteSettingsTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:one)) }

  test "the site settings menu entry opens the settings form directly" do
    get "/avo/resources/site_settings"

    assert_response :redirect
    assert_equal "/avo/resources/site_settings/#{site_settings(:default).id}/edit", URI.parse(response.location).path
  end

  test "social links are edited as name/URL rows" do
    get "/avo/resources/site_settings/#{site_settings(:default).id}/edit"

    assert_response :success
    assert_includes response.body, "Network"
  end
end
