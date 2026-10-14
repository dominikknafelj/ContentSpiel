require "test_helper"

# The editor half of the derived smoke test (block types spec, "New guards"):
# each registered type's card, drawn from its sample, has a control for every
# field of its schema, and the same card held by someone else
# (`HeldFields`) keeps every name and value it had.
class Admin::EditorScreen::BlockSamplesCardTest < ActiveSupport::TestCase
  include ComponentTestHelper
  include TestTypes

  def named(html) = Nokogiri::HTML5.fragment(html).css("[name]").map { |node| [ node["name"], node["value"] || node.text ] }

  test "every type's card draws a control for each field of its schema, and its held form keeps every name and value" do
    with_test_types do
      page = create_page(title: "Cards")
      sampled_types.each do |definition|
        block = sample_block(page, definition.name)
        as_owner { render_inline Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en", editable: true) }
        html = rendered_content

        definition.fields.reject(&:group?).each do |field|
          assert Nokogiri::HTML5.fragment(html).at_css("[name*='[#{field.name}]']"), "#{definition.name}'s card has no control for #{field.name}"
        end
        assert_equal named(html), named(Admin::EditorScreen::HeldFields.call(html)), "#{definition.name}'s held form changed a name or a value"
      end
      assert_every_type_built
    end
  end
end
