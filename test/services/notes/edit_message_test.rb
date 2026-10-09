require "test_helper"

class Notes::EditMessageTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @thread = as(users(:reader)) { Notes::Start.call(@page, body: "Frist draft") }.record
    @message = @thread.first_message
  end

  def edit(body, as_user: users(:reader)) = as(as_user) { Notes::EditMessage.call(@message, body: body) }

  test "the author rewords their note: edited_at is set and the event holds no text" do
    result = edit("First draft, a secret")

    assert result.ok?, result.errors.to_sentence
    assert_equal "First draft, a secret", @message.reload.body
    assert_not_nil @message.edited_at
    event = Audit::Event.order(:id).last
    assert_equal [ "note.edited", { "thread_id" => @thread.id, "message_id" => @message.id } ], [ event.action, event.metadata ]
    assert_no_match(/secret/, event.attributes.to_json)
  end

  test "an unchanged body succeeds, writes nothing and records nothing" do
    assert_no_difference -> { Audit::Event.count } do
      assert edit("Frist draft").ok?
    end
    assert_nil @message.reload.edited_at
  end

  test "only newly mentioned people are told, and only they are checked" do
    lost = User.create!(email_address: "lost@example.com", password: "a-long-password-1")
    @message.update_columns(body: "Ask @[#{lost.id}]", mentioned_user_ids: [ lost.id ])

    result = edit("Ask @[#{lost.id}] and @[#{users(:two).id}]")

    assert result.ok?, result.errors.to_sentence
    assert_equal [ [ users(:two).id, "mention" ] ], Notes::Delivery.pluck(:user_id, :reason)
  end

  test "an edit of a note whose page is in the trash is the same ordinary failure, and writes nothing" do
    @page.update!(trashed_at: Time.current)

    assert_no_difference -> { Audit::Event.count } do
      assert_equal [ "This note is gone: it was deleted, or what it was on was." ], edit("First draft").errors
    end
    assert_equal [ "Frist draft", nil ], @message.reload.then { |message| [ message.body, message.edited_at ] }
  end

  test "nobody edits another person's note, not even someone who may edit the page" do
    result = edit("Mine now", as_user: users(:two))

    assert_predicate result, :denied?
    assert_equal [ "Only the person who wrote a note can change it." ], result.errors
    assert_equal "Frist draft", @message.reload.body
    assert_equal "access.denied", Audit::Event.order(:id).last.action
  end

  test "an author who can no longer read the page can't edit" do
    AccessControl::Membership.where(user: users(:reader)).destroy_all

    assert_predicate edit("Still here?"), :denied?
  end
end
