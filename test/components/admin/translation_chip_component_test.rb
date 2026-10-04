require "test_helper"

class Admin::TranslationChipComponentTest < ViewComponent::TestCase
  test "done is a solid chip with no glyph" do
    render_inline(Admin::TranslationChipComponent.new(state: :complete, locale: "de"))
    assert_selector ".admin-translation-chip.border-line-strong.text-ink[data-translation-state=complete][data-locale=de]", exact_text: "de"
    assert_selector "[role=img][aria-label='Deutsch: translated'][title='Translated']"
  end

  test "missing is dashed with a hollow ring glyph, never red" do
    render_inline(Admin::TranslationChipComponent.new(state: :missing, locale: "de"))
    assert_selector ".admin-translation-chip.border-dashed.text-meta", text: "de ○"
    assert_selector "[aria-label='Deutsch: not translated'][title='Not translated']"
    assert_no_selector "[class*=danger]"
  end

  test "outdated is warn with a refresh glyph and names the source language" do
    render_inline(Admin::TranslationChipComponent.new(state: :outdated, locale: "de"))
    assert_selector ".admin-translation-chip.border-warn.text-warn-ink", text: "de ↻"
    assert_selector "[aria-label='Deutsch: outdated']"
    assert_selector "[title='English changed since translation']"
  end

  test "an unknown state is a programming error" do
    assert_raises(ArgumentError) { Admin::TranslationChipComponent.new(state: :stale, locale: "de") }
  end
end
