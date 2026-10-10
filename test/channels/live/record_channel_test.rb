require "test_helper"

# The base of a record's channel (presence spec §4.2): the record is found
# through the read scope as the user is NOW, a rejection says nothing about
# why, and the stream is named by the subclass from the record found.
class Live::RecordChannelTest < ActionCable::Channel::TestCase
  class ProbeChannel < Live::RecordChannel
    cattr_accessor :arrivals, default: []

    private

    def stream_name_for(record) = "probe:#{record.class.polymorphic_name}-#{record.id}"

    def arrived(record) = arrivals << record
  end

  class BareChannel < Live::RecordChannel
    private

    def stream_name_for(record) = "bare:#{record.id}"
  end

  class ForgetfulChannel < Live::RecordChannel
  end

  class RaisingChannel < Live::RecordChannel
    private

    def stream_name_for(record) = "raising:#{record.id}"

    def arrived(_record) = raise(IOError, "the row could not be written")
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

  test "an image is rejected for a user without media.upload and found for one with it" do
    asset = create_media_asset
    self.class.tests Class.new(Live::RecordChannel) { private def stream_name_for(record) = "m:#{record.id}" }
    connect_as users(:reader)
    subscribe type: "media", id: asset.id
    assert subscription.rejected?

    connect_as users(:two)
    subscribe type: "media", id: asset.id
    assert subscription.confirmed?
  ensure
    self.class.tests ProbeChannel
  end

  test "a nil subscriber, a session that ended, is rejected" do
    connected = User.find(users(:reader).id)
    connect_as connected
    Session.where(user_id: connected.id).destroy_all
    subscribe type: "page", id: @page.id
    assert subscription.rejected?
    assert_empty ProbeChannel.arrivals
  end

  test "a hook is not an action: a client that performs it runs nothing" do
    connect_as users(:reader)
    subscribe type: "page", id: @page.id
    ProbeChannel.arrivals = []

    assert_not_includes ProbeChannel.action_methods, "arrived"
    assert_not_includes ProbeChannel.action_methods, "stream_name_for"
    perform :arrived, {}
    perform :stream_name_for, {}
    perform :stream_for, {}
    assert_empty ProbeChannel.arrivals
    assert_equal [ "probe:Page-#{@page.id}" ], streams_of(subscription)
  end

  test "no channel under app/channels that descends from Live::RecordChannel offers an action it does not mean to" do
    Rails.application.eager_load!
    meant = { "Notes::RecordChannel" => [] }
    subclasses = Live::RecordChannel.descendants.reject { |klass| klass.name.nil? || klass.name.start_with?("Live::RecordChannelTest") }
    assert_includes subclasses.map(&:name), "Notes::RecordChannel"
    subclasses.each do |klass|
      assert_equal meant.fetch(klass.name, []).sort, klass.action_methods.to_a.sort, "#{klass.name} offers a client an action it does not mean to"
    end
  end

  test "the test subclasses make the guard able to fail: a public hook would be an action" do
    leaky = Class.new(Live::RecordChannel) { def arrived(_record) = nil }
    assert_includes leaky.action_methods, "arrived"
  end

  test "a hook that raises in arrived rejects cleanly with nothing opened" do
    self.class.tests RaisingChannel
    connect_as users(:reader)
    assert_raises(IOError) { subscribe type: "page", id: @page.id }
    assert_empty streams_of(subscription)
    assert_not subscription.confirmed?
  ensure
    self.class.tests ProbeChannel
  end

  test "a subclass that forgot stream_name_for fails loudly, not with Rails' stream_for" do
    self.class.tests ForgetfulChannel
    connect_as users(:reader)
    error = assert_raises(NotImplementedError) { subscribe type: "page", id: @page.id }
    assert_match(/ForgetfulChannel must define a private stream_name_for/, error.message)
  ensure
    self.class.tests ProbeChannel
  end

  test "Notes::RecordChannel's hook is private too" do
    assert_empty Notes::RecordChannel.action_methods
    tests_notes = Notes::RecordChannel
    self.class.tests tests_notes
    connect_as users(:reader)
    subscribe type: "page", id: @page.id
    perform :stream_name_for, {}
    assert_equal [ "notes:record:Page-#{@page.id}" ], streams_of(subscription)
  ensure
    self.class.tests ProbeChannel
  end

  private

  def streams_of(subscription) = subscription.send(:streams).to_a
end
