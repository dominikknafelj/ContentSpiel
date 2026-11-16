require "test_helper"

# The suggestions in flight per process (`SiteSearch::SuggestLimit.in_a_slot`):
# at most `IN_FLIGHT` at once across threads, a request past them answered
# at once, and a slot given back on every path.
class SiteSearch::SuggestLimitTest < ActiveSupport::TestCase
  IN_FLIGHT = SiteSearch::SuggestLimit::IN_FLIGHT

  test "IN_FLIGHT is below the default Puma thread count, so a thread is always left for pages" do
    assert_operator IN_FLIGHT, :<, 3
    assert_operator IN_FLIGHT, :>=, 1
  end

  test "threads past IN_FLIGHT are refused at once while the others hold their slots, and a slot freed is taken again" do
    entered = Queue.new
    go = Queue.new
    holders = Array.new(IN_FLIGHT) { Thread.new { SiteSearch::SuggestLimit.in_a_slot { entered << true; go.pop } } }
    IN_FLIGHT.times { entered.pop }

    refused = Thread.new { SiteSearch::SuggestLimit.in_a_slot { flunk "a slot past IN_FLIGHT was given" } }.value
    assert_equal false, refused

    IN_FLIGHT.times { go << true }
    assert_equal [ true ] * IN_FLIGHT, holders.map(&:value)
    assert_equal true, SiteSearch::SuggestLimit.in_a_slot { nil }
    assert_equal IN_FLIGHT, SiteSearch::SuggestLimit::SLOTS.available_permits
  ensure
    IN_FLIGHT.times { go&.push(true) }
    holders&.each(&:join)
  end

  test "a raise inside gives the slot back and is raised through" do
    assert_raises(RuntimeError) { SiteSearch::SuggestLimit.in_a_slot { raise "down" } }
    assert_equal IN_FLIGHT, SiteSearch::SuggestLimit::SLOTS.available_permits
  end
end
