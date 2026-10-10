require "test_helper"

# The base of a record's channel (presence spec §4.2): the record is found
# through the read scope as the user is NOW, a rejection says nothing about
# why, and the stream is named by the subclass from the record found.
class Live::RecordChannelTest < ActionCable::Channel::TestCase
  class ProbeChannel < Live::RecordChannel
    cattr_accessor :arrivals, default: []

    def stream_for(record) = "probe:#{record.class.polymorphic_name}-#{record.id}"

    def arrived(record) = arrivals << record
  end

  class BareChannel < Live::RecordChannel
    def stream_for(record) = "bare:#{record.id}"
  end

  tests ProbeChannel

  setup do
    ProbeChannel.arrivals = []
    @page = create_page(title: "Pricing")
    @stranger = User.create!(email_address: "stranger@example.com", password: "a-long-password-1")
  end

  def connect_as(user) = stub_connection(current_user: user, session_id: user.sessions.create!.id)

  test "a reader subscribes to a record they may read, and the subclass is told" do
    connect_as users(:reader)
    subscribe type: "page", id: @page.id

    assert subscription.confirmed?
    assert_has_stream "probe:Page-#{@page.id}"
    assert_equal [ @page ], ProbeChannel.arrivals
  end

  test "a subclass without arrived still subscribes" do
    self.class.tests BareChannel
    connect_as users(:reader)
    subscribe type: "page", id: @page.id

    assert subscription.confirmed?
    assert_has_stream "bare:#{@page.id}"
  ensure
    self.class.tests ProbeChannel
  end

  test "a record out of scope, a trashed one, an unknown kind and a bad id are rejected alike" do
    connect_as @stranger
    subscribe type: "page", id: @page.id
    assert subscription.rejected?

    connect_as users(:one)
    [ [ "tag", 1 ], [ "page", 0 ], [ "page", "1 OR 1=1" ], [ "page", "9" * 30 ], [ nil, nil ] ].each do |type, id|
      subscribe type: type, id: id
      assert subscription.rejected?, [ type, id ].inspect
    end
    @page.update!(trashed_at: Time.current)
    subscribe type: "page", id: @page.id
    assert subscription.rejected?
    assert_empty subscription.streams
    assert_empty ProbeChannel.arrivals
  end

  test "someone demoted since the socket connected is judged by their grants" do
    owner = User.create!(email_address: "second-owner@example.com", password: "a-long-password-1", owner: true)
    connect_as User.find(owner.id)
    subscribe type: "page", id: @page.id
    assert subscription.confirmed?

    User.where(id: owner.id).update_all(owner: false)
    subscribe type: "page", id: @page.id
    assert subscription.rejected?
  end
end
