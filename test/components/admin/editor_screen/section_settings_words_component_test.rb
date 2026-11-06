require "test_helper"

class Admin::EditorScreen::SectionSettingsWordsComponentTest < ViewComponent::TestCase
  setup do
    @editor_page = create_page(title: "Section words")
    @section = @editor_page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "three" })
  end

  def render_words
    render_inline Admin::EditorScreen::SectionCardComponent.words(section: @section.reload)
  end

  def words = page.all("#section-#{@section.id}-words button.admin-section-word").map { |word| word.text.delete("▾").strip }

  test "a section's head says its layout, background and width as words, each a button for its settings" do
    render_words

    assert_equal [ "3 columns", "No background", "Content width" ], words
    { "layout" => "3 columns", "background" => "No background", "width" => "Content width" }.each do |field, word|
      assert_selector "#section-#{@section.id}-words button.admin-section-word[type=button][data-action='admin--editor--section#openSettings']" \
        "[data-admin--editor--section-field-param='#{field}'][aria-label='Section settings: #{word}']", text: word
    end
    assert_selector "button.admin-section-word span[aria-hidden=true]", text: "▾", count: 3

    @section.update!(settings: { "layout" => "one", "background" => "strong", "width" => "full" })
    render_words
    assert_equal [ "1 column", "Strong background", "Full width" ], words

    @section.update!(settings: { "layout" => "two", "background" => "tinted" })
    render_words
    assert_equal [ "2 columns", "Tinted background", "Content width" ], words
  end

  test "a style word appears only for a style that is not the default, and an anchor word only when one is set" do
    with_section_grid_theme do
      render_words
      assert_no_selector "[data-admin--editor--section-field-param='style']"

      @section.update!(settings: { "layout" => "three", "style" => "grid_six" })
      render_words
      label = Theme.current.choice(:section_styles, "grid_six").label_for(:en)
      assert_selector "button[data-admin--editor--section-field-param='style']", text: label
      assert_equal [ "3 columns", "No background", "Content width", label ], words

      # A name the theme no longer declares is drawn as the default: no word.
      @section.update_columns(settings: { "layout" => "three", "style" => "dropped" }) # version: none (a stored name the theme dropped)
      render_words
      assert_no_selector "[data-admin--editor--section-field-param='style']"
    end

    # The default theme declares no style, so a stored name has no word.
    @section.update_columns(settings: { "layout" => "three", "style" => "grid_six" }) # version: none (a name the default theme does not declare)
    render_words
    assert_no_selector "[data-admin--editor--section-field-param='style']"
    assert_no_selector "[data-admin--editor--section-field-param='anchor']"

    @section.update!(settings: { "layout" => "three", "anchor" => "about" })
    render_words
    assert_selector "button[data-admin--editor--section-field-param='anchor'][aria-label='Section settings: #about']", text: "#about"
    assert_equal "#about", words.last
  end

  test "every word controls the settings region and says it is closed" do
    @section.update!(settings: { "layout" => "three", "anchor" => "about" })
    render_words

    assert_selector "#section-#{@section.id}-words[data-admin--editor--section-target='words']"
    assert_selector "button.admin-section-word", count: 4
    assert_selector "button.admin-section-word[aria-controls='section-#{@section.id}-settings'][aria-expanded='false']", count: 4

    assert_no_selector "button.admin-section-word[disabled]"
  end
end
