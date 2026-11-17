require "test_helper"

# `Admin::Fields::MediaListField`: a Gallery block's images, a hidden input
# holding the ids as JSON, which the rows' script (`admin--editor--gallery`)
# writes and nobody types in.
class Admin::Fields::MediaListFieldTest < ViewComponent::TestCase
  Field = ContentModel::Definition::Field

  def field = Field.new(name: "images", type: :media_list, options: { max: 60 })

  def render_field(value)
    render_inline Admin::Fields::MediaListField.new(field:, form_name: "block[settings]", value: value, locale: "en", id_prefix: "block-7")
  end

  def input = page.find("input", visible: :all)

  test "the list is a hidden input with the ids as JSON, named for the field and with the id the rows are handed" do
    render_field([ 3, 1, 2 ])

    assert_selector "input[type=hidden]#block-7-images[name='block[settings][images]']", visible: :all
    assert_equal [ 3, 1, 2 ], JSON.parse(input[:value])
    assert_no_selector "label, [data-controller], [data-action]", visible: :all
  end

  test "an empty list is an empty value, which the cast reads as no list" do
    render_field(nil)

    assert_equal "", input[:value].to_s
  end

  test "it draws no label, no original and no room, and reads as a count where it cannot be edited" do
    assert Admin::Fields::MediaListField.own_label?(field)
    assert_not Admin::Fields::MediaListField.reference?(field)
    assert Admin::Fields::MediaListField.hidden?(field)
    assert_equal "12 images", Admin::Fields::MediaListField.display(field, (1..12).to_a)
    assert_equal "1 image", Admin::Fields::MediaListField.display(field, [ 4 ])
    assert_nil Admin::Fields::MediaListField.display(field, [])
  end
end
