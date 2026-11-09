require "test_helper"

class Notes::MessageTest < ActiveSupport::TestCase
  setup do
    @thread = Notes::Thread.create!(subject: create_page(title: "Pricing"), last_message_at: Time.current)
  end

  test "a body is 1 to 4,000 characters" do
    assert_not @thread.messages.build(body: "  ").valid?
    assert_not @thread.messages.build(body: "x" * 4_001).valid?
    assert @thread.messages.build(body: "x" * 4_000).valid?
  end

  test "the mentioned ids are read from the body on every save" do
    message = @thread.messages.create!(author: users(:one), body: "Ask @[#{users(:two).id}] and @[#{users(:reader).id}], then @[#{users(:two).id}] again")
    assert_equal [ users(:two).id, users(:reader).id ], message.mentioned_user_ids

    message.update!(body: "Nobody now")
    assert_equal [], message.reload.mentioned_user_ids
  end

  # Review Focus 2: a token typed by hand, with a number no bigint holds.
  test "a hand-typed token with a number too long to be an id is saved as text and mentions nobody" do
    message = @thread.messages.create!(author: users(:one), body: "Hi @[99999999999999999999]")

    assert_equal [], message.reload.mentioned_user_ids
    assert_equal "Hi @[99999999999999999999]", message.body
  end

  test "an emoji and a line break are kept as typed" do
    message = @thread.messages.create!(author: users(:one), body: "Looks good 👍\nShip it")

    assert_equal "Looks good 👍\nShip it", message.reload.body
  end

  test "a delivery is one per person and message, and goes with its user" do
    message = @thread.messages.create!(author: users(:one), body: "Hello")
    reader = User.create!(email_address: "told@example.com", password: "a-long-password-1")
    Notes::Delivery.create!(user: reader, message: message, thread: @thread, reason: "mention")

    assert_raises(ActiveRecord::RecordNotUnique) do
      Notes::Delivery.transaction(requires_new: true) { Notes::Delivery.create!(user: reader, message: message, thread: @thread, reason: "reply") }
    end
    assert_not Notes::Delivery.new(user: reader, message: message, thread: @thread, reason: "poke").valid?

    reader.destroy!
    assert_equal 0, Notes::Delivery.count
  end

  test "authors_per_container answers each container's authors with when each wrote last, narrowed by the threads merged in" do
    other = Notes::Thread.create!(subject: @thread.subject, last_message_at: Time.current)
    post_thread = Notes::Thread.create!(subject: create_post(title: "Elsewhere"), last_message_at: Time.current)
    early = 3.hours.ago.change(usec: 0)
    @thread.messages.create!(author: users(:one), body: "One", created_at: early)
    other.messages.create!(author: users(:one), body: "One again", created_at: early + 1.hour)
    other.messages.create!(author: users(:two), body: "Two", created_at: early + 2.hours)
    @thread.messages.create!(author: nil, body: "Nobody", created_at: early + 3.hours)
    post_thread.messages.create!(author: users(:reader), body: "Elsewhere", created_at: early)

    rows = Notes::Message.authors_per_container.merge(Notes::Thread.where(id: [ @thread.id, other.id ])).map do |row|
      [ row[:container_type], row[:container_id], row.author_id, row[:last_wrote_at].change(usec: 0) ]
    end

    assert_equal [ [ "Page", @thread.container_id, users(:two).id, early + 2.hours ], [ "Page", @thread.container_id, users(:one).id, early + 1.hour ] ], rows
  end
end
