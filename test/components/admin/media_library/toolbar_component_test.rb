require "test_helper"

class Admin::MediaLibrary::ToolbarComponentTest < ViewComponent::TestCase
  include ContentHelper

  COUNTS = { all: 12, unused: 5, missing_alt: 3, untranslated: 2, mine: 4 }.freeze

  test "five segments with their counts, the chosen one checked" do
    with_locales(%w[en de], default: "en")

    render_inline Admin::MediaLibrary::ToolbarComponent.new(counts: COUNTS, filter: "missing_alt", q: nil)

    assert_selector "label", text: /All\s+12/
    assert_selector "label", text: /Unused\s+5/
    assert_selector "label", text: /Missing alt\s+3/
    assert_selector "label", text: /Untranslated\s+2/
    assert_selector "label", text: /Mine\s+4/
    assert_selector "input[type=radio][name=filter]", count: 5, visible: :all
    assert_selector "input#media-filter-missing_alt[checked]", visible: :all
    assert_selector "#media-count-missing_alt", text: "3"
  end

  test "All is a blank filter value, and checked for the normalised all" do
    render_inline Admin::MediaLibrary::ToolbarComponent.new(counts: COUNTS, filter: "all", q: nil)

    assert_selector "input#media-filter-all[value=''][checked]", visible: :all
  end

  test "Untranslated is not offered with one language" do
    with_locales(%w[en], default: "en")

    render_inline Admin::MediaLibrary::ToolbarComponent.new(counts: COUNTS, filter: "all", q: nil)

    assert_no_selector "#media-filter-untranslated", visible: :all
    assert_selector "input[type=radio][name=filter]", count: 4, visible: :all
  end

  test "the form auto-submits into the content frame, keeping the chosen image and the language" do
    render_inline Admin::MediaLibrary::ToolbarComponent.new(counts: COUNTS, filter: "all", q: "sun", selected_id: 7, url_options: { locale: "de" })

    assert_selector "form[data-controller='admin--auto-submit'][data-turbo-frame='content']"
    assert_selector "input[type=hidden][name=selected][value='7']", visible: :all
    assert_selector "input[type=hidden][name=locale][value='de']", visible: :all
    assert_selector "input[type=search][name=q][value='sun']"
    assert_selector "a", text: "Clear"
  end

  test "no Clear link while nothing is set" do
    render_inline Admin::MediaLibrary::ToolbarComponent.new(counts: COUNTS, filter: "all", q: nil)

    assert_no_selector "a", text: "Clear"
  end

  # Round 3 Task 9: the same toolbar inside the picker's own frame.
  test "the picker's toolbar targets its frame, keeps picker=1, has its own ids and no Untranslated" do
    with_locales(%w[en de], default: "en")

    render_inline Admin::MediaLibrary::ToolbarComponent.new(counts: COUNTS, filter: "all", q: "dune", picker: true)

    assert_selector "form[data-turbo-frame='media-picker-grid'][data-controller='admin--auto-submit']"
    assert_no_selector "form[data-turbo-action]"
    assert_selector "input[type=hidden][name=picker][value='1']", visible: :all
    assert_selector "input#media-picker-q[type=search][value=dune]"
    assert_selector "label[for=media-picker-q]", text: "Search images", visible: :all
    assert_selector "input[type=radio][name=filter]", count: 4, visible: :all
    assert_no_selector "input[value=untranslated]", visible: :all
    assert_selector "input#media-picker-filter-unused", visible: :all
    assert_selector "#media-picker-count-unused", text: "5"
    assert_no_selector "#media-count-unused"
  end
end
