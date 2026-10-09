require "test_helper"

# A request can carry a thread, a message or a block that was loaded a moment
# before the record it is on was deleted for good (`Trash::Purge`, which takes
# the threads with it through `Notes::Remove`). Its container is then nil.
# Every notes service answers that as the ordinary "gone" failure the drawer
# shows, never an exception out of the permission lookup, and writes nothing.
class Notes::StaleThreadTest < ActiveSupport::TestCase
  GONE = "This note is gone: it was deleted, or what it was on was.".freeze

  setup do
    @page = create_page(title: "Pricing", published: false)
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    thread = as(users(:two)) { Notes::Start.call(@page, body: "Is this right?") }.record
    # Loaded before the purge, their associations not yet read: what a
    # controller holds when the purge commits between its lookup and its call.
    @thread = Notes::Thread.find(thread.id)
    @note = Notes::Message.find(thread.first_message.id)
    @block = ContentBlock.find(block.id)
    assert Trash::Move.call(@page).ok?
    assert Trash::Purge.call(@page.reload).ok?
    assert_equal [ 0, 0 ], [ Notes::Thread.count, ContentBlock.where(id: block.id).count ]
  end

  def assert_gone(sentence = GONE, &call)
    result = nil
    assert_no_difference [ -> { Audit::Event.count }, -> { Notes::Thread.count }, -> { Notes::Message.count }, -> { Notes::Follow.count } ] do
      result = as(users(:two), &call)
    end
    assert_not result.ok?
    assert_not result.denied?
    assert_equal [ sentence ], result.errors
  end

  test "a thread whose record was purged is gone to every service that takes a thread" do
    assert_nil @thread.container

    assert_gone { Notes::Reply.call(@thread, body: "An answer") }
    assert_gone { Notes::Resolve.call(@thread) }
    assert_gone { Notes::Reopen.call(@thread) }
    assert_gone { Notes::Pin.call(@thread) }
    assert_gone { Notes::Unpin.call(@thread) }
    assert_gone { Notes::SetFollowing.call(@thread, following: true) }
    assert_gone { Notes::MarkRead.call(thread: @thread) }
  end

  test "a message whose thread was removed is gone to an edit and to a delete" do
    assert_nil @note.thread

    assert_gone { Notes::EditMessage.call(@note, body: "Reworded") }
    assert_gone { Notes::DeleteMessage.call(@note) }
  end

  test "a block whose page was purged takes no note, and says the block was deleted" do
    assert_nil @block.owner

    assert_gone("This block was deleted.") { Notes::Start.call(@block, body: "A question") }
  end

  test "the purged page itself takes no note and marks nothing read" do
    assert_gone("This page is in the trash or was deleted.") { Notes::Start.call(@page, body: "A question") }
    assert_gone { Notes::MarkRead.call(container: @page) }
  end
end
