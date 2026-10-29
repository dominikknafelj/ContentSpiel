require "test_helper"

class BlockTypes::TableTest < ActiveSupport::TestCase
  def table_block(markdown: nil, caption: nil, locale: :en)
    block = root_page.content_blocks.new(block_type: :table, position: 0)
    block.assign_body(rich_doc(markdown, tables: true), locale: locale) if markdown
    block.caption = caption if caption
    block
  end

  test "the table type declares its body as a table, its caption, its icon and its theme methods" do
    definition = BlockTypes.fetch(:table)

    assert_equal :table, definition.body_content
    assert_equal %w[body caption], definition.uses.map(&:to_s).sort
    assert_equal "table", definition.icon
    assert_equal Blocks::TableComponent, definition.component
    assert_equal %i[block page rows header_row? header_column? column_count caption], definition.theme_methods.map(&:to_sym)
    assert_empty definition.fields
  end

  test "summary reads columns × rows and the first header words, the caption in their place, and Empty table for a blank body" do
    markdown = "| Plan | Price | Storage |\n| --- | --- | --- |\n| A | 1 | 2 |\n| B | 3 | 4 |"

    assert_equal [ [ :text, "Table · 3 × 3 · " ], [ :text, "Plan Price Storage" ] ], BlockTypes::Table.summary(table_block(markdown: markdown), locale: "en")
    assert_equal [ [ :text, "Table · 3 × 3 · " ], [ :text, "Plans" ] ], BlockTypes::Table.summary(table_block(markdown: markdown, caption: "Plans"), locale: "en")
    assert_equal [ [ :hint, :empty ] ], BlockTypes::Table.summary(table_block, locale: "en")
  end
end
