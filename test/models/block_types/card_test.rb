require "test_helper"

class BlockTypes::CardTest < ActiveSupport::TestCase
  test "a card is an icon, a title, a text and a link, none required, the title and text translated" do
    definition = BlockTypes.fetch(:card)

    assert_equal [ %w[icon theme_choice], %w[title string], %w[text text], %w[link link] ],
                 definition.fields.map { |field| [ field.name, field.type.to_s ] }
    assert_equal :icons, definition.fields.first.options[:of]
    assert definition.fields.none?(&:required?)
    assert_equal %w[title text], definition.fields.select(&:translated?).map(&:name)
    assert_equal %w[image alt], definition.uses_columns
    assert_equal Blocks::CardComponent, definition.component
    assert_equal %w[block page title text link icon icon_name image], definition.theme_methods.map(&:to_s)
  end
end
