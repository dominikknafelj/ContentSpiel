require "test_helper"
require_relative "../../../support/answers_test_helper"

class Admin::Answers::BlockRefusedTest < ActionView::TestCase
  include AnswersTestHelper

  setup { @page = create_page(title: "About") }

  def refused = Admin::Answers::BlockRefused.new(answers_context(@page))

  def failure(record = nil, denied: false) = ApplicationService::Result.new(record: record, errors: [ "Something is off" ], denied: denied)

  test "a refused add into a column says why and redraws the section's lanes, unless it was denied" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    inside = @page.content_blocks.create!(block_type: "image", section: section, section_column: 1, position: 0)

    answer = refused.created(failure, section: section)

    assert_equal :unprocessable_entity, answer.status
    assert_equal [ [ "replace", "content-blocks-alert" ], [ "replace", Admin::EditorScreen::SectionCardComponent.lanes_id(section) ],
      [ "update", Admin::EditorScreen::BlockCardComponent.panel_title_id(inside) ], *section_counts(section) ], streams_of(answer)
    assert_includes stream_nodes(answer).first.inner_html, "Something is off"

    denied = refused.created(failure(denied: true), section: section)
    assert_equal :forbidden, denied.status
    assert_equal [ [ "replace", "content-blocks-alert" ] ], streams_of(denied)

    assert_equal [ [ "replace", "content-blocks-alert" ] ], streams_of(refused.created(failure, section: nil))
    unknown = refused.unknown_section
    assert_equal :unprocessable_entity, unknown.status
    assert_includes stream_nodes(unknown).sole.inner_html, ContentBlocks::Reorder::NO_COLUMN
  end

  test "a refused structural move redraws the whole list, a refused list order does not" do
    @page.content_blocks.create!(block_type: "rich_text", position: 0)

    structural = refused.reordered(failure, structural: true)
    assert_equal :unprocessable_entity, structural.status
    assert_equal [ [ "replace", "content-blocks-status" ], [ "replace", "content-blocks-alert" ], [ "update", "content-blocks-list" ] ], streams_of(structural)

    assert_equal [ [ "replace", "content-blocks-status" ], [ "replace", "content-blocks-alert" ] ], streams_of(refused.reordered(failure, structural: false))

    denied = refused.reordered(failure(denied: true), structural: true)
    assert_equal :forbidden, denied.status
    assert_equal [ [ "replace", "content-blocks-status" ], [ "replace", "content-blocks-alert" ] ], streams_of(denied)
  end

  test "a denial is 403 and anything else 422" do
    assert_equal :forbidden, refused.status_for(failure(denied: true))
    assert_equal :unprocessable_entity, refused.status_for(failure)

    assert_equal :forbidden, refused.refused(failure(denied: true)).status
    assert_equal :unprocessable_entity, refused.refused(failure).status
    assert_equal [ [ "replace", "content-blocks-alert" ] ], streams_of(refused.refused(failure))
  end

  test "a refused save of a block in a column marks its tile invalid, and a denied one draws its tile as it is" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    inside = @page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)
    autosave = [ view.turbo_stream.replace("block-status", html: "not saved") ]
    summary = Admin::EditorScreen::TileSummaryComponent.dom_id(inside)

    invalid = refused.updated(inside, result: failure(inside), autosave: autosave)
    assert_equal :unprocessable_entity, invalid.status
    assert_equal [ [ "replace", "block-status" ], [ "replace", summary ] ], streams_of(invalid)

    denied = refused.updated(inside, result: failure(inside, denied: true), autosave: autosave,
      refused_media: view.turbo_stream.replace("block-image", html: "stored"))
    assert_equal :forbidden, denied.status
    assert_equal [ [ "replace", "block-status" ], [ "replace", "block-image" ], [ "replace", summary ] ], streams_of(denied)
    assert_not_equal stream_nodes(invalid).last.inner_html, stream_nodes(denied).last.inner_html
  end
end
