require "test_helper"

class SetupSiteStepsTest < ActionDispatch::IntegrationTest
  setup do
    start_fresh_install
    verify_setup_token
    create_setup_admin
  end

  test "the site step renders the current settings" do
    get setup_step_path("site")

    assert_response :success
    assert_select "input[name='site_setting[title]'][value=?]", "Test Site"
  end

  test "saving site identity keeps complete social links and drops half-filled rows" do
    patch setup_step_path("site"), params: { site_setting: {
      title: "Dana's Notes", tagline: "Things I learned",
      social_links: [
        { name: "GitHub", url: "https://github.com/dana" },
        { name: "Mastodon", url: "" },
        { name: "", url: "https://example.org" },
        { name: "", url: "" }
      ]
    } }

    assert_redirected_to setup_step_path("languages")
    setting = SiteSetting.instance
    assert_equal "Dana's Notes", setting.title
    assert_equal "Things I learned", setting.tagline
    assert_equal({ "GitHub" => "https://github.com/dana" }, setting.social_links)
  end

  test "a blank title is rejected" do
    patch setup_step_path("site"), params: { site_setting: { title: " ", social_links: [ { name: "", url: "" } ] } }

    assert_response :unprocessable_entity
    assert_includes response.body, "Title can&#39;t be blank"
  end

  test "choosing the default language" do
    get setup_step_path("languages")
    assert_response :success
    assert_includes response.body, "Deutsch"

    patch setup_step_path("languages"), params: { site_setting: { default_locale: "de" } }

    assert_redirected_to setup_step_path("mcp_token")
    assert_equal "de", SiteSetting.instance.default_locale
  end

  test "an unsupported language is rejected" do
    patch setup_step_path("languages"), params: { site_setting: { default_locale: "fr" } }

    assert_response :unprocessable_entity
  end
end
