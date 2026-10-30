require "test_helper"

class Notes::DeliveriesTest < ActiveSupport::TestCase
  setup do
    @dana, @eli, @fay = %w[dana eli fay].map { |name| User.create!(email_address: "#{name}@example.com", password: "a-long-password-1") }
    @thread = Notes::Thread.create!(subject: create_page(title: "Pricing"), created_by: @dana, last_message_at: Time.current)
  end

  # Not `message`: that is `Minitest::Assertions#message`, which every
  # assertion calls to build its failure text.
  def write_message(author, body) = @thread.messages.create!(author: author, body: body)

  # A message as a service would send it: the rows it tells.
  def send_message(author, body) = Notes::Deliveries.for_new_message(write_message(author, body), actor_user: author)

  def told(rows) = rows.map { |row| [ row.user_id, row.reason ] }.sort

  def following = Notes::Follow.where(thread: @thread, following: true).pluck(:user_id).sort

  test "the first message tells the people it mentions, never its author, and both now follow" do
    rows = send_message(@dana, "Hi @[#{@eli.id}] and me, @[#{@dana.id}]")

    assert_equal [ [ @eli.id, "mention" ] ], told(rows)
    assert_equal [ @thread.id ], rows.map(&:thread_id).uniq
    assert_equal [ @dana.id, @eli.id ].sort, following
  end

  test "a reply tells every follower; a mention wins over a reply" do
    send_message(@dana, "Hi @[#{@eli.id}]")

    assert_equal [ [ @dana.id, "mention" ], [ @eli.id, "reply" ] ].sort, told(send_message(@fay, "Sure, @[#{@dana.id}]"))
    assert_equal [ @dana.id, @eli.id, @fay.id ].sort, following
  end

  test "an explicit unfollow is kept when that person writes again, and undone when they are mentioned" do
    send_message(@dana, "Start")
    send_message(@eli, "Hello")
    Notes::Follow.find_by!(thread: @thread, user: @eli).update!(following: false)

    assert_equal [ [ @dana.id, "reply" ] ], told(send_message(@eli, "Still not following"))
    assert_equal [ @dana.id ], following
    assert_equal [], told(send_message(@dana, "Nobody is told: Eli stopped following"))

    assert_equal [ [ @eli.id, "mention" ] ], told(send_message(@dana, "Back to you, @[#{@eli.id}]"))
    assert_equal [ @dana.id, @eli.id ].sort, following
  end

  test "a mentioned user who no longer exists is skipped and follows nothing" do
    gone = User.create!(email_address: "gone@example.com", password: "a-long-password-1")
    gone_id = gone.id
    gone.destroy!

    assert_equal [], told(send_message(@dana, "Hi @[#{gone_id}]"))
    assert_equal [ @dana.id ], following
  end

  test "an edit tells only the newly mentioned, who now follow, and turns a reply row for that message into a mention" do
    send_message(@dana, "Start")
    reply = write_message(@eli, "Hello")
    Notes::Deliveries.for_new_message(reply, actor_user: @eli)
    Notes::Delivery.where(user: @dana).update_all(read_at: Time.current) # version: none (a test's own setup)

    rows = Notes::Deliveries.for_edit(reply, newly_mentioned: [ @dana.id, @fay.id ], actor_user: @eli)

    assert_equal [ [ @dana.id, "mention" ], [ @fay.id, "mention" ] ].sort, told(rows)
    assert_equal 1, Notes::Delivery.where(user: @dana, message: reply).count
    assert_nil Notes::Delivery.find_by(user: @dana, message: reply).read_at
    assert_includes following, @fay.id
  end

  # Review Focus 1: the row for this person and the first message exists already.
  test "a resolve and a reopen tell the followers on the first message, reusing the row that is already there" do
    first = write_message(@dana, "Hi @[#{@eli.id}]")
    Notes::Deliveries.for_new_message(first, actor_user: @dana)
    send_message(@fay, "Done")
    Notes::Delivery.where(user: @eli).update_all(read_at: 1.hour.ago) # version: none (a test's own setup)

    rows = Notes::Deliveries.for_state(@thread, "resolved", actor_user: @fay)

    assert_equal [ [ @dana.id, "resolved" ], [ @eli.id, "resolved" ] ].sort, told(rows)
    assert_equal [ first.id ], rows.map(&:message_id).uniq
    assert_equal 1, Notes::Delivery.where(user: @eli, message: first).count
    assert_nil Notes::Delivery.find_by(user: @eli, message: first).read_at

    again = Notes::Deliveries.for_state(@thread, "reopened", actor_user: @dana)

    assert_equal [ [ @eli.id, "reopened" ], [ @fay.id, "reopened" ] ].sort, told(again)
    assert_equal 1, Notes::Delivery.where(user: @eli, message: first).count
  end

  test "someone who stopped following is not told of a resolve" do
    send_message(@dana, "Start")
    send_message(@eli, "Hello")
    Notes::Follow.find_by!(thread: @thread, user: @dana).update!(following: false)

    assert_equal [], told(Notes::Deliveries.for_state(@thread, "resolved", actor_user: @eli))
  end

  # `User.can_sign_in`: an invited person is told nothing and follows
  # nothing, whether mentioned or already a follower.
  test "an invited person is not told and does not follow, mentioned or following" do
    invited = invited_user("invited@example.com")

    assert_equal [], told(send_message(@dana, "Hi @[#{invited.id}]"))
    assert_equal [ @dana.id ], following

    Notes::Follow.create!(thread: @thread, user: invited, following: true)
    assert_equal [ [ @dana.id, "reply" ] ], told(send_message(@eli, "Hello"))
  end
end
