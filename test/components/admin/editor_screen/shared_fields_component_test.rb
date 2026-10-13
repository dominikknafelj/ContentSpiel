require "test_helper"

class Admin::EditorScreen::SharedFieldsComponentTest < ViewComponent::TestCase
  Field = ContentModel::Definition::Field

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

  test "a select is shown by its label, an empty one by its blank label, and a value that is not on the list as it is stored" do
    field = Field.new(name: "language", type: :select, options: { options: { "ruby" => "Ruby" }, blank: "Plain text" })
    display = ->(value) { Admin::EditorScreen::SharedFieldsComponent.display(field, value) }

    assert_equal "Ruby", display.("ruby")
    assert_equal "Plain text", display.(nil)
    assert_equal "cobol", display.("cobol")
    assert_equal "small", Admin::EditorScreen::SharedFieldsComponent.display(Field.new(name: "size", type: :select, options: { options: %w[small] }), "small")
  end

  test "code is shown in a scrolling pre of at most twelve lines, as text, and no code as a dash" do
    field = Field.new(name: "code", type: :code, options: {})
    shown = Admin::EditorScreen::SharedFieldsComponent.display(field, "  a <b>bold</b>\n\tb")
    assert_nil Admin::EditorScreen::SharedFieldsComponent.display(field, nil)

    render_inline(Admin::EditorScreen::SharedFieldsComponent.new(fields: [ [ "Code", shown ], [ "Filename", nil ] ]))

    assert_selector "dd pre[tabindex='0'].overflow-auto", visible: :all
    assert_includes page.find("dd pre", visible: :all)[:class], "max-h-[12lh]"
    assert_equal "  a <b>bold</b>\n\tb", Nokogiri::HTML5.fragment(rendered_content).at_css("dd pre").text
    assert_no_selector "dd b", visible: :all
    assert_text :all, "—"
  end
end
