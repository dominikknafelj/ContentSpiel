require "test_helper"

# The test backend obeys the contract every backend's test includes, and
# can be told to fail or to be slow, for the callers' tests.
class SiteSearch::FakeTest < ActiveSupport::TestCase
  include SiteSearchBackendContract
  include SiteSearchBackendContract::BareDocuments

  def backend = @backend ||= SiteSearch::Fake.new

  def deadline_in(seconds) = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds

  def query(text) = SiteSearch::Query.new(text: text, language: "en", page: 1, per_page: 10, now: Time.current)

  test "raise_with raises from search and health" do
    fake = SiteSearch::Fake.new(raise_with: RuntimeError.new("engine down"))
    assert_equal "engine down", assert_raises(RuntimeError) { fake.search(query("a"), deadline: deadline_in(1)) }.message
    assert_raises(RuntimeError) { fake.health(deadline: deadline_in(1)) }
  end

  test "sleep_for past the deadline raises at the deadline" do
    fake = SiteSearch::Fake.new(sleep_for: 5)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_raises(Timeout::Error) { fake.search(query("a"), deadline: start + 0.1) }
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - start, :<, 1
  end
end
