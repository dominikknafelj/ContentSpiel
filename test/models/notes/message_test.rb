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
end
