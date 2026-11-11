require "test_helper"

class Sessions::SweepJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @now = Time.current.change(usec: 0)
    @exporter = Rails.application.config.x.otel_test_exporter
  end

  def start(seen:, signed_in: seen)
    Session.start(user: @user, method: "password", user_agent: nil, ip_address: nil, at: signed_in).tap { |s| s.update_column(:last_seen_at, seen) }
  end

  def ended_events
    Audit::Event.where(action: "session.ended").order(:id)
  end

  test "it ends the idle and the absolute session, keeps the live one and records one event per reason" do
    live = start(seen: @now)
    start(seen: @now - 13.hours, signed_in: @now - 1.day)
    start(seen: @now - 1.hour, signed_in: @now - 15.days)

    assert_difference -> { Session.count }, -2 do
      Sessions::SweepJob.perform_now(at: @now)
    end

    assert_equal [ live ], Session.where(user: @user).to_a
    events = ended_events.last(2)
    assert_equal [ %w[expired_absolute 1], %w[expired_idle 1] ], events.map { |e| [ e.metadata["reason"], e.metadata["count"].to_s ] }
    assert events.all? { |e| e.actor.nil? && e.subject.nil? }
  end

  test "a session that is both idle and absolute is counted once, as absolute" do
    start(seen: @now - 20.days, signed_in: @now - 21.days)
    Sessions::SweepJob.perform_now(at: @now)
    assert_equal [ { "reason" => "expired_absolute", "count" => 1, "after_days" => 14 } ], ended_events.map(&:metadata)
  end

  test "more than a batch is ended and counted in one event" do
    rows = Array.new(3) { start(seen: @now - 13.hours) }
    stub = Sessions::SweepJob.const_get(:BATCH)
    Sessions::SweepJob.send(:remove_const, :BATCH)
    Sessions::SweepJob.const_set(:BATCH, 2)
    Sessions::SweepJob.perform_now(at: @now)
    assert_equal 0, Session.where(id: rows.map(&:id)).count
    assert_equal [ 3 ], ended_events.map { |e| e.metadata["count"] }
  ensure
    Sessions::SweepJob.send(:remove_const, :BATCH)
    Sessions::SweepJob.const_set(:BATCH, stub)
  end

  test "a run with nothing to do records nothing" do
    start(seen: @now)
    assert_no_difference -> { Audit::Event.count } do
      Sessions::SweepJob.perform_now(at: @now)
    end
  end

  test "its span carries the count and is not a root when run under a parent span" do
    start(seen: @now - 13.hours)
    @exporter.reset
    OpenTelemetry.tracer_provider.tracer("test").in_span("job", kind: :consumer) do
      Sessions::SweepJob.perform_now(at: @now)
    end
    span = @exporter.finished_spans.find { |s| s.name == "auth.session_sweep" }
    assert_equal 1, span.attributes["auth.session.count"]
    assert_not_equal OpenTelemetry::Trace::INVALID_SPAN_ID, span.parent_span_id
  end

  test "it is scheduled in every environment, hourly at minute 40 on default" do
    %w[production development test].each do |environment|
      schedule = YAML.load_file(Rails.root.join("config/recurring.yml")).dig(environment, "sessions_sweep")
      assert_equal "Sessions::SweepJob", schedule["class"], environment
      assert_equal "default", schedule["queue"], environment
      assert_equal "every hour at minute 40", schedule["schedule"], environment
    end
  end
end
