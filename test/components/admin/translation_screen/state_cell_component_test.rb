require "test_helper"

# A Translations cell (layout points spec, decision 7): the state as the
# chip's mark and a word; the column's header names the language.
class Admin::TranslationScreen::StateCellComponentTest < ViewComponent::TestCase
  test "each state is the chip's mark and its word, and no language code" do
    { complete: "Translated", missing: "Missing", outdated: "Outdated" }.each do |state, word|
      render_inline Admin::TranslationScreen::StateCellComponent.new(state: state, locale: "de")

      assert_selector "span[data-locale=de][data-translation-state=#{state}]", exact_text: (state == :outdated ? "↻#{word}" : word)
      assert_selector "[data-translation-mark=#{state}][aria-hidden=true]", visible: :all
    end
    render_inline Admin::TranslationScreen::StateCellComponent.new(state: :missing, locale: "de")
    assert_selector "[data-translation-mark=missing][class~='border-field-line'][class~='border-[1.5px]']"
    assert_no_selector "[class*=danger]"
  end

  test "an unknown state is refused" do
    assert_raises(KeyError) { render_inline Admin::TranslationScreen::StateCellComponent.new(state: :lost, locale: "de") }
  end
end
