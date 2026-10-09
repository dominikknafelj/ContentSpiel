require "test_helper"

class Notes::RemoveTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing", published: false)
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @other = create_page(title: "Other")
    as(users(:two)) do
      Notes::Start.call(@page, body: "On the page, @[#{users(:reader).id}]")
      Notes::Start.call(@block, body: "On the block")
      Notes::Start.call(@other, body: "Elsewhere")
    end
  end

  def left = [ Notes::Thread.count, Notes::Message.count, Notes::Delivery.count, Notes::Follow.count ]

  test "it removes the threads of the record and of what goes with it, and nothing else" do
    result = Notes::Remove.call(@page, with: [ @block ])

    assert result.ok?
    assert_equal [ @other ], Notes::Thread.all.map(&:subject)
    assert_equal [ 1, 1, 0, 1 ], left
  end

  test "one event on the record, ids only; none when there was nothing to remove" do
    ids = Notes::Thread.where(container: @page).order(:id).pluck(:id)

    Notes::Remove.call(@page, with: [ @block ])

    event = Audit::Event.order(:id).last
    assert_equal [ "notes.removed", "Page", @page.id, nil ], [ event.action, event.subject_type, event.subject_id, event.snapshot ]
    assert_equal ids, event.metadata["thread_ids"].sort
    assert_no_difference -> { Audit::Event.count } do
      assert Notes::Remove.call(@page, with: [ @block ]).ok?
    end
  end

  test "it costs the same statements for one thread as for many" do
    one = capture_sql { Notes::Remove.call(@other) }.size
    as(users(:two)) { 6.times { |index| Notes::Start.call(@block, body: "Note #{index}") } }
    many = capture_sql { Notes::Remove.call(@page, with: [ @block ]) }.size

    assert_equal one, many
  end

  test "a block's notes go with the right to edit its page; a reader is refused and nothing is removed" do
    refused = as(users(:reader)) { Notes::Remove.call(@block) }

    assert_predicate refused, :denied?
    assert_equal 3, Notes::Thread.count
    assert as(users(:two)) { Notes::Remove.call(@block) }.ok?
    assert_equal 2, Notes::Thread.count
  end
end
