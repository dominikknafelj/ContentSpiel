require "test_helper"

# The "Original changed" note beside a translated field's original
# (translation helpers spec §4): the text always, the "Mark as up to date"
# button only for a viewer who may edit the record.
class Admin::TranslationScreen::OutdatedNoteComponentTest < ViewComponent::TestCase
  CONFIRM = { record_type: "Media::Asset", record_id: 7, field: "alt", locale: "de" }.freeze

  test "the note and a button submitting the layout's confirm form" do
    render_inline Admin::TranslationScreen::OutdatedNoteComponent.new(confirm: CONFIRM)

    assert_selector "#translation-note-media-asset-7-alt[role='status']", text: "Original changed since this was translated"
    button = page.find("#translation-note-media-asset-7-alt button[type='submit'][form='translation-confirm-form']", text: "Mark as up to date")
    uri = URI(button["formaction"])
    assert_equal "/cs-studio/translations/confirm", uri.path
    assert_equal({ "record_type" => "Media::Asset", "record_id" => "7", "field" => "alt", "locale" => "de" }, Rack::Utils.parse_query(uri.query))
  end

  test "without confirm params, the note alone" do
    render_inline Admin::TranslationScreen::OutdatedNoteComponent.new

    assert_text "Original changed since this was translated"
    refute_selector "button"
  end

  test "dom_id is the same for the component and the controller's stream" do
    assert_equal "translation-note-content-block-3-text", Admin::TranslationScreen::OutdatedNoteComponent.dom_id("ContentBlock", 3, "text")
  end
end
