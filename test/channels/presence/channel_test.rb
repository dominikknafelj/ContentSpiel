require "test_helper"

# A tab's presence on one record (presence spec §5.2). The record is found
# through the read scope by the base class; nothing is written for a record
# the user may not read.
class Presence::ChannelTest < ActionCable::Channel::TestCase
  include ActionCable::TestHelper

  TAB = "tab-12345678".freeze

  setup do
    @page = create_page(title: "Pricing")
    @stranger = User.create!(email_address: "stranger@example.com", password: "a-long-password-1")
  end

  def connect_as(user) = stub_connection(current_user: user, session_id: user.sessions.create!.id)

  def record_stream = "presence:record:Page-#{@page.id}"

  def list_payload = { "kind" => "presence" }

  def decoded(stream) = broadcasts(stream).map { |payload| ActiveSupport::JSON.decode(payload) }

  test "subscribing writes the row, streams the record's presence and tells the record and the list" do
    connect_as users(:reader)
    subscribe type: "page", id: @page.id, tab: TAB

    assert subscription.confirmed?
    mark = Presence::Mark.sole
    assert_equal [ users(:reader).id, "Page", @page.id, TAB, "here" ], mark.values_at(:user_id, :record_type, :record_id, :tab, :state)
    assert_has_stream record_stream
    assert_equal [ { "kind" => "presence" } ], decoded(record_stream)
    assert_equal [ list_payload ], decoded("presence:list")
  end

  test "an image's stream has no colons" do
    asset = create_media_asset
    connect_as users(:two)
    subscribe type: "media", id: asset.id, tab: TAB
    assert_has_stream "presence:record:MediaAsset-#{asset.id}"
    assert_equal "Media::Asset", Presence::Mark.sole.record_type
  end

  test "a record out of scope, a trashed one, an unknown kind, a bad id and a tab of the wrong shape are rejected and write nothing" do
    connect_as @stranger
    subscribe type: "page", id: @page.id, tab: TAB
    assert subscription.rejected?

    connect_as users(:one)
    [ [ "tag", 1, TAB ], [ "page", 0, TAB ], [ "page", "1 OR 1=1", TAB ], [ nil, nil, TAB ],
      [ "page", @page.id, nil ], [ "page", @page.id, "" ], [ "page", @page.id, "A sentence" ], [ "page", @page.id, "short" ],
      [ "page", @page.id, "tab-12345678\nx" ], [ "page", @page.id, [ TAB ] ] ].each do |type, id, tab|
      subscribe type: type, id: id, tab: tab
      assert subscription.rejected?, [ type, id, tab ].inspect
    end
    @page.update!(trashed_at: Time.current)
    subscribe type: "page", id: @page.id, tab: TAB
    assert subscription.rejected?

    assert_equal 0, Presence::Mark.count
    assert_empty subscription.streams
    assert_equal 0, broadcasts(record_stream).size
    assert_equal 0, broadcasts("presence:list").size
  end

  test "a socket whose session has ended is rejected and writes nothing" do
    connected = User.find(users(:reader).id)
    connect_as connected
    Session.where(user_id: connected.id).destroy_all
    subscribe type: "page", id: @page.id, tab: TAB
    assert subscription.rejected?
    assert_equal 0, Presence::Mark.count
  end

  test "the same tab subscribing twice is one row" do
    connect_as users(:reader)
    subscribe type: "page", id: @page.id, tab: TAB
    subscribe type: "page", id: @page.id, tab: TAB
    assert_equal 1, Presence::Mark.count
  end

  test "report away tells everyone once, and the same state again tells nobody" do
    connect_as users(:reader)
    subscribe type: "page", id: @page.id, tab: TAB
    clear_messages

    perform :report, state: "away"
    assert_equal "away", Presence::Mark.sole.state
    assert_equal 1, broadcasts(record_stream).size
    assert_equal [ list_payload ], decoded("presence:list")

    perform :report, state: "away"
    assert_equal 1, broadcasts(record_stream).size
    assert_equal 1, broadcasts("presence:list").size

    perform :report, state: "gone"
    perform :report, {}
    assert_equal "away", Presence::Mark.sole.state
    assert_equal 1, broadcasts(record_stream).size

    perform :report, state: "here"
    assert_equal 2, broadcasts(record_stream).size
  end

  test "a command numbered at or below the last one worked on is dropped: reports that crossed end in the newer state" do
    connect_as users(:reader)
    subscribe type: "page", id: @page.id, tab: TAB
    clear_messages

    perform :report, state: "away", seq: 2
    perform :report, state: "here", seq: 1
    assert_equal "away", Presence::Mark.sole.state
    perform :beat, state: "here", seq: 2
    assert_equal "away", Presence::Mark.sole.state
    assert_equal 1, broadcasts(record_stream).size

    perform :report, state: "here", seq: 3
    assert_equal "here", Presence::Mark.sole.state
    perform :report, state: "away"
    assert_equal "away", Presence::Mark.sole.state, "a command with no number is worked on as it comes"
  end

  test "two threads reporting at once are worked on one at a time, and the older number loses" do
    connect_as users(:reader)
    subscribe type: "page", id: @page.id, tab: TAB
    inside = 0
    overlapped = false
    original = Presence::Mark.method(:report)
    Presence::Mark.define_singleton_method(:report) do |**args|
      inside += 1
      overlapped ||= inside > 1
      Thread.pass
      original.call(**args)
    ensure
      inside -= 1
    end
    begin
      [ { state: "away", seq: 2 }, { state: "here", seq: 1 } ].map { |data| Thread.new { subscription.report(data.stringify_keys) } }.each(&:join)
    ensure
      Presence::Mark.singleton_class.remove_method(:report)
      Presence::Mark.define_singleton_method(:report, original)
    end
    assert_not overlapped
    assert_equal "away", Presence::Mark.sole.state
  end

  test "a signal on the list names no record, whatever the kind" do
    asset = create_media_asset
    post = create_post(title: "Hello")
    connect_as users(:two)
    [ [ "page", @page.id ], [ "post", post.id ], [ "media", asset.id ] ].each do |type, id|
      subscribe type: type, id: id, tab: TAB
      perform :report, state: "away"
      unsubscribe
    end
    assert_operator broadcasts("presence:list").size, :>=, 9
    assert_equal [ { "kind" => "presence" } ], decoded("presence:list").uniq
  end

  test "a post without a grant and an image without media.upload are rejected through the channel itself" do
    connect_as users(:reader)
    subscribe type: "media", id: create_media_asset.id, tab: TAB
    assert subscription.rejected?
    connect_as @stranger
    subscribe type: "post", id: create_post(title: "Hello").id, tab: TAB
    assert subscription.rejected?
    assert_equal 0, Presence::Mark.count
  end

  test "report always moves seen_at, and state_at only with a change" do
    connect_as users(:reader)
    travel_to(Time.zone.local(2026, 10, 10, 12, 0, 0)) { subscribe type: "page", id: @page.id, tab: TAB }
    travel_to(Time.zone.local(2026, 10, 10, 12, 5, 0)) { perform :report, state: "away" }
    travel_to(Time.zone.local(2026, 10, 10, 12, 9, 0)) { perform :report, state: "away" }
    mark = Presence::Mark.sole
    assert_equal Time.zone.local(2026, 10, 10, 12, 9, 0), mark.seen_at
    assert_equal Time.zone.local(2026, 10, 10, 12, 5, 0), mark.state_at
  end

  test "two connections of one tab: a late unsubscribe of the older leaves the newer subscription's row, and the newer one's deletes it" do
    user = users(:reader)
    stub_connection(current_user: user, session_id: user.sessions.create!.id)
    subscribe type: "page", id: @page.id, tab: TAB
    first = subscription
    stub_connection(current_user: user, session_id: user.sessions.create!.id)
    subscribe type: "page", id: @page.id, tab: TAB
    second = subscription
    assert_equal 1, Presence::Mark.count
    clear_messages

    first.unsubscribe_from_channel
    assert_equal 1, Presence::Mark.count
    assert_equal 0, broadcasts(record_stream).size

    perform :beat
    assert_equal 1, Presence::Mark.count
    second.unsubscribe_from_channel
    assert_equal 0, Presence::Mark.count
  end

  # A reload, or a socket that came back before the server noticed the old
  # one was gone: for a while the same person, record and tab have TWO live
  # subscriptions. The older one's keep-alive finds the row (it is the
  # newer's now) and must leave its token alone, or the newer one's leave
  # would delete nothing and the person would stay until the row went stale.
  test "an older live subscription's beat leaves the newer one's token on the row" do
    user = users(:reader)
    stub_connection(current_user: user, session_id: user.sessions.create!.id)
    subscribe type: "page", id: @page.id, tab: TAB
    first = subscription
    old_token = Presence::Mark.sole.token
    stub_connection(current_user: user, session_id: user.sessions.create!.id)
    subscribe type: "page", id: @page.id, tab: TAB
    second = subscription
    new_token = Presence::Mark.sole.token
    assert_not_equal old_token, new_token

    first.perform_action("action" => "beat", "state" => "here")
    assert_equal new_token, Presence::Mark.sole.token
    first.perform_action("action" => "report", "state" => "away")
    assert_equal [ new_token, "away" ], Presence::Mark.sole.values_at(:token, :state)

    first.unsubscribe_from_channel
    assert_equal 1, Presence::Mark.count
    second.unsubscribe_from_channel
    assert_equal 0, Presence::Mark.count
  end

  # Action Cable works a connection's commands on a pool of threads and takes
  # a subscription out of its list only AFTER `unsubscribed` has run: a beat
  # or a report sent in the same moment as a leave can still reach this
  # object once the row is gone. It must not put the row back, or the person
  # would be shown for as long as a row stays fresh with nobody to remove it.
  test "a beat and a report that come after the leave write no row and tell nobody" do
    connect_as users(:reader)
    subscribe type: "page", id: @page.id, tab: TAB
    left = subscription
    left.unsubscribe_from_channel
    assert_equal 0, Presence::Mark.count
    clear_messages

    left.perform_action("action" => "beat", "state" => "here")
    left.perform_action("action" => "beat", "state" => "away")
    left.perform_action("action" => "report", "state" => "away")
    left.perform_action("action" => "report", "state" => "here")

    assert_equal 0, Presence::Mark.count
    assert_equal 0, broadcasts(record_stream).size
    assert_equal 0, broadcasts("presence:list").size
  end

  # The same for a row that is another subscription's by now: the one that
  # left neither moves its state nor its `seen_at`.
  test "a report that comes after the leave does not touch the row a newer subscription of the tab holds" do
    user = users(:reader)
    stub_connection(current_user: user, session_id: user.sessions.create!.id)
    subscribe type: "page", id: @page.id, tab: TAB
    old = subscription
    stub_connection(current_user: user, session_id: user.sessions.create!.id)
    subscribe type: "page", id: @page.id, tab: TAB
    old.unsubscribe_from_channel
    before = Presence::Mark.sole.attributes
    clear_messages

    travel 10.seconds do
      old.perform_action("action" => "report", "state" => "away")
      old.perform_action("action" => "beat", "state" => "away")
    end

    assert_equal before, Presence::Mark.sole.attributes
    assert_equal 0, broadcasts(record_stream).size
  end

  test "a beat finds no row, puts it back with the subscription's token and the state it carries, and tells the others" do
    connect_as users(:reader)
    subscribe type: "page", id: @page.id, tab: TAB
    token = Presence::Mark.sole.token
    Presence::Mark.delete_all # version: none (a test of presence)
    clear_messages

    perform :beat, state: "away"
    mark = Presence::Mark.sole
    assert_equal [ "away", token ], mark.values_at(:state, :token)
    assert_equal 1, broadcasts(record_stream).size

    perform :beat, state: "away"
    assert_equal 1, broadcasts(record_stream).size
  end

  test "a beat that finds no row heals with the remembered state when it carries none or a bad one" do
    connect_as users(:reader)
    subscribe type: "page", id: @page.id, tab: TAB
    perform :report, state: "away"
    [ {}, { state: "gone" }, { state: 3 } ].each do |data|
      Presence::Mark.delete_all # version: none (a test of presence)
      perform :beat, data
      assert_equal "away", Presence::Mark.sole.state, data.inspect
    end
  end

  test "a report that finds no row heals as well" do
    connect_as users(:reader)
    subscribe type: "page", id: @page.id, tab: TAB
    Presence::Mark.delete_all # version: none (a test of presence)
    perform :report, state: "away"
    assert_equal "away", Presence::Mark.sole.state
  end

  test "a beat carrying a different state than the tab last reported is a report" do
    connect_as users(:reader)
    subscribe type: "page", id: @page.id, tab: TAB
    clear_messages
    perform :beat, state: "away"
    assert_equal "away", Presence::Mark.sole.state
    assert_equal 1, broadcasts(record_stream).size
  end

  test "beat moves seen_at and tells nobody" do
    connect_as users(:reader)
    travel_to(40.seconds.ago) { subscribe type: "page", id: @page.id, tab: TAB }
    clear_messages
    old = Presence::Mark.sole.seen_at

    perform :beat
    assert_operator Presence::Mark.sole.seen_at, :>, old
    assert_equal 0, broadcasts(record_stream).size
    assert_equal 0, broadcasts("presence:list").size
  end

  test "unsubscribing deletes the row and tells the record and the list" do
    connect_as users(:reader)
    subscribe type: "page", id: @page.id, tab: TAB
    clear_messages
    unsubscribe

    assert_equal 0, Presence::Mark.count
    assert_equal [ { "kind" => "presence" } ], decoded(record_stream)
    assert_equal [ list_payload ], decoded("presence:list")
  end

  test "a record that went into the trash while the tab was open can still be left" do
    connect_as users(:reader)
    subscribe type: "page", id: @page.id, tab: TAB
    @page.update!(trashed_at: Time.current)
    unsubscribe
    assert_equal 0, Presence::Mark.count
  end

  test "presence writes nothing of the record, of the content version or of the audit log" do
    updated_at = @page.reload.updated_at
    version = PublicSite::Version.current
    events = Audit::Event.count
    connect_as users(:reader)
    subscribe type: "page", id: @page.id, tab: TAB
    perform :report, state: "away"
    perform :beat
    unsubscribe
    assert_equal updated_at, @page.reload.updated_at
    assert_equal version, PublicSite::Version.current
    assert_equal events, Audit::Event.count
  end

  test "only report and beat are actions" do
    assert_equal %w[beat report], Presence::Channel.action_methods.to_a.sort
  end

  test "a hook is not an action" do
    connect_as users(:reader)
    subscribe type: "page", id: @page.id, tab: TAB
    clear_messages
    %i[arrived unsubscribed subscribed stream_name_for leave].each { |name| perform name, {} }
    assert_equal 1, Presence::Mark.count
    assert_equal 0, broadcasts(record_stream).size
  end

  private

  def clear_messages
    ActionCable.server.pubsub.clear_messages(record_stream)
    ActionCable.server.pubsub.clear_messages("presence:list")
  end
end
