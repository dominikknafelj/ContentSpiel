require "test_helper"

# Settings → Page speed: how visitors' browsers get the theme's stylesheet
# (`SiteSetting#stylesheet_mode`, `ThemeCss.inline_for?`). One field of the
# Settings form, saved with its save bar, audited as a settings change, and
# for `settings.manage` alone. What each mode does to a public page is
# `test/integration/public_stylesheet_test.rb`'s.
class Admin::SettingsPageSpeedTest < ActionDispatch::IntegrationTest
  WORDS = "admin.components.settings_screen.page_speed".freeze
  RADIO = "input[type=radio][name='site_setting[stylesheet_mode]']".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @site = site_settings(:default)
    sign_in_as(users(:one))
  end

  def save(fields)
    patch "/cs-studio/settings", params: { site_setting: fields, base_updated_at: @site.reload.updated_at.iso8601(6) }
  end

  test "the card is last, in the Settings form, a radiogroup of three tiles named by its legend with the stored choice checked" do
    get "/cs-studio/settings"

    assert_equal "#page_speed", css_select("nav[aria-label='Settings sections'] a").last["href"]
    assert_select "nav a[href='#page_speed']", "Page speed"
    assert_select "form#settings-form #settings-page_speed-card h2#page_speed", "Page speed"
    assert_select "#settings-page_speed-card", text: /How visitors' browsers get your theme's stylesheet\. A change applies to the next page they open\./
    assert_select "#settings-page_speed-card [data-field-name=stylesheet_mode] > fieldset:first-child[role=radiogroup][aria-labelledby=settings-stylesheet_mode-legend]" do
      assert_select "legend#settings-stylesheet_mode-legend", "Theme stylesheet"
      assert_equal ThemeCss::MODES, css_select(RADIO).map { |radio| radio["value"] }
      assert_select "#{RADIO}[checked]", 1
      assert_select "#{RADIO}[value=automatic][checked]"
      assert_select "label", text: /Automatic\s+In the page while it is small \(14 KB or less, compressed\), otherwise a separate file\./
      assert_select "label", text: /Always in the page\s+The first page a visitor opens draws sooner\. Every later page downloads the stylesheet again\./
      assert_select "label", text: /Always a separate file\s+The browser keeps the file and reuses it on every later page\. The first page waits for one more request\./
    end
    assert_select "#settings-stylesheet_mode-help", I18n.t("#{WORDS}.cdn_help")
    assert_select "#settings-glance-page_speed", 0
  end

  test "the size line says the served stylesheet's compressed size and what Automatic does with it, whatever is chosen" do
    size = ThemeCss.kilobytes(Theme::Stylesheet.current.compressed_size)
    @site.update!(stylesheet_mode: "file")
    get "/cs-studio/settings"
    assert_select "#settings-stylesheet_mode-size", "Your theme's stylesheet is #{size} KB compressed, so Automatic puts it in the page."

    Theme::Stylesheet.with_limit(1) { get "/cs-studio/settings" }
    assert_select "#settings-stylesheet_mode-size", "Your theme's stylesheet is #{size} KB compressed, so Automatic links it as a separate file."

    with_singleton_override(Theme::Stylesheet, :current, -> { nil }) { get "/cs-studio/settings" }
    assert_select "#settings-stylesheet_mode-size", "The stylesheet's size is known once it is built."
  end

  test "the choice is saved and recorded as settings.updated with the old and new mode" do
    save(stylesheet_mode: "inline")
    assert_redirected_to "/cs-studio/settings"
    assert_equal "inline", @site.reload.stylesheet_mode
    assert_equal [ "automatic", "inline" ], Audit::Event.where(action: "settings.updated").order(:id).last.field_changes["stylesheet_mode"]

    follow_redirect!
    assert_select "#{RADIO}[value=inline][checked]"

    save(stylesheet_mode: "file")
    assert_equal "file", @site.reload.stylesheet_mode
  end

  test "a value that is no mode is refused under the field, keeps the stored one and marks the field unsaved" do
    @site.update!(stylesheet_mode: "file")
    assert_no_difference -> { Audit::Event.where(action: "settings.updated").count } do
      save(stylesheet_mode: "always")
    end

    assert_response :unprocessable_entity
    assert_select "#settings-stylesheet_mode-errors", /Theme stylesheet must be Automatic, Always in the page or Always a separate file\./
    assert_select "[data-field-name=stylesheet_mode][data-save-bar-changed=saved]"
    assert_select "a[href='#settings-stylesheet_mode-automatic']", /Theme stylesheet must be/
    assert_equal "file", @site.reload.stylesheet_mode
  end

  test "the column holds the three modes itself" do
    assert_raises(ActiveRecord::CheckViolation) { SiteSetting.transaction(requires_new: true) { @site.update_columns(stylesheet_mode: "always") } }
    assert_raises(ActiveRecord::NotNullViolation) { SiteSetting.transaction(requires_new: true) { @site.update_columns(stylesheet_mode: nil) } }
  end

  test "a viewer without settings.manage neither sees nor saves it" do
    languages_only = User.create!(email_address: "languages-only@example.com", password: "a long enough password")
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "languages.manage", scope: {})
    AccessControl::Membership.create!(user: languages_only, group: access_control_groups(:branch_editors))
    sign_in_as(languages_only)

    get "/cs-studio/settings"
    assert_response :success
    assert_select "#page_speed, #settings-page_speed-card, nav a[href='#page_speed']", 0
    assert_select RADIO, 0

    assert_difference -> { Audit::Event.where(action: "access.denied").count }, 1 do
      save(stylesheet_mode: "inline")
    end
    assert_response :forbidden
    assert_equal "automatic", @site.reload.stylesheet_mode

    sign_in_as(users(:reader))
    save(stylesheet_mode: "inline")
    assert_response :forbidden
    assert_equal "automatic", @site.reload.stylesheet_mode
  end
end
