require "test_helper"

class Admin::EditorScreen::SharedFieldsComponentTest < ViewComponent::TestCase
  test "is closed by default, counts its fields and lists label and value read-only" do
    render_inline(Admin::EditorScreen::SharedFieldsComponent.new(fields: [ [ "Venue", "Main Hall" ], [ "Limit", "5" ] ]))

    assert_selector "details:not([open]) > summary", text: "Shared fields (2)"
    assert_text "Venue"
    assert_text "Main Hall"
    assert_text "Limit"
    assert_text "Shared by all languages. Edit them on the #{Locales.name(Locales.default, native: true)} tab."
    assert_no_selector "input, textarea, select"
  end

  test "renders nothing without fields" do
    render_inline(Admin::EditorScreen::SharedFieldsComponent.new(fields: []))

    assert_no_selector "details"
  end

  test "a blank value reads as a dash" do
    render_inline(Admin::EditorScreen::SharedFieldsComponent.new(fields: [ [ "Venue", "" ] ]))

    assert_text "—"
  end
end
