require "test_helper"

# `Admin::Ui::LanguageProgressComponent`: one language's bar and its counts,
# the one drawing the Dashboard and the Translations tiles share.
class Admin::Ui::LanguageProgressComponentTest < ViewComponent::TestCase
  def progress(language: "Deutsch", counts_id: nil, **figures)
    render_inline(Admin::Ui::LanguageProgressComponent.new(language:, counts_id:, **figures))
  end

  test "the bar is ok on a sunken track, named for the language, at its percentage in 5% steps" do
    progress(complete: 7, total: 20, outdated: 1, missing: 12)

    assert_selector "[role=progressbar].h-1.rounded-full.bg-sunken[aria-label='Deutsch translated'][aria-valuemin='0'][aria-valuemax='100'][aria-valuenow='35'] > .bg-ok.w-\\[35\\%\\]"
    assert_no_selector ".bg-line"

    progress(complete: 1, total: 3, outdated: 0, missing: 2)
    assert_selector "[role=progressbar][aria-valuenow='33'] > .w-\\[35\\%\\]"
  end

  test "outdated comes first, with its ↻ in warn ink, then missing in meta" do
    progress(complete: 7, total: 20, outdated: 3, missing: 12)

    counts = page.find("[role=progressbar] + span")
    assert_equal "↻ 3 outdated · 12 missing", counts.text.squish
    assert_selector ".text-warn-ink", exact_text: "↻ 3 outdated"
    assert_selector ".text-warn-ink [aria-hidden=true]", exact_text: "↻"
    assert_selector ".text-meta[aria-hidden=true]", exact_text: "·"
    assert_selector ".text-meta", exact_text: "12 missing"
  end

  test "a zero count is not drawn, and with both zero it reads All translated" do
    progress(complete: 8, total: 20, outdated: 0, missing: 12)
    assert_no_selector ".text-warn-ink"
    assert_no_text "outdated"
    assert_no_text "·"

    progress(complete: 17, total: 20, outdated: 1, missing: 0)
    assert_selector ".text-warn-ink", exact_text: "↻ 1 outdated"
    assert_no_text "missing"

    progress(complete: 4, total: 4, outdated: 0, missing: 0)
    assert_selector ".text-meta", exact_text: "All translated"
    assert_selector "[role=progressbar][aria-valuenow='100'] > .w-full"
  end

  test "nothing to translate reads 0%, and percent is the shared figure" do
    progress(complete: 0, total: 0, outdated: 0, missing: 0)
    assert_selector "[role=progressbar][aria-valuenow='0'] > .w-0"
    assert_equal 35, Admin::Ui::LanguageProgressComponent.percent(complete: 7, total: 20)
    assert_equal 0, Admin::Ui::LanguageProgressComponent.percent(complete: 0, total: 0)
  end

  test "the counts take the caller's id; everything is a span that takes no focus and is never red" do
    html = progress(complete: 1, total: 3, outdated: 1, missing: 1, counts_id: "de-counts").to_html

    assert_selector "span#de-counts", text: "1 missing"
    assert_equal [ "span" ], Nokogiri::HTML::DocumentFragment.parse(html).css("*").map(&:name).uniq, "it may stand inside a link"
    assert_no_selector "[tabindex], a, button"
    assert_no_match(/danger/, html)
  end
end
