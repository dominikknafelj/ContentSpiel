require "test_helper"

# The editor half of the derived smoke test (block types spec, "New guards"):
# each registered type's card, drawn from its sample, has a control for every
# field of its schema, and the same card held by someone else
# (`HeldFields`) keeps every name and value it had.
class Admin::EditorScreen::BlockSamplesCardTest < ActiveSupport::TestCase
  include ComponentTestHelper
  include EveryBlockType

  def named(html) = Nokogiri::HTML5.fragment(html).css("[name]").map { |node| [ node["name"], node["value"] || node.text ] }

  def sample_value(block, field) = block.settings[field.name]

  test "a theme-choice field with no choice and no stored name draws no control, and one with a choice draws it" do
    page = create_page(title: "Cards")
    section = page.content_blocks.create!(block_type: "section", position: 0)
    draw = -> { as_owner { render_inline Admin::EditorScreen::SectionCardComponent.new(page: page, section: section, outline: BlockOutline.new(page.content_blocks.reload), locale: "en", editable: true) }.then { rendered_content } }

    assert_nil Nokogiri::HTML5.fragment(draw.call).at_css("[name='block[settings][style]']")
    assert_not_nil Nokogiri::HTML5.fragment(with_choices_theme { draw.call }).at_css("select[name='block[settings][style]']")
  end

  test "every type's card draws a control for each field of its schema, and its held form keeps every name and value" do
    with_every_type do
      assert_includes sampled_types.map(&:name), "gallery/album", "the outside type is in the run"
      page = create_page(title: "Cards")
      sampled_types.each do |definition|
        block = sample_block(page, definition.name)
        as_owner { render_inline Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en", editable: true) }
        html = rendered_content

        definition.fields.reject(&:group?).each do |field|
          # A theme-choice field is drawn only where the theme offers a choice
          # or the block stores a name (`ThemeChoiceField.draws?`): the default
          # theme declares none, so a sample that stores none draws no control.
          next if field.type == :theme_choice && !Admin::Fields::ThemeChoiceField.draws?(field, sample_value(block, field))

          assert Nokogiri::HTML5.fragment(html).at_css("[name*='[#{field.name}]']"), "#{definition.name}'s card has no control for #{field.name}"
        end
        assert_equal named(html), named(Admin::EditorScreen::HeldFields.call(html)), "#{definition.name}'s held form changed a name or a value"
      end
      assert_every_type_built
    end
  end
end
