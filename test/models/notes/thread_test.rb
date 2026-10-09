require "test_helper"

class Notes::ThreadTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
  end

  def thread_on(subject, **attributes)
    Notes::Thread.create!({ subject: subject, created_by: users(:one), last_message_at: Time.current }.merge(attributes))
  end

  test "a thread on a block is listed by the block's page; any other subject is its own container" do
    post = create_post(title: "Hello")
    asset = create_media_asset

    assert_equal @page, thread_on(@block).container
    assert_equal @page, thread_on(@page).container
    assert_equal post, thread_on(post).container
    assert_equal asset, thread_on(asset).container
    assert_equal "Media::Asset", thread_on(asset).container_type
  end

  test "the container is derived, never taken from the caller" do
    other = create_page(title: "Elsewhere")

    assert_equal @page, thread_on(@block, container: other).container
  end

  test "only a page, a post, a block or a library image takes a note" do
    thread = Notes::Thread.new(subject: Tag.create!(name: "news"), last_message_at: Time.current)

    assert_not thread.valid?
    assert_includes thread.errors[:subject_type], "is not included in the list"
  end

  test "state, origin and quote are checked" do
    assert_not Notes::Thread.new(subject: @page, state: "closed", last_message_at: Time.current).valid?
    assert_not Notes::Thread.new(subject: @page, origin_view: "email", last_message_at: Time.current).valid?
    assert_not Notes::Thread.new(subject: @page, quote: "x" * 501, last_message_at: Time.current).valid?
    assert Notes::Thread.new(subject: @page, quote: "x" * 500, origin_view: "mind_graph", last_message_at: Time.current).valid?
  end

  test "scopes split the threads of a container" do
    open = thread_on(@page)
    pinned = thread_on(@block, pinned: true, pinned_at: Time.current)
    done = thread_on(@page, state: "resolved", resolved_at: Time.current)

    assert_equal [ open, pinned ].sort_by(&:id), Notes::Thread.where(container: @page).unresolved.order(:id).to_a
    assert_equal [ done ], Notes::Thread.where(container: @page).resolved.to_a
  end

  test "deleting a thread's author leaves the thread; deleting the thread takes its messages and deliveries" do
    writer = User.create!(email_address: "writer@example.com", password: "a-long-password-1")
    thread = thread_on(@page, created_by: writer)
    message = thread.messages.create!(author: writer, body: "Hello")
    Notes::Delivery.create!(user: users(:two), message: message, thread: thread, reason: "reply")
    Notes::Follow.create!(user: users(:two), thread: thread, following: true)

    writer.destroy!
    assert_nil thread.reload.created_by_id
    assert_nil message.reload.author_id

    thread.destroy!
    assert_equal 0, Notes::Message.count
    assert_equal 0, Notes::Delivery.count
    assert_equal 0, Notes::Follow.count
  end
end
