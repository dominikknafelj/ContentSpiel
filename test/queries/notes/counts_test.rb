require "test_helper"

class Notes::CountsTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    as(users(:two)) do
      Notes::Start.call(@page, body: "One")
      2.times { Notes::Start.call(@block, body: "Two") }
      Notes::Resolve.call(Notes::Start.call(@block, body: "Done").record)
    end
  end

  test "open threads by subject, with the total, in one query" do
    counts = nil
    statements = capture_sql { counts = Notes::Counts.for_container(@page) }

    assert_equal({ "total" => 3, "subjects" => { "Page-#{@page.id}" => 1, "ContentBlock-#{@block.id}" => 2 }, "unread" => [] }, counts)
    assert_equal 1, statements.size
  end

  test "with a user, the keys whose open threads hold something unread for them, in one more query" do
    as(users(:two)) { Notes::Start.call(@block, body: "For @[#{users(:reader).id}]") }
    counts = nil
    statements = capture_sql { counts = Notes::Counts.for_container(@page, user: users(:reader)) }

    assert_equal [ "ContentBlock-#{@block.id}" ], counts["unread"]
    assert_equal 2, statements.size
    assert_equal [], Notes::Counts.for_container(@page, user: users(:two))["unread"]
    assert_equal Set[@page.id], Notes::Counts.unread_among("Page", [ @page.id, 0 ], users(:reader))
    assert_empty capture_sql { assert_empty Notes::Counts.unread_among("Page", [ @page.id ], nil) }
  end

  test "the unread keys come in one order, whatever order the rows are found in" do
    other = @page.content_blocks.create!(block_type: "rich_text", position: 1)
    as(users(:two)) { [ other, @page, @block ].each { |subject| Notes::Start.call(subject, body: "For @[#{users(:reader).id}]") } }

    unread = Notes::Counts.for_container(@page, user: users(:reader))["unread"]

    assert_equal [ "ContentBlock-#{@block.id}", "ContentBlock-#{other.id}", "Page-#{@page.id}" ], unread
  end

  test "a delivery knows whether a thread holds something unread for a user, in one query" do
    thread = as(users(:two)) { Notes::Start.call(@block, body: "For @[#{users(:reader).id}]") }.record

    assert_equal 1, capture_sql { assert Notes::Delivery.unread_on?(thread, users(:reader)) }.size
    assert_not Notes::Delivery.unread_on?(thread, users(:two))
    assert_empty capture_sql { assert_not Notes::Delivery.unread_on?(thread, nil) }
  end

  test "open threads per container, for a list" do
    other = create_page(title: "Quiet")

    assert_equal({ @page.id => 3 }, Notes::Counts.by_container("Page", [ @page.id, other.id ]))
    assert_empty capture_sql { assert_equal({}, Notes::Counts.by_container("Page", [])) }
  end
end
