require "test_helper"

class Admin::LanguageTabsComponentTest < ViewComponent::TestCase
  # Enabled locales in the default SiteSetting fixture: en (default), de, es.
  setup { @url = ->(code) { "/x?locale=#{code}" } }

  test "underline tabs in each language's own name, the current one marked" do
    render_inline(Admin::LanguageTabsComponent.new(current: "de", url: @url))
    assert_selector "nav.admin-language-tabs[aria-label='Languages']"
    assert_selector "[aria-current=true]", text: "Deutsch"
    assert_selector "a[href='/x?locale=en'][data-turbo-frame=_top]", text: "English"
    assert_no_selector "a", text: "Deutsch"
  end

  test "missing is a hollow ring, outdated a solid warn dot, each with screen-reader text and no red" do
    render_inline(Admin::LanguageTabsComponent.new(current: "en", missing: %w[de], outdated: %w[es], url: @url))
    assert_selector "span.border-meta[data-language-state=missing]"
    assert_selector "span.bg-warn[data-language-state=outdated]##{Admin::LanguageTabsComponent.outdated_marker_id('es')}"
    assert_selector ".sr-only", text: "Deutsch: not translated"
    assert_selector ".sr-only", text: "Español: original changed"
    assert_no_selector "[class*=danger]"
    # The sentences sit inside the marks, so removing the marker by id
    # (Still correct — mark up to date) removes the announcement too.
    assert_selector "##{Admin::LanguageTabsComponent.outdated_marker_id('es')} .sr-only", text: "Español: original changed"
    assert_selector "[data-language-state=missing] .sr-only", text: "Deutsch: not translated"
    assert_selector "[title='Original changed']", count: 1
    assert_selector "[title='Missing required fields']", count: 1
  end

  test "no markers when nothing is missing or outdated" do
    render_inline(Admin::LanguageTabsComponent.new(current: "en", url: @url))
    assert_no_selector "[data-language-state]"
  end

  test "the outdated marker id is unchanged so Turbo Streams keep working" do
    assert_equal "language-switcher-outdated-de", Admin::LanguageTabsComponent.outdated_marker_id("de")
  end

  # Minitest 6 ships without `stub` here, so the enabled list and names are
  # swapped by hand on Locales' singleton and always put back.
  test "more than the visible number collapse into +N, keeping the current language visible" do
    with_locales(%w[en de es fr it pt]) do
      render_inline(Admin::LanguageTabsComponent.new(current: "pt", url: @url, visible: 4))
      assert_selector "nav > ul > li", count: 5 # four tabs + the overflow
      assert_selector "[aria-current=true]", text: "PT"
      assert_selector "button[aria-haspopup=menu]", text: "+2"
      assert_selector "[role=menu] a", count: 2, visible: :all
    end
  end

  test "buttons mode draws a tab per language that only switches, the current one selected, with no name" do
    render_inline(Admin::LanguageTabsComponent.new(current: "de", mode: :buttons, missing: %w[es], outdated: %w[de],
      button_data: ->(code) { { code: code, action: "x#select" } }, panel_id: ->(code) { "panel-#{code}" }))

    assert_selector "ul[role=tablist] button[type=button][role=tab]", count: 3
    assert_selector "button[role=tab][aria-selected=true][aria-controls=panel-de][data-code=de]", text: "Deutsch"
    assert_selector "button[role=tab][aria-selected=false][aria-controls=panel-en]", text: "English"
    assert_no_selector "a"
    assert_no_selector "button[name]"
    assert_selector "##{Admin::LanguageTabsComponent.outdated_marker_id('de')}"
    assert_selector "[data-language-state=missing]", count: 1
  end

  test "buttons mode never collapses into a +N menu" do
    with_locales(%w[en de es fr it pt]) do
      render_inline(Admin::LanguageTabsComponent.new(current: "en", mode: :buttons, visible: 2))
      assert_selector "button[role=tab]", count: 6
      assert_no_selector "button[aria-haspopup=menu]"
    end
  end

  test "an unknown mode is refused" do
    assert_raises(ArgumentError) { Admin::LanguageTabsComponent.new(current: "en", mode: :tabs) }
  end

  private

  def with_locales(codes)
    original_enabled = Locales.method(:enabled)
    original_name = Locales.method(:name)
    Locales.define_singleton_method(:enabled) { codes }
    Locales.define_singleton_method(:name) { |code, **| code.to_s.upcase }
    yield
  ensure
    Locales.define_singleton_method(:enabled, original_enabled)
    Locales.define_singleton_method(:name, original_name)
  end
end
