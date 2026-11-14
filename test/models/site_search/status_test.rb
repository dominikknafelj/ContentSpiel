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

  test "the built-in ready counts the kept and published records and names the limited languages switched on" do
    Locales::Enable.call("ja")
    create_page(title: "Counted")
    indexed = SiteSearch::Rebuild.new(name: SiteSearch::Backends::BUILT_IN, backend: SiteSearch::Backends.current).call
    expected = [ Page, Post ].sum { |model| model.kept.count { |record| Publishing::State.of(record).timed? } }

    status = SiteSearch::Status.read

    assert_equal :ready, status.state
    assert_operator indexed, :>, 0
    assert_equal indexed, status.count
    assert_equal expected, status.count
    assert_equal %w[ja], status.limited
  end

  test "no row, no job and a process up for over an hour reads not_built; inside the hour, or with a job, it does not" do
    SiteSearch::IndexState.where(backend: SiteSearch::Backends::BUILT_IN).delete_all
    long_ago = 2.hours.ago

    assert_equal :not_built, SiteSearch::Status.read(job_running: -> { false }, booted_at: long_ago).state
    assert_equal :ready, SiteSearch::Status.read(job_running: -> { true }, booted_at: long_ago).state
    assert_equal :ready, SiteSearch::Status.read(job_running: -> { false }, booted_at: 5.minutes.ago).state
  end

  test "a ready row of another fingerprint with no job reads out_of_date; with a job it reads ready" do
    SiteSearch::IndexState.start!(SiteSearch::Backends::BUILT_IN, total: 0).ready!("another", languages: [], done: 0)

    assert_equal :out_of_date, SiteSearch::Status.read(job_running: -> { false }).state
    assert_equal :ready, SiteSearch::Status.read(job_running: -> { true }).state

    ready_index
    assert_equal :ready, SiteSearch::Status.read(job_running: -> { false }).state
  end

  test "a backend that ignores its deadline reads timeout within about the timeout, and its thread is left alone" do
    hanging = Class.new(SiteSearch::Fake) do
      def health(deadline:)
        sleep 1.5
        SiteSearch::Health.new(status: :ok)
      end
    end
    hanging.new.installed do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      status = SiteSearch::Status.read(timeout: 0.2)

      assert_equal :timeout, status.state
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 1
    end
  end

  test "an :ok that comes after the deadline is no answer" do
    late = Class.new(SiteSearch::Fake) do
      def health(deadline:)
        sleep 0.4
        SiteSearch::Health.new(status: :ok, detail: "late")
      end
    end
    late.new.installed do
      assert_equal :timeout, SiteSearch::Status.read(timeout: 0.1).state
    end
  end

  test "an outside backend's detail is kept on a ready status" do
    detailed = Class.new(SiteSearch::Fake) do
      def health(deadline:) = SiteSearch::Health.new(status: :ok, detail: "3 nodes")
    end
    detailed.new.installed do
      status = SiteSearch::Status.read

      assert_equal :ready, status.state
      assert_equal "3 nodes", status.health.detail
    end
  end

  test "an outside backend gets no limited languages, whatever is switched on" do
    Locales::Enable.call("ja")

    SiteSearch::Fake.new.installed { assert_empty SiteSearch::Status.read.limited }
  end

  # Solid Queue's tables are not in the test database: the queue schema is
  # loaded inside the test's transaction (Postgres rolls DDL back).
  test "a failed reindex job is no running job: the row reads stopped" do
    load Rails.root.join("db/queue_schema.rb")
    was = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :solid_queue
    SiteSearch::IndexState.start!(SiteSearch::Backends::BUILT_IN, total: 10, now: 2.hours.ago)
    job = SolidQueue::Job.create!(queue_name: "default", class_name: SiteSearch::ReindexJob.name, arguments: {})

    assert_equal :building, SiteSearch::Status.read.state

    SolidQueue::FailedExecution.create!(job_id: job.id, error: "RuntimeError")
    assert_equal :stopped, SiteSearch::Status.read.state

    job.update_columns(finished_at: Time.current)
    assert_equal :stopped, SiteSearch::Status.read.state
  ensure
    ActiveJob::Base.queue_adapter = was
  end

  private
    def ready_index
      SiteSearch::IndexState.start!(SiteSearch::Backends::BUILT_IN, total: 0)
        .ready!(SiteSearch::IndexState.fingerprint(SiteSearch::Backends::BUILT_IN), languages: [], done: 0)
    end
end
