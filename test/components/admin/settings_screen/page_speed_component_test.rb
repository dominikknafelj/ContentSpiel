require "test_helper"

class Admin::SettingsScreen::PageSpeedComponentTest < ViewComponent::TestCase
  RADIO = "input[type=radio][name='site_setting[stylesheet_mode]']".freeze

  # A built stylesheet of a given compressed size, which Automatic draws in
  # or links as `inline` says.
  Served = Data.define(:compressed_size, :automatic) do
    def inline?(mode) = mode.to_s == "automatic" ? automatic : ThemeCss.inline_for?(mode, compressed_size)
  end

  def render_card(mode: "automatic", stylesheet: Served.new(compressed_size: 9_421, automatic: true), changed: false)
    site = SiteSetting.instance
    site.stylesheet_mode = mode
    values = Admin::SettingsScreen::Values.new(site: site)
    values.define_singleton_method(:saved_change) { |_name| "saved" } if changed
    render_inline Admin::SettingsScreen::PageSpeedComponent.new(values: values, stylesheet: stylesheet)
  end

  test "the card's heading and intro, the legend, and the three tiles in order with the chosen one checked" do
    render_card(mode: "file")

    assert_selector "section#settings-page_speed-card h2#page_speed", text: "Page speed"
    assert_text "How visitors' browsers get your theme's stylesheet. A change applies to the next page they open."
    assert_selector "fieldset[role=radiogroup] > legend", text: "Theme stylesheet"
    assert_equal %w[automatic inline file], page.all(RADIO, visible: :all).map(&:value)
    assert_equal [ "Automatic", "Always in the page", "Always a separate file" ], page.all("label span.font-semibold").map(&:text)
    assert_selector "#{RADIO}[value=file][checked]", visible: :all
    assert_selector "#{RADIO}[checked]", visible: :all, count: 1
    assert_selector "#settings-stylesheet_mode-help", text: /\ABehind a CDN that sends Early Hints \(on Cloudflare: Speed › Optimization › Early Hints\)/
  end

  test "the size line's three forms: put in the page, linked as a separate file, not built yet" do
    render_card(stylesheet: Served.new(compressed_size: 9_421, automatic: true))
    assert_selector "#settings-stylesheet_mode-size", exact_text: "Your theme's stylesheet is 9.2 KB compressed, so Automatic puts it in the page."

    render_card(mode: "inline", stylesheet: Served.new(compressed_size: 21_914, automatic: false))
    assert_selector "#settings-stylesheet_mode-size", exact_text: "Your theme's stylesheet is 21.4 KB compressed, so Automatic links it as a separate file."

    render_card(stylesheet: nil)
    assert_selector "#settings-stylesheet_mode-size", exact_text: "The stylesheet's size is known once it is built."
  end

  test "the group is described by the size line and the CDN help, and a saved change marks the wrapper" do
    render_card(changed: true)

    assert_selector "fieldset[aria-describedby='settings-stylesheet_mode-size settings-stylesheet_mode-help']"
    assert_selector "[data-field-name=stylesheet_mode][data-save-bar-changed=saved] > fieldset:first-child > legend"
  end
end
