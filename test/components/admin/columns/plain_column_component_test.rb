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

  test "a soft counter counts code points and turns to a warning past its limit" do
    render_inline Admin::Columns::PlainColumnComponent.new(name: "meta_title", value: "ab😀", counter: 60)
    assert_selector "[data-admin--char-count-target=output].text-meta", text: "3 / 60"

    render_inline Admin::Columns::PlainColumnComponent.new(name: "meta_title", value: "x" * 70, counter: 60)
    assert_selector "[data-admin--char-count-target=output].text-warn-ink", text: "70 / 60 · long"
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

    assert_selector "[data-original-for='subtitle'] button[form='translation-confirm-form']", text: "Still correct — mark up to date"
  end

  test "current, unknown or no state shows nothing" do
    [ :current, :unknown, nil ].each do |state|
      render_inline Admin::Columns::PlainColumnComponent.new(name: "subtitle", value: "Alt", original: "New",
        translation_state: state, translation_confirm: CONFIRM)

      refute_text "changed since this was translated"
    end
  end
end
