require "test_helper"

class Admin::SettingsScreen::GlanceRowComponentTest < ViewComponent::TestCase
  PROGRESS = { total: 0, made: 0, failed: 0 }.freeze

  def render_row(id, site: SiteSetting.instance.reload, mail_settings: MailSettings.current(site, env: {}), progress: PROGRESS,
    locales: %w[en de es], default: "en", ai_result: nil)
    render_inline Admin::SettingsScreen::GlanceRowComponent.new(section: SettingsSections.find(id), site_setting: site, mail_settings: mail_settings,
      images_progress: progress, locales: locales, default: default, ai_result: ai_result)
  end

  def row(id) = "a##{Admin::SettingsScreen::GlanceRowComponent.id_for(id)}"

  def chips(id) = page.all("#{row(id)} .admin-state-chip").map { |chip| [ chip["data-state-tone"], chip.text.strip ] }

  test "languages: the count and the default, with no state chip" do
    render_row("languages")
    assert_selector row("languages"), text: "3 languages"
    assert_selector "#{row('languages')} .text-small.text-dim", text: "English is the default"
    assert_no_selector "#{row('languages')} .admin-state-chip"

    render_row("languages", locales: %w[de], default: "de")
    assert_selector row("languages"), text: "1 language"
    assert_selector row("languages"), text: "Deutsch is the default"
  end

  test "AI translation: Off, No key, Key saved, then Connected or Not connected after a test" do
    site = SiteSetting.instance
    site.update_columns(ai_provider: nil, ai_api_key: nil, ai_api_key_saved_at: nil)
    render_row("ai", site: site.reload)
    assert_equal [ %w[off Off] ], chips("ai")
    assert_selector row("ai"), text: "AI translation"

    site.update_columns(ai_provider: "anthropic")
    render_row("ai", site: site.reload)
    assert_equal [ [ "warn", "No key" ] ], chips("ai")

    site.update!(ai_api_key: "sk-ant-glance-test")
    site.update_columns(ai_api_key_saved_at: Time.zone.local(2020, 10, 2, 12))
    render_row("ai", site: site.reload)
    assert_equal [ [ "ok", "Key saved" ] ], chips("ai")
    assert_no_text "added" # the rail says the state; the date is the card's

    render_row("ai", site: site, ai_result: :connected)
    assert_equal [ %w[ok Connected] ], chips("ai")
    render_row("ai", site: site, ai_result: :failed)
    assert_equal [ [ "danger", "Not connected" ] ], chips("ai")
  end

  test "mail: the four states' words and tones, as the Mail card draws them" do
    Admin::SettingsScreen::MailStateComponent::TONES.each do |state, tone|
      with_mail_state(state) { render_row("mail") }

      assert_equal [ [ tone.to_s, I18n.t("admin.mail.states.#{state}.word") ] ], chips("mail"), state
      assert_selector row("mail"), text: "Mail"
    end
  end

  test "images: Ready, waiting, failed, both, and No images yet" do
    render_row("images", progress: { total: 0, made: 0, failed: 0 })
    assert_equal [ [ "off", "No images yet" ] ], chips("images")

    render_row("images", progress: { total: 20, made: 20, failed: 0 })
    assert_equal [ %w[ok Ready] ], chips("images")

    render_row("images", progress: { total: 20, made: 8, failed: 0 })
    assert_equal [ [ "warn", "12 waiting" ] ], chips("images")

    render_row("images", progress: { total: 20, made: 18, failed: 2 })
    assert_equal [ [ "danger", "2 failed" ] ], chips("images")

    render_row("images", progress: { total: 20, made: 6, failed: 2 })
    assert_equal [ [ "warn", "12 waiting" ], [ "danger", "2 failed" ] ], chips("images")

    render_row("images", progress: { total: 2, made: 0, failed: 1 })
    assert_equal [ [ "warn", "1 waiting" ], [ "danger", "1 failed" ] ], chips("images")
  end

  test "the row is one link to its card's anchor" do
    %w[languages ai mail images].each do |id|
      render_row(id)

      assert_selector "a", count: 1
      assert_selector "a[href='##{id}']#settings-glance-#{id}"
      assert_no_selector "a[data-turbo-frame], a[data-turbo-action]"
      assert_no_selector "button, input, [tabindex]"
      section = SettingsSections.find(id)
      chip = page.find("a").native.element_children.first
      assert_equal [ "span", "true" ], [ chip.name, chip["aria-hidden"] ], id
      assert_includes chip[:class].split, Admin::Ui::IconChipComponent::FAMILIES.fetch(section.family).split.first, id
    end
  end

  test "a section with no row raises where it is named" do
    assert_raises(ArgumentError) { render_row("site") }
  end
end
