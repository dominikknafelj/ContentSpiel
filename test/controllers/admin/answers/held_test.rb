require "test_helper"
require_relative "../../../support/answers_test_helper"

class Admin::Answers::HeldTest < ActionView::TestCase
  include AnswersTestHelper

  test "a held save is 409: the held status naming the holder, the lost strip and the form's toast removed" do
    page = create_page(title: "About")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)
    holder = users(:two)
    reserve(block, page, holder, "tab-b")
    hold = Editing::Reservation.holder_of(block)
    prefix = Admin::EditorScreen::BlockCardComponent.error_prefix(block)

    answer = Admin::Answers::Held.new(view: view).answer(subject: block, hold: hold, viewer: users(:one),
      status_id: "#{prefix}-save-status", error_prefix: prefix, live: false)

    assert_equal :conflict, answer.status
    assert_equal [ [ "replace", "#{prefix}-save-status" ], [ "update", Admin::EditorScreen::HoldStripComponent.slot_id(block) ], [ "remove", "toast-#{prefix}" ] ],
      streams_of(answer)
    status, strip = stream_nodes(answer)
    assert_includes status.inner_html, PersonName.of(holder).upcase
    assert_predicate strip.inner_html.strip, :present?
  end
end
