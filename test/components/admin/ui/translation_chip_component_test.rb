require "test_helper"

class Admin::Ui::TranslationChipComponentTest < ViewComponent::TestCase
  test "done is a solid chip with a filled ok dot" do
    render_inline(Admin::Ui::TranslationChipComponent.new(state: :complete, locale: "de"))
    assert_selector ".admin-translation-chip.border-line-strong.text-ink[data-translation-state=complete][data-locale=de]", exact_text: "de"
    assert_selector ".admin-translation-chip [data-translation-mark=complete][class~='bg-ok'][class~='rounded-full'][aria-hidden=true]"
    assert_selector "[role=img][aria-label='Deutsch: translated'][title='Translated']"
  end

  test "missing is dashed with a hollow ring in the field line, 1.5px, never red" do
    render_inline(Admin::Ui::TranslationChipComponent.new(state: :missing, locale: "de"))
    assert_selector ".admin-translation-chip.border-dashed.text-meta", exact_text: "de"
    assert_selector ".admin-translation-chip [data-translation-mark=missing][class~='border-field-line'][class~='border-[1.5px]'][aria-hidden=true]"
    assert_selector "[aria-label='Deutsch: not translated'][title='Not translated']"
    assert_no_selector "[class*=danger]"
  end

  test "outdated is warn with a refresh glyph and names the source language" do
    render_inline(Admin::Ui::TranslationChipComponent.new(state: :outdated, locale: "de"))
    assert_selector ".admin-translation-chip.border-warn.text-warn-ink", text: "de ↻"
    assert_selector "[aria-label='Deutsch: outdated']"
    assert_selector "[title='English changed since translation']"
  end

  test "an unknown state is a programming error" do
    assert_raises(ArgumentError) { Admin::Ui::TranslationChipComponent.new(state: :stale, locale: "de") }
  end
end
