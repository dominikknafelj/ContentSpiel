require "test_helper"

class Admin::SettingsScreen::SiteCardComponentTest < ViewComponent::TestCase
  setup do
    @site = SiteSetting.instance
    Mobility.with_locale(:de) { @site.update!(title: "Danas Notizen") }
  end

  def render_card(locale: "en", submitted: nil, errors: nil)
    values = Admin::SettingsScreen::Values.new(site: @site, submitted: submitted)
    as_owner { render_inline Admin::SettingsScreen::SiteCardComponent.new(site_setting: @site, values: values, locale: locale, errors: errors) }
  end

  test "a panel per language holds that language's title and tagline, only the current one visible" do
    render_card(locale: "de")

    assert_selector "h2#site", text: "Site"
    %w[en de es].each do |code|
      assert_selector "[data-language-panel='#{code}'] input#settings-#{code}-title[name='site_setting[translations][#{code}][title]']", visible: :all
      assert_selector "[data-language-panel='#{code}'] input#settings-#{code}-tagline", visible: :all
    end
    assert_selector "[data-language-panel='de']:not([hidden])"
    assert_selector "[data-language-panel='en'][hidden]", visible: :all
    assert_selector "button[role=tab][aria-selected=true]", text: "Deutsch"
    assert_selector "label", text: "Title · translatable", visible: :all, minimum: 3
  end

  test "the tabs are driven by admin--settings--tabs and the pairs sit in a translation form container" do
    render_card

    assert_selector "section[data-controller='admin--settings--tabs'][data-admin--settings--tabs-current-value='en']"
    assert_selector "button[role=tab][data-admin--settings--tabs-target=tab][data-code=de]"
    assert_selector ".admin-translation-form [data-language-panel='de']", visible: :all
  end

  test "a non-default language shows the original in a card with a per-language id" do
    render_card(locale: "de")

    assert_selector "[data-language-panel='de'] [data-original-for='title'] p", text: @site.title(locale: "en")
    assert_selector "#reference-card-site-setting-#{@site.id}-title-de"
    assert_selector "[data-language-panel='en'] [data-original-for]", visible: :all, count: 0
  end

  test "without a logo only the drop zone and its hint are drawn: no NONE square" do
    render_card

    assert_no_text "NONE"
    assert_no_selector "[data-field-name=logo] img, [data-field-name=logo] .bg-sunken"
    assert_selector "input[type=file][name='site_setting[logo]']", visible: :all
    assert_text "PNG, JPEG, GIF or WebP. Without a logo the site title is shown."
    assert_no_selector "input[name='site_setting[remove_logo]']", visible: :all
  end

  test "the time zone, with its help, and one empty social link row with a template for more" do
    render_card

    assert_selector "select[name='site_setting[time_zone]']"
    assert_text "Used for scheduled publishing."
    assert_selector "[data-admin--settings--repeat-rows-target=list] input[name='site_setting[social_links][0][name]'][placeholder='Label, e.g. GitHub']", count: 1
    assert_selector "[data-admin--settings--repeat-rows-target=list] input", count: 2
    assert_selector "[data-admin--settings--repeat-rows-target=list] button[aria-label='Remove link']", count: 1
    assert_selector "template#settings-social-link-template", visible: :all
    assert_selector "button[data-action='admin--settings--repeat-rows#add']", text: "+ Add link"
  end

  test "typed values beat stored ones, and the stored time zone is always an option" do
    submitted = ActionController::Parameters.new(translations: { de: { title: "Typed" } }, time_zone: "Mars/Olympus",
      social_links: { "0" => { name: "GitHub", url: "github.com/x" }, "1" => { name: "", url: "" } }).permit!
    render_card(locale: "de", submitted: submitted)

    assert_selector "input#settings-de-title[value='Typed']"
    assert_selector "select[name='site_setting[time_zone]'] option[selected][value='Mars/Olympus']"
    assert_selector "input[name='site_setting[social_links][0][url]'][value='github.com/x']"
    assert_selector "[data-admin--settings--repeat-rows-target=list] input[name$='[name]']", count: 2
  end
end
