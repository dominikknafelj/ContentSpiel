require "test_helper"

class Admin::Columns::PlainColumnComponentTest < ViewComponent::TestCase
  test "renders a text input by default" do
    render_inline Admin::Columns::PlainColumnComponent.new(name: "caption", value: "A caption")

    assert_selector "input[type=text][name=caption][value='A caption']"
  end

  test "renders a textarea when multiline" do
    render_inline Admin::Columns::PlainColumnComponent.new(name: "meta_description", value: "A description", multiline: true)

    assert_selector "textarea[name=meta_description]", text: "A description"
  end

  test "shows the read-only original and errors" do
    render_inline Admin::Columns::PlainColumnComponent.new(name: "caption", value: nil, original: "Bildunterschrift", errors: [ "is too long" ])

    assert_selector "[data-original-for='caption']", text: "Bildunterschrift"
    assert_text "is too long"
  end
end

class Admin::Columns::PlainColumnComponentTranslationTest < ViewComponent::TestCase
  CONFIRM = { record_type: "Page", record_id: 1, field: "subtitle", locale: "de" }.freeze

  test "an outdated translation shows the note and button inside the original box" do
    render_inline Admin::Columns::PlainColumnComponent.new(name: "subtitle", value: "Alt", original: "New",
      translation_state: :outdated, translation_confirm: CONFIRM)

    assert_selector "[data-original-for='subtitle'] #translation-note-page-1-subtitle button", text: "Mark as up to date"
  end

  test "current, unknown or no state shows nothing" do
    [ :current, :unknown, nil ].each do |state|
      render_inline Admin::Columns::PlainColumnComponent.new(name: "subtitle", value: "Alt", original: "New",
        translation_state: state, translation_confirm: CONFIRM)

      refute_text "Original changed since this was translated"
    end
  end
end
