require "test_helper"

# What is recorded is the work a request or a job caused, nothing of the
# background's polling (lib/telemetry/work_sampler.rb). Solid Cable's and
# Solid Queue's polls and heartbeats begin a trace with an INTERNAL span of
# the Active Record instrumentation, a request with the Rack
# instrumentation's SERVER span and a performed job with the Active Job
# instrumentation's CONSUMER span; the sampler decides by that kind, for the
# root alone, and every other span follows its parent. These tests start
# spans of each kind on the provider the application configured, so what
# they read is what a backend would be sent.
class Telemetry::WorkSamplerTest < ActiveSupport::TestCase
  DROPPED = %i[internal client producer].freeze
  KEPT = %i[server consumer].freeze

  setup do
    @exporter = Rails.application.config.x.otel_test_exporter
    @exporter.reset
  end

  test "the provider's sampler is the SDK's ParentBased with the work sampler at its root" do
    sampler = OpenTelemetry.tracer_provider.sampler

    assert_instance_of OpenTelemetry::SDK::Trace::Samplers::ParentBased, sampler
    assert_includes sampler.description, "root=Telemetry::WorkSampler::Root{server,consumer}"
  end

  test "a root of each dropped kind is dropped with its whole trace, while a server and a consumer root are kept with theirs" do
    DROPPED.each do |kind|
      tracer.in_span("root #{kind}", kind: kind) do |root|
        assert_not root.recording?, "a #{kind} root is not recorded"
        tracer.in_span("its query") { |child| assert_not child.recording?, "a child of a dropped #{kind} root is not recorded" }
        tracer.in_span("its call", kind: :client) { |child| assert_not child.recording? }
      end
    end
    assert_empty @exporter.finished_spans.map(&:name)

    KEPT.each do |kind|
      tracer.in_span("root #{kind}", kind: kind) do
        tracer.in_span("its query") { tracer.in_span("its nested query") { } }
      end
    end

    spans = @exporter.finished_spans
    assert_equal KEPT.flat_map { |kind| [ "its nested query", "its query", "root #{kind}" ] }, spans.map(&:name)
    spans.group_by(&:trace_id).each_value do |trace|
      assert_equal 3, trace.size, "the root and both of its children are in one trace"
    end
  end

  # A span with no kind is INTERNAL (the API's default), as Active Record's
  # spans are: `SolidCable::Message query` and `ActiveRecord.transaction`.
  test "a span started with no kind and no parent, as a poll's query is, is dropped" do
    tracer.in_span("SolidCable::Message query") { }
    tracer.start_root_span("ActiveRecord.transaction").finish

    assert_empty @exporter.finished_spans
  end

  # A job's perform is started with `start_root_span`, which ignores the
  # context it is in. Solid Queue's worker posts a claimed job to its pool
  # from inside the claim, and the concurrent-ruby instrumentation carries
  # that context into the pool's thread: the perform is a root all the same.
  test "a consumer root started inside a dropped trace is a root of its own and is kept" do
    tracer.in_span("SolidQueue::ReadyExecution query") do
      tracer.start_root_span("default process", kind: :consumer).finish
    end

    assert_equal [ "default process" ], @exporter.finished_spans.map(&:name)
  end

  test "the root sampler decides by kind alone, whatever the name" do
    root = Telemetry::WorkSampler::Root.new
    decide = ->(kind, name) do
      root.should_sample?(trace_id: OpenTelemetry::Trace.generate_trace_id, parent_context: OpenTelemetry::Context.empty,
        links: nil, name: name, kind: kind, attributes: nil)
    end

    KEPT.each { |kind| assert decide.(kind, "SolidCable::Message query").sampled?, kind.to_s }
    DROPPED.each { |kind| assert_not decide.(kind, "GET /").recording?, kind.to_s }
  end

  private
    def tracer = OpenTelemetry.tracer_provider.tracer("work-sampler-test")
end
