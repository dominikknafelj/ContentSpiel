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

  test "saving the site step without a social_links key leaves existing links untouched" do
    SiteSetting.instance.update!(social_links: { "GitHub" => "https://github.com/dana" })

    patch setup_step_path("site"), params: { site_setting: { title: "New Title" } }

    assert_redirected_to setup_step_path("languages")
    assert_equal({ "GitHub" => "https://github.com/dana" }, SiteSetting.instance.social_links)
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
    setting = SiteSetting.instance
    assert_equal "de", setting.default_locale
    # No `extra_locales` submitted alongside it -- the endpoint writes
    # exactly the codes it was given, so the default becomes the site's only
    # enabled language rather than silently keeping whichever ones were
    # enabled before.
    assert_equal [ "de" ], setting.locale_codes
  end

  # Covers the endpoint actually enabling every submitted language (spec
  # §4.4), not just recording the choice of default: setup runs before any
  # page or post exists, so unlike `Locales::Enable` (which also backfills
  # slugs for *existing* content -- there is none yet here), all
  # `update_languages` needs to do is make `Locales.enabled` return the new
  # list and rebuild `public_paths` so it's not left stale for whatever gets
  # created next. A page created right after this step, still within the
  # wizard, proves the newly-enabled language is already live.
  test "additional languages are enabled alongside the default" do
    patch setup_step_path("languages"), params: { site_setting: {
      default_locale: "de", extra_locales: [ "en", "fr" ]
    } }

    assert_redirected_to setup_step_path("mcp_token")
    assert_equal %w[de en fr], SiteSetting.instance.locale_codes

    about = create_page(title: "About")
    assert_equal "/about", about.full_path("fr")
  end

  test "an unsupported language is rejected" do
    patch setup_step_path("languages"), params: { site_setting: { default_locale: "xx" } }

    assert_response :unprocessable_entity
  end
end
