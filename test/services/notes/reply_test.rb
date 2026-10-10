require "test_helper"

class Notes::ReplyTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @thread = as(users(:two)) { Notes::Start.call(@page, body: "Is this right?") }.record
  end

  def reply(as_user: users(:reader), body: "Yes.") = as(as_user) { Notes::Reply.call(@thread, body: body) }

  test "a reply adds a message, moves last_message_at, tells the followers and is audited without text" do
    result = travel_to(1.minute.from_now) { reply(body: "a secret answer") }

    assert result.ok?, result.errors.to_sentence
    assert_equal [ "Is this right?", "a secret answer" ], @thread.reload.messages.map(&:body)
    assert_equal result.record.created_at.to_i, @thread.last_message_at.to_i
    assert_equal [ [ users(:two).id, "reply" ] ], Notes::Delivery.pluck(:user_id, :reason)
    event = Audit::Event.order(:id).last
    assert_equal [ "note.replied", "Page", @page.id ], [ event.action, event.subject_type, event.subject_id ]
    assert_equal({ "thread_id" => @thread.id, "message_id" => result.record.id }, event.metadata)
    assert_no_match(/secret/, event.attributes.to_json)
  end

  test "a reply to a resolved thread reopens it and says so in the log" do
    @thread.update!(state: "resolved", resolved_at: Time.current, resolved_by: users(:two))

    assert reply.ok?
    assert_equal [ "open", nil, nil ], @thread.reload.then { |thread| [ thread.state, thread.resolved_at, thread.resolved_by_id ] }
    assert_equal %w[note.replied note.reopened], Audit::Event.order(:id).last(2).map(&:action)
  end

  # Spec §7, "A message deleted while someone replies": the reply still lands.
  test "a reply lands in a thread one of whose messages was deleted meanwhile" do
    gone = as(users(:two)) { Notes::Reply.call(@thread, body: "Never mind") }.record
    stale = Notes::Thread.find(@thread.id)
    as(users(:two)) { Notes::DeleteMessage.call(gone) }

    assert as(users(:reader)) { Notes::Reply.call(stale, body: "Still answering") }.ok?
    assert_equal [ "Is this right?", "Still answering" ], @thread.reload.messages.map(&:body)
  end

  # Review Focus 3.
  test "a reply to a thread that was removed meanwhile is an ordinary failure" do
    stale = Notes::Thread.find(@thread.id)
    @thread.destroy!

    result = as(users(:reader)) { Notes::Reply.call(stale, body: "Too late") }

    assert_equal [ "This note is gone: it was deleted, or what it was on was." ], result.errors
    assert_equal 0, Notes::Message.count
  end

  # One rule for a reply, an edit and a delete: a container in the trash
  # takes no write to its notes.
  test "a reply to a thread whose page is in the trash is the same ordinary failure, and writes nothing" do
    @page.update!(trashed_at: Time.current)

    assert_no_difference [ -> { Notes::Message.count }, -> { Notes::Delivery.count }, -> { Audit::Event.count } ] do
      assert_equal [ "This note is gone: it was deleted, or what it was on was." ], reply.errors
    end
    assert_not_predicate reply, :denied?
  end

  test "a stranger is refused" do
    stranger = User.create!(email_address: "stranger@example.com", password: "a-long-password-1")

    assert_predicate reply(as_user: stranger), :denied?
    assert_equal 1, @thread.messages.count
  end
end
