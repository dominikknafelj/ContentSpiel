require "test_helper"

# What a block is called where a note names it (the handoff's decision 8).
class Notes::HeadingTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @text = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @section = @page.content_blocks.create!(block_type: "section", position: 1, settings: { "layout" => "two" })
    @image = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 2, position: 0)
    @list = @page.content_blocks.create!(block_type: "post_list", position: 2)
  end

  def heading(locale: "en") = Notes::Heading.new(@page.reload.content_blocks.to_a, locale: locale)

  def name_of(block, **options) = heading(**options).then { |headings| headings.for(headings.instance_variable_get(:@by_id).fetch(block.id)) }

  def write(block, locale, markdown)
    block.assign_body(rich_doc(markdown), locale: locale)
    block.save!
  end

  test "a text block is named by its type and its first six words, with an ellipsis when the text goes on" do
    write(@text, :en, "Our prices start at forty nine euros a month.\n\nSecond paragraph")

    name = name_of(@text)

    assert_equal [ "Rich text", nil, nil, "Our prices start at forty nine…", nil, 1 ], name.to_h.values_at(:type, :section, :column, :words, :file_name, :position)

    write(@text, :en, "**Short** and sweet")
    assert_equal "Short and sweet", name_of(@text).words
  end

  # A table's plain paragraphs are its cells, row by row
  # (`RichText::Document#plain_paragraphs`), so the first is its first cell.
  test "a note on a Table block is headed by its first cell's text" do
    table = @page.content_blocks.create!(block_type: "table", position: 3)
    table.assign_body(rich_doc("| Plan name | Price |\n| --- | --- |\n| Basic | 5 |", tables: true), locale: :en)
    table.save!

    assert_equal "Plan name", name_of(table).words
  end

  test "the words are the tab's language's, and the default language's when the tab's is blank" do
    with_locales(%w[en de], default: "en") do
      write(@text, :en, "English words here")
      assert_equal "English words here", name_of(@text, locale: "de").words

      write(@text, :de, "Deutsche Wörter hier")
      assert_equal "Deutsche Wörter hier", name_of(@text, locale: "de").words
      assert_equal "English words here", name_of(@text, locale: "en").words
    end
  end

  test "a block in a section carries the section's type and its column" do
    assert_equal [ "Image", "Section", 2 ], name_of(@image).to_h.values_at(:type, :section, :column)
  end

  test "an image block is named by its image's file name once the images are read, and never by its caption" do
    @image.update!(media_asset: create_media_asset(filename: "tiny.png"), caption: "A caption")
    headings = heading
    block = headings.instance_variable_get(:@by_id).fetch(@image.id)

    assert_equal [ nil, nil, 3 ], headings.for(block).to_h.values_at(:words, :file_name, :position)

    headings.preload_images([ block ])
    assert_equal [ nil, "tiny.png" ], headings.for(block).to_h.values_at(:words, :file_name)
  end

  test "a block with no text and no image has only its place on the page, in display order, a section counted" do
    assert_equal [ [ nil, nil, 1 ], [ nil, nil, 2 ], [ nil, nil, 3 ], [ nil, nil, 4 ] ],
      [ @text, @section, @image, @list ].map { |block| name_of(block).to_h.values_at(:words, :file_name, :position) }
  end

  test "naming blocks reads nothing, and the images of any number of image blocks are read in one pass" do
    write(@text, :en, "Some words")
    more = 3.times.map { |index| @page.content_blocks.create!(block_type: "image", position: 3 + index, media_asset: create_media_asset) }
    @image.update!(media_asset: create_media_asset)
    blocks = @page.reload.content_blocks.to_a

    one = capture_sql { Notes::Heading.new(blocks, locale: "en").preload_images(blocks.select { |block| block.id == @image.id }) }.size
    blocks = @page.reload.content_blocks.to_a
    headings = Notes::Heading.new(blocks, locale: "en")
    four = capture_sql { headings.preload_images(blocks) }.size

    assert_equal one, four
    assert_operator one, :<=, 3
    assert_empty capture_sql { blocks.each { |block| headings.for(block) } }
    assert_empty capture_sql { headings.preload_images(blocks) }
    assert_equal [ "tiny.png" ] * 4, [ @image, *more ].map { |image| headings.for(blocks.find { |block| block.id == image.id }).file_name }
  end
end
