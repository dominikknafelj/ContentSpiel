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

  # Translation helpers spec §5: the title and tagline are translated, and
  # setup writes them in the site's default language.
  test "the site step writes the title and tagline in the default language" do
    SiteSetting.instance.update!(locales: [ { "code" => "de" }, { "code" => "en" } ], default_locale: "de")

    patch setup_step_path("site"), params: { site_setting: { title: "Danas Notizen", tagline: "Was ich gelernt habe" } }

    assert_redirected_to setup_step_path("languages")
    setting = SiteSetting.instance
    assert_equal "Danas Notizen", setting.title(locale: "de")
    assert_equal "Was ich gelernt habe", setting.tagline(locale: "de")
    assert_nil setting.read_attribute(:tagline)["en"]

    get setup_step_path("site")
    assert_select "input[name='site_setting[title]'][value=?]", "Danas Notizen"
    get setup_step_path("review")
    assert_includes response.body, "Danas Notizen"
  end

  # The site step comes before the languages step, so the title is typed in
  # whatever the default was then; choosing a different default afterwards
  # takes it along rather than leaving the new default without a title
  # (which would refuse the languages step outright).
  test "choosing a different default language afterwards carries the title and tagline into it" do
    patch setup_step_path("site"), params: { site_setting: { title: "Dana's Notes", tagline: "Things I learned" } }
    assert_equal "en", SiteSetting.instance.default_locale

    patch setup_step_path("languages"), params: { site_setting: { default_locale: "de", extra_locales: [ "en" ] } }

    assert_redirected_to setup_step_path("mcp_token")
    setting = SiteSetting.instance
    assert_equal "Dana's Notes", setting.title(locale: "de")
    assert_equal "Things I learned", setting.tagline(locale: "de")
    assert_equal "Dana's Notes", setting.title(locale: "en")
  end
end
