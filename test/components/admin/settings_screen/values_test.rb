require "test_helper"

class Admin::SettingsScreen::ValuesTest < ActiveSupport::TestCase
  setup do
    @site = SiteSetting.instance
    @site.update!(locales: [ { "code" => "en" }, { "code" => "de", "fallbacks" => [ "en" ] }, { "code" => "es" } ],
      mail_server: "smtp.saved.test", mail_port: 587, social_links: { "Mastodon" => "https://social.example/@site" })
    Mobility.with_locale(:de) { @site.update!(title: "Die Seite") }
  end

  def values(submitted)
    Admin::SettingsScreen::Values.new(site: @site, submitted: ActionController::Parameters.new(submitted).permit!, stored: @site)
  end

  # After a refused or stale save the browser's baseline is what was typed,
  # so only the server can say which fields are unsaved.
  test "Values#changed_fields lists the wrappers whose typed value differs from the stored settings, per language and per row, and nothing on a plain load" do
    assert_empty Admin::SettingsScreen::Values.new(site: @site, stored: @site).changed_fields

    # The whole form resent as stored: nothing differs. A security never
    # chosen sends the option the card shows ticked.
    @site.update!(mail_security: nil)
    same = values(
      translations: { "en" => { title: @site.title(locale: "en").to_s, tagline: @site.tagline(locale: "en").to_s }, "de" => { title: "Die Seite", tagline: "" } },
      mail_server: "smtp.saved.test", mail_port: "587", mail_security: MailSettings::DEFAULT_SECURITY, social_links_present: "1", social_links: { "0" => { name: "Mastodon", url: "https://social.example/@site" } },
      languages: [ { code: "en" }, { code: "de", fallback: "en" }, { code: "es", fallback: "" } ]
    )
    assert_empty same.changed_fields

    typed = values(
      translations: { "en" => { title: @site.title(locale: "en").to_s }, "de" => { title: "Die neue Seite", tagline: "" } },
      mail_server: "smtp.typed.test", mail_port: "abc", social_links_present: "1", social_links: {},
      languages: [ { code: "de", fallback: "" }, { code: "en" }, { code: "es", fallback: "" } ], remove_logo: "1"
    )
    assert_equal %w[title.de mail_server mail_port social_links language_order languages.de.fallback logo].sort, typed.changed_fields.sort
  end

  test "the logo is read from the stored row, not the record holding what was typed" do
    stored = SiteSetting.find(@site.id)
    assert_same stored.logo, Admin::SettingsScreen::Values.new(site: @site, submitted: ActionController::Parameters.new({}).permit!, stored: stored).logo
  end
end
