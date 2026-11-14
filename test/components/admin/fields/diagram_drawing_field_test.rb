require "test_helper"

# `Admin::Fields::DiagramDrawingField`: the drawing a Diagram block stores,
# a hidden input the preview script writes and nobody types in.
class Admin::Fields::DiagramDrawingFieldTest < ViewComponent::TestCase
  Field = ContentModel::Definition::Field
  STORED = { "svg" => '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><path d="M0 0"/></svg>', "from" => "a" * 64 }.freeze

  def field = Field.new(name: "drawing", type: :diagram_drawing, options: { translated: true })

  def render_field(value, original: nil)
    render_inline Admin::Fields::DiagramDrawingField.new(field:, form_name: "block[settings]", value: value, original: original, locale: "en", id_prefix: "block-7")
  end

  def input = page.find("input", visible: :all)

  test "DiagramDrawingField is a hidden input with no label whose value is the stored JSON" do
    render_field(STORED)

    assert_selector "input[type=hidden]#block-7-drawing[name='block[settings][drawing]']", visible: :all
    assert_equal STORED, JSON.parse(input[:value])
    assert_no_selector "label, textarea, [data-controller], [data-action]", visible: :all
    assert Admin::Fields::DiagramDrawingField.own_label?(field)
    assert_not Admin::Fields::DiagramDrawingField.reference?(field)
    assert_nil Admin::Fields::DiagramDrawingField.display(field, STORED)
  end

  test "with no drawing the value is empty, and a refused drawing read back is no drawing" do
    render_field(nil)
    assert_equal "", input[:value].to_s

    render_field({ "refused" => "element" })
    assert_equal "", input[:value].to_s
  end

  # A translation with no drawing of its own beside the original's: nothing
  # is sent until the script writes this language's drawing, and the script
  # names the field then (`admin--diagram--preview`'s `drawing-name` value).
  test "a translation tab with no drawing of its own draws the input with no name" do
    render_field(nil, original: STORED)

    assert_selector "input[type=hidden]#block-7-drawing:not([name])", visible: :all
    assert_equal "", input[:value].to_s

    render_field(STORED, original: STORED)
    assert_selector "input[type=hidden][name='block[settings][drawing]']", visible: :all
  end
end
