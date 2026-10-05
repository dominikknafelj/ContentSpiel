require "test_helper"

# `Admin::AdminComponent#t`: a relative key reads under
# `admin.components.<the component's own scope>` (docs/reference/i18n.md),
# anything else is passed on to the view context's `t` untouched.
class Admin::AdminComponentTest < ViewComponent::TestCase
  # A component with nothing but a lookup, to ask `t` things the real ones
  # don't. Its scope is `i18n_probe`.
  class ::Admin::I18nProbeComponent < Admin::AdminComponent
    def initialize(key, **options)
      @key = key
      @options = options
    end

    def call = tag.span(t(@key, **@options))
  end

  setup do
    I18n.backend.store_translations(:en, admin: { components: { i18n_probe: {
      plain: "Plain %{name}", safe_html: "<b>%{name}</b>", count: { one: "%{count} thing", other: "%{count} things" }
    } } })
  end

  test "the scope is the class name without Admin:: and Component, one segment per namespace" do
    assert_equal "confirm_dialog", Admin::ConfirmDialogComponent.translation_scope
    assert_equal "editor_screen.header", Admin::EditorScreen::HeaderComponent.translation_scope
    assert_equal "i18n_probe", Admin::I18nProbeComponent.translation_scope
  end

  test "t(\".cancel\") in the confirm dialog reads admin.components.confirm_dialog.cancel" do
    assert_equal "Cancel", I18n.t("admin.components.confirm_dialog.cancel")

    I18n.backend.store_translations(:en, admin: { components: { confirm_dialog: { cancel: "Dismiss it" } } })
    render_inline Admin::ConfirmDialogComponent.new(id: "d", title: "T")
    assert_selector "form[method='dialog'] button", text: "Dismiss it"
  ensure
    I18n.backend.store_translations(:en, admin: { components: { confirm_dialog: { cancel: "Cancel" } } })
  end

  test "a missing key raises, relative or absolute" do
    assert_raises(I18n::MissingTranslationData) { render_inline Admin::I18nProbeComponent.new(".nope") }
    assert_raises(I18n::MissingTranslationData) { render_inline Admin::I18nProbeComponent.new("admin.components.i18n_probe.nope") }
  end

  test "a key that is not relative is not rescoped" do
    render_inline Admin::I18nProbeComponent.new("admin.components.i18n_probe.plain", name: "x")

    assert_text "Plain x"
  end

  test "interpolation and pluralisation work" do
    render_inline Admin::I18nProbeComponent.new(".plain", name: "Dom")
    assert_text "Plain Dom"

    render_inline Admin::I18nProbeComponent.new(".count", count: 1)
    assert_text "1 thing"
    render_inline Admin::I18nProbeComponent.new(".count", count: 2)
    assert_text "2 things"
  end

  test "a _html key is html safe and what is interpolated into it is escaped" do
    render_inline Admin::I18nProbeComponent.new(".safe_html", name: "<i>x</i>")

    assert_selector "b", text: "<i>x</i>"
    assert_no_selector "b i"
  end
end
