require "test_helper"

# One language's card on the translations matrix (design pass round 2, Task
# 18): its own name, "% done" over items, a bar, "12 missing · 1 outdated".
class Admin::TranslationScreen::SummaryCardComponentTest < ViewComponent::TestCase
  setup { with_locales(%w[en de es], default: "en") }

  def card(summary) = render_inline(Admin::TranslationScreen::SummaryCardComponent.new(locale: "de", summary:))

  test "shows the language in its own language, the percentage, the bar and the counts" do
    card(total: 20, complete: 7, missing: 12, outdated: 1)

    assert_selector "[data-locale=de]", text: /Deutsch/
    assert_text "35% done"
    assert_selector "[role=progressbar][aria-label='Deutsch translated'][aria-valuenow='35']"
    assert_text "12 missing · 1 outdated"
    assert_selector ".text-warn-ink", text: "12 missing · 1 outdated"
  end

  test "a finished language says so and an empty site reads 0%" do
    card(total: 4, complete: 4, missing: 0, outdated: 0)
    assert_text "100% done"
    assert_text "All translated"
    assert_no_selector ".text-warn-ink"

    card(total: 0, complete: 0, missing: 0, outdated: 0)
    assert_text "0% done"
  end

  test "never red" do
    html = card(total: 3, complete: 0, missing: 2, outdated: 1).to_html
    assert_no_match(/danger/, html)
  end
end
