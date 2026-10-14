module Telemetry
  # Which traces are sent: those that begin with a request or with a job
  # being performed, and nothing that begins anywhere else.
  #
  # Production runs Solid Cable on Postgres and Solid Queue inside Puma, and
  # both poll their tables from threads of their own. Solid Cable's listener
  # asks for new messages every 0.1 seconds (`polling_interval` in
  # config/cable.yml), Solid Queue's worker asks for ready jobs and its
  # processes write a heartbeat, and every one of those statements is a span
  # of the Active Record instrumentation, which makes a span whether or not
  # anything is being traced (`_query_by_sql`, `transaction`, `touch` and the
  # rest are wrapped unconditionally in opentelemetry-instrumentation-
  # active_record 0.13). On a small, almost idle site that was about 820,000
  # spans a day (2026-10-13: `SolidCable::Message query` 697,000, each its own
  # trace; `ActiveRecord.transaction` 183,000, Solid Queue's claims and
  # heartbeats under it), against a few hundred page requests: Honeycomb's
  # free plan (20 million events a month) would have been gone in three
  # weeks, and the requests were hard to find among them.
  #
  # The SDK decides this itself, by a SAMPLER, and nothing is filtered by
  # hand. A sampler is asked once for each span as it starts, before anything
  # is recorded: a span it drops is a non-recording span that no processor
  # sees and no exporter is handed, and it costs no allocation of a span's
  # data. `ParentBased` asks this class only for a ROOT, a span with no
  # parent; every other span follows its parent's decision, so a root that is
  # dropped drops its whole trace and a root that is kept keeps all of its
  # spans, its database spans included. The decision is by the root's KIND,
  # which each instrumentation states, not by its name:
  #
  #   :server    a request. The Rack instrumentation's span, which Action
  #              Pack names after the controller and action. Kept.
  #   :consumer  a job being performed. The Active Job instrumentation starts
  #              `<queue> process` with `start_root_span(kind: :consumer)`
  #              (handlers/perform.rb, `propagation_style: :link`, the
  #              default), always as a root of its own, also when the worker
  #              posted it from inside a polling trace that was dropped, and
  #              links it to the request that enqueued it. Kept.
  #   :internal  every other span that has no parent: Active Record's spans
  #              on a polling or heartbeat thread, a sweep of Solid Queue's
  #              own, and, since no Action Cable instrumentation is
  #              installed, a channel action's statements and Solid Cable's
  #              batched INSERT of a broadcast, which its writer thread makes
  #              apart from the request or job that broadcast (both are named
  #              in docs/reference/hosting.md, "Telemetry"). Dropped.
  #   :client, :producer
  #              an outgoing call or an enqueue with no request or job around
  #              it: Solid Queue's scheduler enqueuing a recurring task (the
  #              job's perform is kept, as its own trace). Dropped. Inside a
  #              request or a job both are children and are kept with it.
  #
  # Why not a list of span names: the names are the instrumentation's
  # (`SolidCable::Message query`), they change with a gem's version or a
  # model's name, and a list drops a span of a request that happens to share
  # a name with a poll. Why not instrumentation options: the Active Record
  # instrumentation has none that tells a poll from a request's query, and
  # turning it off would take the database spans out of the requests too.
  #
  # The other two cases of `ParentBased` keep the SDK's defaults: a span whose
  # parent came in a request's `traceparent` header follows that header's
  # sampled flag, as it did before. This sampler replaces whatever
  # OTEL_TRACES_SAMPLER would have chosen (config/initializers/opentelemetry.rb
  # assigns it after the SDK is configured).
  #
  # Nothing here changes what the scrubber sees: `PathScrubber::Processor` is
  # still the first processor of every span that is recorded, and only a
  # recorded span is ever exported.
  module WorkSampler
    # The kinds of root whose trace is sent. A Symbol, as the API passes it
    # (`OpenTelemetry::Trace::SpanKind::SERVER` is `:server`).
    KEPT_ROOTS = %i[server consumer].freeze

    # What the provider is given: the SDK's own ParentBased, with Root for
    # the one case it delegates to us.
    def self.sampler
      OpenTelemetry::SDK::Trace::Samplers.parent_based(root: Root.new)
    end

    # The root's decision. The interface is the SDK's Sampler duck type:
    # `should_sample?` and `description`, as `ConstantSampler` has it.
    class Root
      def should_sample?(trace_id:, parent_context:, links:, name:, kind:, attributes:)
        decision =
          if KEPT_ROOTS.include?(kind)
            OpenTelemetry::SDK::Trace::Samplers::Decision::RECORD_AND_SAMPLE
          else
            OpenTelemetry::SDK::Trace::Samplers::Decision::DROP
          end

        OpenTelemetry::SDK::Trace::Samplers::Result.new(
          decision: decision,
          tracestate: OpenTelemetry::Trace.current_span(parent_context).context.tracestate
        )
      end

      def description = "Telemetry::WorkSampler::Root{#{KEPT_ROOTS.join(",")}}"
    end
  end
end
