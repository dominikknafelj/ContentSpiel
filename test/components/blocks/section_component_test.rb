require "test_helper"

# `Blocks::SectionComponent`'s `style` (theme choices spec, "Section
# styles"): the stored name when the theme declares it, written as a class.
class Blocks::SectionComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper

  def section_block(settings = {})
    block = root_page.content_blocks.create!(block_type: :section, position: 0, settings: { "layout" => "one", "background" => "none", "width" => "content" }.merge(settings))
    root_page.content_blocks.create!(block_type: :rich_text, section: block, section_column: 1, position: 0, body: rich_doc("Inside"))
    block
  end

  def draw(block) = render_inline(Blocks::SectionComponent.new(block: block, page: root_page))

  def style_of(block) = Blocks::SectionComponent.new(block: block, page: root_page).style

  test "style is the stored name when the theme declares it, and nil when it does not or is blank" do
    styled = with_choices_theme { section_block("style" => "services") }
    blank = section_block
    blank.update_columns(settings: blank.settings.merge("style" => "  ")) # version: none (a test's row) # changes: none (a test's row)

    assert_equal "services", with_choices_theme { style_of(styled) }
    assert_nil style_of(styled), "the default theme declares no style"
    assert_nil with_plain_theme { style_of(styled) }
    assert_nil with_choices_theme { style_of(blank) }
    assert_nil with_choices_theme { style_of(section_block) }
    styled.update_columns(settings: styled.settings.merge("style" => "retired")) # version: none (a test's row) # changes: none (a test's row)
    assert_nil with_choices_theme { style_of(styled.reload) }
  end

  test "the default template writes content-section--style-<name> for a style and nothing new without one" do
    styled = with_choices_theme { section_block("style" => "services") }
    plain = section_block("background" => "tinted")

    with_choices_theme { draw(styled) }
    assert_selector "section.content-section.content-section--none.content-section--content.content-section--style-services"

    draw(plain)
    assert_equal %(<section class="content-section content-section--tinted content-section--content">), rendered_content[/<section[^>]*>/]
    assert_no_match(/style-/, rendered_content)
  end
  test "column_width is the width a column is drawn at in the content column, less the gaps and a band's padding" do
    width = ->(settings, column) { Blocks::SectionComponent.column_width(section_block(settings), column) }
    assert_equal 736, width.({ "layout" => "one" }, 1)
    assert_equal 352, width.({ "layout" => "two" }, 1)
    assert_equal 328, width.({ "layout" => "two", "background" => "tinted" }, 2)
    assert_equal 328, width.({ "layout" => "two", "background" => "strong" }, 1)
    assert_equal 352, width.({ "layout" => "two", "background" => "strong", "width" => "full" }, 1), "a full-width band has no inline padding of its own"
    assert_equal 160, width.({ "layout" => "four" }, 3), "the section measures 46rem, so four sit four across"
    assert_equal 148, width.({ "layout" => "four", "background" => "tinted" }, 4)
    assert_in_delta 704 * 2 / 3.0, width.({ "layout" => "one_two" }, 2)
    assert_in_delta 704 / 3.0, width.({ "layout" => "one_two" }, 1)
  end
end
