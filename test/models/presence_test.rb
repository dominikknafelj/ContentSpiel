require "test_helper"

# The numbers of presence that must agree across Ruby and JavaScript.
class PresenceTest < ActiveSupport::TestCase
  # A hidden tab's timers are throttled by the browser to about one run a
  # minute, so its keep-alive then arrives about once a minute: two of those
  # and some slack must fit inside the time a row is trusted, or a person who
  # is only hidden flickers away. The scripts take BEAT_EVERY from the server
  # (`data-...-beat-value`), so this is the one place the relation is stated.
  test "a row is trusted for at least four keep-alives" do
    assert_operator Presence::STALE_AFTER, :>=, 4 * Presence::BEAT_EVERY
  end
end
