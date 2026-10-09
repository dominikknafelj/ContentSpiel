require "test_helper"

class Notes::PersonChannelTest < ActionCable::Channel::TestCase
  test "it streams for the connected user, whatever parameters are sent" do
    stub_connection current_user: users(:reader)

    subscribe user_id: users(:two).id, id: users(:two).id

    assert subscription.confirmed?
    assert_has_stream "notes:person:#{users(:reader).id}"
    assert_equal 1, subscription.streams.size
  end
end
