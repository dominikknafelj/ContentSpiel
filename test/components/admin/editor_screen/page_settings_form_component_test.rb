require "test_helper"

# The page settings panel's field details (design pass round 2, Task 10,
# handoff §9 B22 / §10 A1): the slug's help line, soft character counters under
# SEO, and the hero's per-page alt override with its Reset.
class Admin::EditorScreen::PageSettingsFormComponentTest < ViewComponent::TestCase
  include ContentHelper

  def render_settings(page, locale: "en")
    as_owner { render_inline Admin::EditorScreen::PageSettingsFormComponent.new(page: page, locale: locale) }
  end

  def landing_with_hero(alt: "A dog on a beach", hero_alt: nil)
    asset = create_media_asset
    asset.update!(alt: alt)
    translations = { Locales.default => { title: "Landing" } }
    translations[Locales.default][:hero_alt] = hero_alt if hero_alt
    Pages::Save.call(attributes: { parent: root_page, page_type: :landing, published: true, hero_media_asset_id: asset.id },
      translations: translations).record
  end

  test "the slug carries its help text" do
    render_settings(create_page(title: "About"))

    assert_text "The last part of the page’s address. Changing it leaves a redirect from the old address."
  end

  test "SEO is a collapsed details with soft counters at 60 and 160 characters" do
    page = create_page(title: "About")
    page.update!(meta_title: "Hello", meta_description: "A description")
    render_settings(page.reload)

    assert_selector "details.admin-page-settings__seo:not([open]) summary", text: "SEO · META TITLE, META DESCRIPTION"
    assert_selector "[data-controller='admin--ui--char-count'][data-admin--ui--char-count-limit-value='60'] input[name='page[meta_title]']", visible: :all
    assert_selector "[data-controller='admin--ui--char-count'][data-admin--ui--char-count-limit-value='160'] textarea[name='page[meta_description]']", visible: :all
    assert_selector "[data-admin--ui--char-count-target='output']", text: "5 / 60", visible: :all
    assert_selector "[data-admin--ui--char-count-target='output']", text: "13 / 160", visible: :all
    assert_no_selector "input[name*='share'], input[name*='og_image']", visible: :all
  end

  test "a landing page's hero alt placeholder is the library alt and there is no Reset without an override" do
    render_settings(landing_with_hero)

    assert_selector "input[name='page[hero_alt]'][placeholder='A dog on a beach']"
    assert_text "Empty uses the alt text from Media"
    assert_selector "button", text: "Reset", visible: :all, count: 1
    assert_selector "[data-admin--ui--override-field-target='reset'][hidden]", visible: :all
    assert_selector "[data-admin--ui--override-field-target='library'][hidden]", visible: :all
  end

  test "an overridden hero alt shows Reset and the library text beneath" do
    render_settings(landing_with_hero(hero_alt: "My own alt"))

    assert_selector "input[name='page[hero_alt]'][value='My own alt']"
    assert_no_selector "[data-admin--ui--override-field-target='reset'][hidden]", visible: :all
    assert_selector "[data-admin--ui--override-field-target='library']:not([hidden])", text: "A dog on a beach"
    assert_selector "button[data-action='admin--ui--override-field#reset']", text: "Reset"
  end

  # ----- Held (live-editing Task 7; handoff 9, 23) -----

  def render_for(viewer, tab, page)
    as_viewer(viewer, tab: tab) { render_inline Admin::EditorScreen::PageSettingsFormComponent.new(page: page, locale: "en") }
  end

  def controls = form_controls

  test "held by someone else: the strip 'is editing the page settings' at the top, the unit says held, no autosave controller, the same controls read-only" do
    page = create_page(title: "Held settings")
    dana = users(:two)
    dana.update!(name: "Dana Weiss")
    render_for(users(:one), "tab-aaaaaaaa", page)
    editable_controls = controls
    assert_selector "form[data-controller~='admin--saving--autosave']"

    reserve(page, page, dana, "tab-bbbbbbbb")
    render_for(users(:one), "tab-aaaaaaaa", page)

    assert_selector "details#page-settings[data-editing-held=true] > summary + #page-hold[data-editing-strip-slot] [data-editing-kind=held]", text: "Dana Weiss is editing the page settings"
    assert_no_selector "[data-controller~='admin--saving--autosave']"
    assert_equal editable_controls, controls
    assert_selector "fieldset.admin-held input[name='page[title]'][readonly]"
    assert_selector "fieldset.admin-held select[name='page[page_type]'][disabled]"
    assert_selector "button[data-action='admin--editing--hold#takeOver']", text: "Take over"
  end

  test "held by the viewer in this tab it is drawn as ever, and held by nobody the slot is empty" do
    page = create_page(title: "Own settings")
    render_for(users(:one), "tab-aaaaaaaa", page)
    assert_selector "#page-hold[data-editing-strip-slot]:empty"

    reserve(page, page, users(:one), "tab-aaaaaaaa")
    render_for(users(:one), "tab-aaaaaaaa", page)
    assert_selector "form[data-controller~='admin--saving--autosave']"
    assert_no_selector "[data-editing-held]"
  end

  test "someone who may only read sees the strip without Take over" do
    page = create_page(title: "Read settings")
    reserve(page, page, users(:two), "tab-bbbbbbbb")

    render_for(users(:reader), "tab-aaaaaaaa", page)

    assert_selector "#page-hold [data-editing-kind=held]"
    assert_no_selector "button", text: "Take over"
  end
end
