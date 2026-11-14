require "test_helper"

# The one stream the lists listen on: a signal names a record and nobody
# (presence spec §5.2); what it makes a tab fetch is scoped.
class Presence::ListChannelTest < ActionCable::Channel::TestCase
  test "a signed-in user streams the list and the channel offers no action" do
    stub_connection current_user: users(:reader), session_id: Session.start(user: users(:reader), method: "password", user_agent: nil, ip_address: nil).id
    subscribe
    assert subscription.confirmed?
    assert_has_stream "presence:list"
    assert_empty Presence::ListChannel.action_methods
  end

  test "a socket whose session has ended is rejected" do
    session = Session.start(user: users(:reader), method: "password", user_agent: nil, ip_address: nil)
    stub_connection current_user: users(:reader), session_id: session.id
    session.destroy!
    subscribe
    assert subscription.rejected?
    assert_empty subscription.streams
  end

  test "a socket whose session is held at enrolment is rejected" do
    session = Session.start(user: users(:reader), method: "password", user_agent: nil, ip_address: nil, enrolment_due: true)
    stub_connection current_user: users(:reader), session_id: session.id
    subscribe
    assert subscription.rejected?
    assert_empty subscription.streams
  end
end
