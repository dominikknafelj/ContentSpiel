require "test_helper"

# The one sender of live signals (presence spec §4.2): a payload says THAT
# something changed (a kind, ids, a reason, an origin) and never what, and
# `later` refuses at the call anything that could carry text.
class Live::SignalsTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  STREAM = "live:test".freeze

  test "a payload of a kind and ids is sent after the commit and not before" do
    ActiveRecord::Base.transaction do
      Live::Signals.later(STREAM, { kind: "threads", thread_id: 4, reason: "reply", origin: "tab-12345678" })
      assert_equal 0, broadcasts(STREAM).size
    end
    assert_equal [ { "kind" => "threads", "thread_id" => 4, "reason" => "reply", "origin" => "tab-12345678" } ],
      broadcasts(STREAM).map { |payload| ActiveSupport::JSON.decode(payload) }
  end

  test "a rolled-back transaction sends nothing" do
    ActiveRecord::Base.transaction do
      Live::Signals.later(STREAM, { kind: "threads", thread_id: 4 })
      raise ActiveRecord::Rollback
    end
    assert_equal 0, broadcasts(STREAM).size
  end

  test "a payload that could carry text is refused at the call" do
    [ { kind: "x", title: "About" }, { kind: "x", thread_id: "abc" }, { kind: "x", body: 1 },
      { kind: "A sentence of free text" }, { kind: "x", reason: "Please read this note" }, { kind: "x", reason: "x" * 33 },
      { kind: "x", origin: "A secret sentence" }, { kind: "x", origin: "<script>" }, { kind: "x", thread_id: 1.5 },
      { kind: "presence", record: [ "page", 3 ] }, { kind: "x", record: [ "page", "3" ] }, { kind: "x", record: "page" },
      { kind: "x", kind_id: [ 1 ] },
      {}, { thread_id: 1 }, { kind: "x", origin: nil }, { kind: "x", reason: nil }, { "kind" => "x", kind: "y" }, { 1 => "x", kind: "x" } ].each do |payload|
      assert_raises(ArgumentError, payload.inspect) { Live::Signals.later(STREAM, payload) }
    end
    assert_equal 0, broadcasts(STREAM).size
  end

  test "a refused payload is refused inside a transaction too, before anything is queued" do
    ActiveRecord::Base.transaction do
      assert_raises(ArgumentError) { Live::Signals.later(STREAM, { kind: "x", title: "About" }) }
    end
    assert_equal 0, broadcasts(STREAM).size
  end

  test "ids and nil ids pass" do
    Live::Signals.later(STREAM, { kind: "x", thread_id: nil })
    Live::Signals.later(STREAM, { kind: "presence", user_id: 9, reason: "left_page" })
    assert_equal 2, broadcasts(STREAM).size
  end

  test "the origin is the tab's id, echoed only in the shape TAB allows" do
    Current.set(notes_tab: "tab-12345678") { assert_equal "tab-12345678", Live::Signals.origin }
    Current.set(notes_tab: "A secret sentence") { assert_nil Live::Signals.origin }
    assert_equal Live::Signals::TAB, Notes::Signals::TAB
  end

  test "a broadcast that fails is logged by kind and class, reported, and swallowed" do
    broken = Class.new(ActionCable::SubscriptionAdapter::Test) { def broadcast(*) = raise(IOError, "the cable is down") }
    ActionCable.server.instance_variable_set(:@pubsub, broken.new(ActionCable.server)) # put back by ActionCable::TestHelper's teardown
    reported = []
    subscriber = Class.new { define_method(:report) { |error, **| reported << error.message } }.new
    Rails.error.subscribe(subscriber)
    log = StringIO.new
    logger = ActiveSupport::Logger.new(log)
    Rails.logger.broadcast_to(logger)

    assert_nothing_raised { Live::Signals.later(STREAM, { kind: "threads", thread_id: 4 }) }

    assert_equal [ "the cable is down" ], reported
    assert_equal [ "Live signal not sent (threads): IOError" ], log.string.lines.grep(/Live signal/).map(&:strip)
  ensure
    Rails.error.unsubscribe(subscriber) if subscriber
    Rails.logger.stop_broadcasting_to(logger) if logger
  end

  test "string keys are sent, logged by kind, and the payload sent is a copy" do
    log = StringIO.new
    logger = ActiveSupport::Logger.new(log)
    Rails.logger.broadcast_to(logger)
    broken = Class.new(ActionCable::SubscriptionAdapter::Test) { def broadcast(*) = raise(IOError, "down") }
    ActionCable.server.instance_variable_set(:@pubsub, broken.new(ActionCable.server))
    Live::Signals.later(STREAM, { "kind" => "threads", "thread_id" => 4 })
    assert_includes log.string, "Live signal not sent (threads): IOError"
  ensure
    Rails.logger.stop_broadcasting_to(logger) if logger
  end

  test "a hash changed after the call changes nothing that is sent" do
    payload = { kind: "threads", thread_id: 4 }
    ActiveRecord::Base.transaction do
      Live::Signals.later(STREAM, payload)
      payload[:title] = "About"
      payload[:kind] = "changed"
    end
    assert_equal [ { "kind" => "threads", "thread_id" => 4 } ], broadcasts(STREAM).map { |p| ActiveSupport::JSON.decode(p) }
  end
end
