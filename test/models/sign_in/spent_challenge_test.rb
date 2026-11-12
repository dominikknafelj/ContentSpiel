require "test_helper"

# A passkey challenge answered once is spent for good: the second spend of
# the same digest is refused by the table's unique index, in one statement.
class SignIn::SpentChallengeTest < ActiveSupport::TestCase
  test "the first spend of a digest is true, the second is false, and another digest is its own" do
    expires_at = 5.minutes.from_now
    assert SignIn::SpentChallenge.spend!("digest-a", expires_at: expires_at)
    assert_not SignIn::SpentChallenge.spend!("digest-a", expires_at: expires_at)
    assert SignIn::SpentChallenge.spend!("digest-b", expires_at: expires_at)
    assert_equal 2, SignIn::SpentChallenge.count
  end

  test "a database error is not rescued: it is no spend" do
    with_singleton_override(SignIn::SpentChallenge, :insert_all, ->(*, **) { raise ActiveRecord::StatementInvalid, "the insert failed" }) do
      assert_raises(ActiveRecord::StatementInvalid) { SignIn::SpentChallenge.spend!("digest-c", expires_at: 5.minutes.from_now) }
    end
  end

  test "sweep deletes the rows past their expiry and keeps the others" do
    now = Time.current.change(usec: 0)
    SignIn::SpentChallenge.spend!("old", expires_at: now - 1.second)
    SignIn::SpentChallenge.spend!("live", expires_at: now + 1.second)

    assert_equal 1, SignIn::SpentChallenge.sweep(at: now)
    assert_equal [ "live" ], SignIn::SpentChallenge.pluck(:digest)
  end
end

# Two connections at once need rows the other connection can see, so this
# class runs outside the test transaction.
class SignIn::SpentChallengeRaceTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  DIGEST = "race-digest-of-a-test".freeze

  setup { clean }
  teardown { clean }

  def clean = SignIn::SpentChallenge.where(digest: DIGEST).delete_all # version: none (a test's own rows)

  # One thread per connection of the pool, the test's own given back, so
  # every thread holds its connection at the gate and all the inserts are
  # sent at once.
  test "of several spends of one digest at the same moment exactly one wins" do
    gate = Queue.new
    ActiveRecord::Base.connection_pool.release_connection
    count = ActiveRecord::Base.connection_pool.size
    threads = Array.new(count) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          SignIn::SpentChallenge.spend!(DIGEST, expires_at: 5.minutes.from_now)
        end
      end
    end
    count.times { gate << :go }
    results = threads.map(&:value)

    assert_equal 1, results.count(true)
    assert_equal count - 1, results.count(false)
    assert_equal 1, SignIn::SpentChallenge.where(digest: DIGEST).count
  end
end
