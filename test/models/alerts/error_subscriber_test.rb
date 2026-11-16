require "test_helper"

class Alerts::ErrorSubscriberTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include LogCapture

  SECRET = "password=hunter2".freeze
  FILE = "test/models/alerts/error_subscriber_test.rb".freeze

  # An error raised on this line, with a backtrace of its own.
  def raised(error)
    raise error
  rescue error.class => caught
    caught
  end
  RAISED_LINE = __LINE__ - 4

  # A job of the Alerts namespace other than RecordErrorJob, as the check job
  # will be: the rule is the namespace, not one class.
  class Alerts::ErrorSubscriberTestJob < ApplicationJob
    def perform = nil
  end

  test "a report is one log line without its message, a span event and a job with five arguments" do
    exporter = Rails.application.config.x.otel_test_exporter
    exporter.reset
    error = raised(RuntimeError.new(SECRET))
    place = "#{FILE}:#{RAISED_LINE}"

    freeze_time do
      log = capture_log do
        with_error_alerts do
          Telemetry.tracer.in_span("request", kind: :server) { Rails.error.report(error, source: "application.action_dispatch") }
        end
      end

      assert_equal [ "[ContentSpiel] Error reported: RuntimeError at #{place} (application.action_dispatch)" ], ours(log)
      assert_no_match "hunter2", log
      assert_enqueued_jobs 1
      assert_enqueued_with(job: Alerts::RecordErrorJob,
        args: [ { error_class: "RuntimeError", place: place, source: "application.action_dispatch", handled: true, at: Time.current } ])
      assert_no_match "hunter2", enqueued_jobs.to_s
    end

    events = exporter.finished_spans.flat_map { |span| Array(span.events) }
    assert_equal [ "error.reported" ], events.map(&:name)
    assert_equal({ "error.type" => "RuntimeError", "error.place" => place }, events.first.attributes.to_h)
  end

  test "an unhandled report is logged at error, a handled one at warn" do
    levels = [ false, true ].to_h do |handled|
      [ handled, level_of { with_error_alerts { Rails.error.report(raised(RuntimeError.new("x")), handled: handled) } } ]
    end

    assert_equal({ false => "ERROR", true => "WARN" }, levels)
  end

  test "an error Rails answers with a 4xx is no alert" do
    log = capture_log do
      with_error_alerts do
        Rails.error.report(raised(ActiveRecord::RecordNotFound.new("no page")))
        Rails.error.report(raised(ActionController::BadRequest.new("bad")))
      end
    end

    assert_no_enqueued_jobs
    assert_equal "", log
  end

  test "a report from a job of the Alerts namespace is dropped, as Solid Queue makes it after the perform" do
    log = capture_log do
      with_error_alerts do
        Rails.error.report(raised(ActiveRecord::ConnectionNotEstablished.new("down")), handled: false, context: { job: Alerts::RecordErrorJob.new })
        Rails.error.report(raised(RuntimeError.new("x")), handled: false, context: { job: Alerts::ErrorSubscriberTestJob.new })
      end
    end

    assert_no_enqueued_jobs
    assert_equal "", log
  end

  test "a report from another job is an alert" do
    with_error_alerts do
      Rails.error.report(raised(RuntimeError.new("x")), handled: false, context: { job: SiteSearch::PruneWordsJob.new })
    end

    assert_enqueued_jobs 1, only: Alerts::RecordErrorJob
  end

  test "the subscriber never raises: a failed enqueue is one line with the classes only" do
    error = raised(RuntimeError.new(SECRET))
    log = nil

    with_singleton_override(Alerts::RecordErrorJob, :perform_later, ->(**) { raise ActiveRecord::ConnectionNotEstablished, "could not connect: #{SECRET}" }) do
      log = capture_log do
        with_error_alerts { assert_nil Rails.error.report(error) }
      end
    end

    assert_no_match "hunter2", log
    assert_equal [ "[ContentSpiel] Error reported: RuntimeError at #{FILE}:#{RAISED_LINE} (application)",
                   "[ContentSpiel] Error report not recorded: RuntimeError (ActiveRecord::ConnectionNotEstablished)" ], ours(log)
    assert_no_enqueued_jobs
  end

  test "off in tests unless asked" do
    log = capture_log { Rails.error.report(raised(RuntimeError.new("x"))) }

    assert_no_enqueued_jobs
    assert_equal "", log
  end

  test "a report inside a transaction that rolls back still arrives" do
    with_error_alerts do
      ActiveRecord::Base.transaction(requires_new: true) do
        Rails.error.report(raised(RuntimeError.new("x")))
        raise ActiveRecord::Rollback
      end
    end

    assert_enqueued_jobs 1, only: Alerts::RecordErrorJob
  end

  test "the place is the first frame inside the application, relative, or nil" do
    error = RuntimeError.new("x")
    error.set_backtrace([
      "/somewhere/gems/actionpack/lib/action_dispatch/x.rb:10:in 'call'",
      "#{Rails.root}/vendor/bundle/ruby/gems/rack/lib/rack.rb:3:in 'call'",
      "#{Rails.root}/app/models/page.rb:120:in 'Page#title'",
      "#{Rails.root}/app/controllers/pages_controller.rb:7:in 'show'"
    ])
    assert_equal "app/models/page.rb:120", Alerts::ErrorSubscriber.place_for(error)

    error.set_backtrace([ "/somewhere/gems/x.rb:1:in 'y'" ])
    assert_nil Alerts::ErrorSubscriber.place_for(error)
    assert_nil Alerts::ErrorSubscriber.place_for(RuntimeError.new("never raised"))
  end

  test "a report with no place in the application says so without a place" do
    error = RuntimeError.new("x")
    error.set_backtrace([ "/somewhere/gems/x.rb:1:in 'y'" ])

    log = capture_log { with_error_alerts { Rails.error.report(error) } }

    assert_equal [ "[ContentSpiel] Error reported: RuntimeError (application)" ], ours(log)
    assert_nil enqueued_jobs.first[:args].first["place"]
  end

  private

  # The lines this feature writes; Active Job adds its own "Enqueued ..." line
  # with the job's arguments, which hold no message either.
  def ours(log) = log.lines.map(&:chomp).select { |line| line.start_with?("[ContentSpiel]") }

  # The severity of the one line `Rails.logger` was handed in the block.
  def level_of
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io)
    logger.formatter = ->(severity, *) { "#{severity}\n" }
    were = Rails.logger
    Rails.logger = logger
    yield
    io.string.chomp
  ensure
    Rails.logger = were
  end
end
