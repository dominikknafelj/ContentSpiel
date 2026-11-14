require "test_helper"

class SiteSearch::StatusTest < ActiveSupport::TestCase
  test "a health past the deadline reads timeout" do
    SiteSearch::Fake.new(sleep_for: 10).installed do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      status = SiteSearch::Status.read

      assert_equal :timeout, status.state
      assert_equal "Fake", status.label
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, SiteSearch::Status::TIMEOUT + 1
    end
  end

  test "a backend that raises reads timeout and its message is nowhere in the status" do
    SiteSearch::Fake.new(raise_with: RuntimeError.new("http://engine/select?q=secret")).installed do
      status = SiteSearch::Status.read

      assert_equal :timeout, status.state
      assert_no_match(/secret/, status.inspect)
    end
  end

  test "a backend's own warning is unhealthy, with its Health" do
    warned = Class.new(SiteSearch::Fake) do
      def health(deadline:) = SiteSearch::Health.new(status: :warn, detail: "The index is behind.")
    end
    warned.new.installed do
      status = SiteSearch::Status.read

      assert_equal :unhealthy, status.state
      assert_equal "The index is behind.", status.health.detail
      assert_empty status.limited
    end
  end

  test "an outside backend that answers is ready, with no count" do
    SiteSearch::Fake.new.installed do
      status = SiteSearch::Status.read

      assert_equal :ready, status.state
      assert_nil status.count
    end
  end

  test "a building row with no job for over an hour reads stopped" do
    state = SiteSearch::IndexState.start!(SiteSearch::Backends::BUILT_IN, total: 1200, now: 2.hours.ago)
    state.progress!(340)

    stopped = SiteSearch::Status.read(job_running: -> { false })
    assert_equal :stopped, stopped.state
    assert_equal [ 340, 1200 ], [ stopped.done, stopped.total ]

    assert_equal :building, SiteSearch::Status.read(job_running: -> { true }).state
  end

  test "a building row that started a minute ago is building, and the job is not asked" do
    SiteSearch::IndexState.start!(SiteSearch::Backends::BUILT_IN, total: 10, now: 1.minute.ago)

    assert_equal :building, SiteSearch::Status.read(job_running: -> { false }).state
  end

  test "the built-in ready counts its records and names the limited languages switched on" do
    SiteSearch::IndexState.start!(SiteSearch::Backends::BUILT_IN, total: 0).ready!("x", languages: [], done: 0)
    Locales::Enable.call("ja")

    status = SiteSearch::Status.read

    assert_equal :ready, status.state
    assert_kind_of Integer, status.count
    assert_equal %w[ja], status.limited
  end
end
