require "test_helper"

class Notes::PersonChannelTest < ActionCable::Channel::TestCase
  setup { @session = users(:reader).sessions.create! }

  test "it streams for the connected user, whatever parameters are sent" do
    stub_connection current_user: users(:reader), session_id: @session.id

    subscribe user_id: users(:two).id, id: users(:two).id

    assert subscription.confirmed?
    assert_has_stream "notes:person:#{users(:reader).id}"
    assert_equal 1, subscription.streams.size
  end

  # A socket is authenticated once, at connect: a subscription asks again.
  test "a socket whose session has ended, or names someone else's, is rejected" do
    stub_connection current_user: users(:reader), session_id: users(:two).sessions.create!.id
    subscribe
    assert subscription.rejected?

    stub_connection current_user: users(:reader), session_id: @session.id
    @session.destroy!
    subscribe
    assert subscription.rejected?
    assert_empty subscription.streams
  end

  test "a user deleted since the socket connected is rejected" do
    connected = User.find(users(:reader).id)
    stub_connection current_user: connected, session_id: @session.id
    assert Users::Destroy.call(users(:reader), actor: nil).ok?

    subscribe

    assert subscription.rejected?
    assert_empty subscription.streams
  end
end
