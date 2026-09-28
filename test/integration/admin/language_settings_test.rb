require "test_helper"

# The Languages *module* (cs-studio spec §6.1, Task 8) -- deliberately not
# named `languages_test.rb`: `test/integration/admin/languages_test.rb`
# already exists (the page editor's own language switcher/original-language
# tests), and this covers a completely different screen
# (`/cs-studio/settings/languages`, `Admin::LanguagesController`).
class Admin::LanguageSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @site = site_settings(:default)
    @site.update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
  end

  test "lists every enabled language with its own position and fallbacks" do
    @site.update!(locales: [ { "code" => "en" }, { "code" => "de", "fallbacks" => [ "en" ] }, { "code" => "es" } ])

    get "/cs-studio/settings/languages"
    assert_response :success
    assert_select "#language-en"
    assert_select "#language-de select[name='languages[de][position]'] option[selected][value='2']"
    assert_select "#language-de input[name='languages[de][fallbacks][]'][value='en'][checked]"
  end

  test "add language enables a supported language via Locales::Enable" do
    post "/cs-studio/settings/languages", params: { code: "fr" }

    assert_response :redirect
    follow_redirect!
    assert_response :success
    assert_includes @site.reload.locale_codes, "fr"
  end

  test "disable turns a non-default language off via Locales::Disable" do
    @site.update!(locales: [ { "code" => "en" }, { "code" => "de" } ])

    delete "/cs-studio/settings/languages/de"

    assert_response :redirect
    follow_redirect!
    assert_response :success
    assert_not_includes @site.reload.locale_codes, "de"
  end

  test "the default language has no Disable button, and disabling it directly is refused" do
    get "/cs-studio/settings/languages"
    assert_select "#language-en form[action=?]", "/cs-studio/settings/languages/en", count: 0

    delete "/cs-studio/settings/languages/en"
    assert_response :redirect
    follow_redirect!
    assert_includes response.body, "default language can&#39;t be disabled"
    assert_includes @site.reload.locale_codes, "en"
  end

  test "saving fallbacks and a new order writes them through Locales::Configure" do
    @site.update!(locales: [ { "code" => "en" }, { "code" => "de" }, { "code" => "es" } ])

    patch "/cs-studio/settings/languages", params: { languages: {
      "es" => { position: "1", fallbacks: [] },
      "en" => { position: "2", fallbacks: [] },
      "de" => { position: "3", fallbacks: [ "en" ] }
    } }

    assert_response :redirect
    follow_redirect!
    assert_response :success

    @site.reload
    assert_equal %w[es en de], @site.locale_codes
    assert_equal [ "en" ], @site.locale_entry("de")["fallbacks"]
  end

  test "a failed reconfigure (an unenabled fallback) reports the error and changes nothing" do
    @site.update!(locales: [ { "code" => "en" }, { "code" => "de" } ])

    patch "/cs-studio/settings/languages", params: { languages: {
      "en" => { position: "1", fallbacks: [] },
      "de" => { position: "2", fallbacks: [ "fr" ] }
    } }

    assert_response :redirect
    follow_redirect!
    assert_includes response.body, "isn&#39;t enabled"
    assert_nil @site.reload.locale_entry("de")["fallbacks"]
  end
end
