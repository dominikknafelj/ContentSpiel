require "test_helper"

# The library's one stream: whoever holds the media read right streams it,
# anyone else is rejected alike (media-folders spec §11).
class Media::LibraryChannelTest < ActionCable::Channel::TestCase
  def connect_as(user) = stub_connection(current_user: user, session_id: Session.start(user: user, method: "password", user_agent: nil, ip_address: nil).id)

  test "a media.upload holder streams the library, anyone else is rejected alike" do
    connect_as users(:two)
    subscribe
    assert subscription.confirmed?
    assert_has_stream Media::LibrarySignals::STREAM

    connect_as users(:reader)
    subscribe
    assert subscription.rejected?
    assert_empty subscription.streams

    session = Session.start(user: users(:two), method: "password", user_agent: nil, ip_address: nil)
    stub_connection current_user: users(:two), session_id: session.id
    session.destroy!
    subscribe
    assert subscription.rejected?
  end

  test "the channel defines no public method" do
    assert_empty Media::LibraryChannel.action_methods
    assert_empty Media::LibraryChannel.public_instance_methods(false)
  end
end
