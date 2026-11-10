require "test_helper"

# One language's tile on the Translations screen: its own name, "% done" over
# items, a bar, and how many are outdated or missing. The whole tile is the
# link that narrows the matrix to the language.
class Admin::TranslationScreen::SummaryCardComponentTest < ViewComponent::TestCase
  setup { with_locales(%w[en de es], default: "en") }

  def card(url: "/x?language=de", current: false, **summary)
    render_inline(Admin::TranslationScreen::SummaryCardComponent.new(locale: "de", summary:, url:, current:))
  end

  test "shows the language in its own language, the percentage, the bar and the counts" do
    card(total: 20, complete: 7, missing: 12, outdated: 1)

    assert_selector "a[data-locale=de] .text-sm.font-semibold", text: "Deutsch"
    assert_text "35% done"
    assert_selector "[role=progressbar][aria-label='Deutsch translated'][aria-valuenow='35']"
    assert_selector "span", text: "12 missing"
    assert_selector "span", text: "↻ 1 outdated"
  end

  test "a language is one tile link with no border; the current one has aria-current" do
    card(total: 1, complete: 0, missing: 1, outdated: 0)
    tile = page.find("a[data-locale=de]")
    assert_equal "/x?language=de", tile[:href]
    assert_equal "Deutsch: show items to translate", tile["aria-label"]
    assert_equal %w[admin-tile flex flex-col gap-2 px-4 py-3.5].sort, tile[:class].split.sort
    assert_nil tile["aria-current"]
    assert_selector "a", count: 1
    assert_no_selector "[class*='border']"
    # The link is named for what it does, and its figures describe it.
    described = tile["aria-describedby"].split.map { |id| page.find("##{id}", visible: :all).text.squish }
    assert_equal [ "0% done", "1 missing" ], described

    card(total: 1, complete: 0, missing: 1, outdated: 0, url: "/x", current: true)
    assert_selector "a.admin-tile[aria-current=true][aria-label='Deutsch: show all languages'][href='/x']"
  end

  test "the bar is ok on a line track, and outdated says ↻ with its count in warn ink, missing its count in meta" do
    card(total: 20, complete: 7, missing: 12, outdated: 3)

    assert_selector "[role=progressbar].h-1.rounded-full.bg-line > .bg-ok"
    assert_no_selector ".bg-sunken"
    assert_selector ".text-warn-ink", text: "↻ 3 outdated"
    assert_selector ".text-warn-ink [aria-hidden=true]", text: "↻"
    assert_selector ".text-meta", text: "12 missing"
    assert_selector ".text-label.text-meta", text: "35% done"

    card(total: 20, complete: 8, missing: 12, outdated: 0)
    assert_no_selector ".text-warn-ink"
    assert_no_text "outdated"
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
