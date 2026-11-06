require "test_helper"
require_relative "../../../support/answers_test_helper"

class Admin::Answers::BlockSavedTest < ActionView::TestCase
  include AnswersTestHelper

  setup { @page = create_page(title: "About") }

  def saved(page = @page) = Admin::Answers::BlockSaved.new(answers_context(page))

  test "a block added to the page's list is one append to the list, and the publishing chip when the page is live" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)

    answer = saved.created(block, section: nil)

    assert_equal :created, answer.status
    assert_equal [ [ "append", "content-blocks-list" ], [ "replace", chip ] ], streams_of(answer)
    assert_includes stream_nodes(answer).first.inner_html, %(id="#{dom_id_of(block)}")

    draft = create_page(title: "Draft", published: false)
    draft_block = draft.content_blocks.create!(block_type: "rich_text", position: 0)
    assert_equal [ [ "append", "content-blocks-list" ] ], streams_of(saved(draft).created(draft_block, section: nil))
  end

  test "a block added to a column is its panel, its tile and the section's count, and no card" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    block = @page.content_blocks.create!(block_type: "image", section: section, section_column: 2, position: 0)

    answer = saved.created(block, section: section)

    assert_equal :created, answer.status
    assert_equal [ [ "append", Admin::EditorScreen::SectionCardComponent.panels_id(section) ],
      [ "append", Admin::EditorScreen::SectionLanesComponent.lane_id(section, 2) ],
      *section_counts(section), [ "replace", chip ] ], streams_of(answer)
    panel = stream_nodes(answer).first.inner_html
    assert_includes panel, %(id="#{Admin::EditorScreen::BlockCardComponent.panel_id(block)}")
    assert_includes panel, "data-open"
  end

  test "a reorder of the list that changed the order offers Undo, and one that changed nothing offers nothing" do
    first = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    second = @page.content_blocks.create!(block_type: "rich_text", position: 1)
    before = [ first.id, second.id ]

    unchanged = saved.reordered(origins: {}, structural: false, before: before, undo: false, undo_url: "/undo-it")
    assert_equal :ok, unchanged.status
    assert_equal [ [ "replace", "content-blocks-status" ], [ "replace", chip ] ], streams_of(unchanged)

    first.update_columns(position: 1)
    second.update_columns(position: 0)
    changed = saved.reordered(origins: {}, structural: false, before: before, undo: false, undo_url: "/undo-it")
    assert_equal :ok, changed.status
    assert_equal [ [ "replace", "content-blocks-status" ], [ "append", "toasts" ], [ "replace", chip ] ], streams_of(changed)
    toast = stream_nodes(changed)[1].inner_html
    assert_includes toast, "Block order changed."
    assert_includes toast, "/undo-it"
  end

  test "an undone reorder redraws the list with 'Order restored.'" do
    first = @page.content_blocks.create!(block_type: "rich_text", position: 0)

    answer = saved.reordered(origins: {}, structural: false, before: [ first.id ], undo: true, undo_url: "/undo-it")

    assert_equal :ok, answer.status
    assert_equal [ [ "replace", "content-blocks-status" ], [ "update", "content-blocks-list" ], [ "append", "toasts" ], [ "replace", chip ] ], streams_of(answer)
    nodes = stream_nodes(answer)
    assert_includes nodes[1].inner_html, %(id="#{dom_id_of(first)}")
    assert_includes nodes[2].inner_html, "Order restored."
    assert_not_includes nodes[2].inner_html, "/undo-it"
  end

  test "a structural move answers each moved block in its new shape" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    moved_in = @page.content_blocks.create!(block_type: "image", section: section, section_column: 1, position: 0)
    moved_out = @page.content_blocks.create!(block_type: "rich_text", position: 1)
    origins = { moved_in.id.to_s => { "section_id" => "", "column" => "" }, moved_out.id.to_s => { "section_id" => section.id.to_s, "column" => "2" } }

    answer = saved.reordered(origins: origins, structural: true, before: [], undo: false, undo_url: "/undo-it")

    assert_equal :ok, answer.status
    card = Admin::EditorScreen::BlockCardComponent
    assert_equal [ [ "replace", "content-blocks-status" ],
      [ "remove", card.panel_id(moved_in) ], [ "append", Admin::EditorScreen::SectionCardComponent.panels_id(section) ], [ "replace", dom_id_of(moved_in) ],
      [ "remove", card.panel_id(moved_out) ], [ "replace", dom_id_of(moved_out) ],
      *section_counts(section), [ "replace", chip ] ], streams_of(answer)
    assert_includes stream_nodes(answer)[3].inner_html, "data-admin--editor--section-target"
  end

  test "a duplicate in a column is drawn after its source's tile" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    source = @page.content_blocks.create!(block_type: "image", section: section, section_column: 1, position: 0)
    copy = @page.content_blocks.create!(block_type: "image", section: section, section_column: 1, position: 1)

    answer = saved.duplicated(copy, source: source)

    assert_equal :created, answer.status
    assert_equal [ [ "append", Admin::EditorScreen::SectionCardComponent.panels_id(section) ], [ "after", dom_id_of(source) ],
      *section_counts(section), [ "replace", chip ] ], streams_of(answer)
    assert_not_includes stream_nodes(answer).first.inner_html, "data-open"
  end

  test "a saved block in a column redraws its tile's line after the autosave's own streams, and one at the top level does not" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    inside = @page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)
    outside = @page.content_blocks.create!(block_type: "rich_text", position: 1)
    autosave = [ view.turbo_stream.replace("block-status", html: "saved") ]

    answer = saved.updated(inside, autosave: autosave, layout_before: nil, columns_before: inside.column_count)
    assert_equal :ok, answer.status
    assert_equal [ [ "replace", "block-status" ], [ "replace", Admin::EditorScreen::TileSummaryComponent.dom_id(inside) ], [ "replace", chip ] ], streams_of(answer)

    top = saved.updated(outside, autosave: autosave, layout_before: nil, columns_before: outside.column_count)
    assert_equal [ [ "replace", "block-status" ], [ "replace", chip ] ], streams_of(top)
  end

  # The region is a form that may hold text a person is typing: a save
  # replaces the head's words, which say what was saved, and never the region.
  test "a saved section setting replaces the words, never the region" do
    section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "two" })
    card = Admin::EditorScreen::SectionCardComponent
    section.update!(settings: { "layout" => "two", "background" => "tinted" })

    background = saved.updated(section, autosave: [], layout_before: "two", columns_before: 2)
    assert_equal [ [ "replace", card.words_id(section) ], [ "replace", chip ] ], streams_of(background)
    assert_includes stream_nodes(background).first.inner_html, "Tinted background"

    section.update!(settings: { "layout" => "three", "background" => "tinted" })
    layout = saved.updated(section, autosave: [], layout_before: "two", columns_before: 2)
    targets = streams_of(layout).map(&:last)
    assert_includes targets, card.words_id(section)
    assert_includes targets, Admin::EditorScreen::SectionLayoutMenuComponent.dom_id(section)
    assert_includes stream_nodes(layout).find { |node| node["target"] == card.words_id(section) }.inner_html, "3 columns"
    [ background, layout ].each do |answer|
      assert_not_includes streams_of(answer).map(&:last), card.settings_id(section)
      assert_not_includes answer.streams.join, %(id="#{card.settings_id(section)}")
      assert_not_includes answer.streams.join, %(id="section-#{section.id}-form")
    end
  end

  test "a removed block takes its card away and tells the page's note counts" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    block.destroy!

    answer = saved.removed(block, kept_ids: [], section: nil)

    assert_equal :ok, answer.status
    assert_equal [ [ "remove", dom_id_of(block) ], [ "replace", "notes-counts" ], [ "replace", chip ] ], streams_of(answer)
  end
end
