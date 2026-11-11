require "test_helper"

class Notes::PersonChannelTest < ActionCable::Channel::TestCase
  setup { @session = Session.start(user: users(:reader), method: "password", user_agent: nil, ip_address: nil) }

  test "it streams for the connected user, whatever parameters are sent" do
    stub_connection current_user: users(:reader), session_id: @session.id

    subscribe user_id: users(:two).id, id: users(:two).id

    assert subscription.confirmed?
    assert_has_stream "notes:person:#{users(:reader).id}"
    assert_equal 1, subscription.streams.size
  end

  # A socket is authenticated once, at connect: a subscription asks again.
  test "a socket whose session has ended, or names someone else's, is rejected" do
    stub_connection current_user: users(:reader), session_id: Session.start(user: users(:two), method: "password", user_agent: nil, ip_address: nil).id
    subscribe
    assert subscription.rejected?

    stub_connection current_user: users(:reader), session_id: @session.id
    @session.destroy!
    subscribe
    assert subscription.rejected?
    assert_empty subscription.streams
  end

  # The socket connected while its session lived; its row stands after
  # either timeout until a request or the sweep ends it, and is no session.
  test "a socket whose session has passed either timeout is rejected, though its row stands" do
    stub_connection current_user: users(:reader), session_id: @session.id

    travel Session::IDLE_TIMEOUT + 1.minute do
      subscribe
      assert subscription.rejected?
      assert_empty subscription.streams
    end

    @session.update_columns(last_seen_at: Time.current, expires_at: 1.minute.ago)
    subscribe
    assert subscription.rejected?
    assert Session.exists?(@session.id)
  end

  test "a user deleted since the socket connected is rejected" do
    connected = User.find(users(:reader).id)
    stub_connection current_user: connected, session_id: @session.id
    assert Users::Destroy.call(users(:reader), actor: nil).ok?

    subscribe

    assert subscription.rejected?
    assert_empty subscription.streams
  end

  test "the channel offers a client no action: subscribed is private" do
    assert_empty Notes::PersonChannel.action_methods
  end
end
