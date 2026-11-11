require "test_helper"
require "ripper"

# Where a span is started and written, read in `app/` and `lib/` with
# comments stripped (so prose may name any of these calls).
#
# A span is started in `lib/telemetry.rb` alone: `Telemetry.in_span` takes a
# name only from `Telemetry::SPANS` and an attribute only from
# `Telemetry::ATTRIBUTES`, so a new span or attribute has to be named there,
# where its neighbours say what a value may be (a fixed word, a number or a
# Boolean, never text that came in a request). A span started anywhere else
# would skip that list.
#
# A write to a span that some instrumentation started (`set_attribute`,
# `add_attributes`, `add_event`) is written outside the helpers, so each file
# that does it is in WRITERS with its reason, and an entry that matches
# nothing any more fails, so the list can't rot.
class TelemetrySpansTest < ActiveSupport::TestCase
  ROOTS = %w[app lib].freeze
  HELPERS = "lib/telemetry.rb".freeze

  # A start on any receiver but the checked helper's own (`Telemetry.in_span`,
  # which is how a span is started everywhere else). `lib/telemetry.rb` itself
  # starts one on its tracer, so it is the one file that matches.
  STARTS = /(?<!\bTelemetry)\.(in_span|start_span|start_root_span)\b/
  WRITES = /\.(set_attribute|add_attributes|add_event)\b/

  WRITERS = {
    "app/jobs/media/rendition_job.rb" => "the image figures on the job's own span",
    "lib/telemetry/path_scrubber.rb" => "the scrubber's processor rewrites a path or a query an instrumentation started a span with, to what may be sent"
  }.freeze

  PREFIXES = %w[auth. server. http. error.].freeze

  test "no file but lib/telemetry.rb starts a span" do
    starters = sources.select { |_path, code| code.match?(STARTS) }.keys

    assert_equal [ HELPERS ], starters,
      "a span is started through Telemetry.in_span (lib/telemetry.rb), which checks its name and keys; " \
      "lib/telemetry.rb is listed because its helper starts the span on the tracer, so it fails too if the helper stops doing so"
  end

  test "the starter pattern lets the checked helper's callers through and catches every other start" do
    [ 'Telemetry.in_span("auth.sign_in") { }', '::Telemetry.in_span("auth.throttle", kind: :internal) { |span| span }' ].each do |call|
      assert_no_match STARTS, call
    end

    [
      'tracer.in_span("auth.sign_in") { }',
      'Telemetry.tracer.in_span("auth.sign_in") { }',
      'OpenTelemetry.tracer_provider.tracer("x").in_span("auth.sign_in") { }',
      'OpenTelemetry.tracer_provider.tracer("x").start_span("auth.sign_in")',
      'Telemetry::Other.start_root_span("auth.sign_in")',
      'MyTelemetry.in_span("auth.sign_in") { }'
    ].each { |call| assert_match STARTS, call }
  end

  test "every write to a span outside lib/telemetry.rb is listed with its reason, and every listed one is still there" do
    writers = sources.select { |path, code| path != HELPERS && code.match?(WRITES) }.keys.sort

    assert_equal WRITERS.keys.sort, writers,
      "a file that writes to a span outside lib/telemetry.rb is in WRITERS with its reason, and an entry whose file stopped writing goes"
    WRITERS.each_value { |reason| assert reason.present? }
  end

  test "every span name and attribute key is auth., server., http. or error." do
    offenders = (Telemetry::SPANS + Telemetry::ATTRIBUTES).reject { |name| name.start_with?(*PREFIXES) }

    assert_empty offenders
  end

  test "both lists are frozen and name each entry once" do
    assert Telemetry::SPANS.frozen? && Telemetry::ATTRIBUTES.frozen?
    assert_equal Telemetry::SPANS.uniq, Telemetry::SPANS
    assert_equal Telemetry::ATTRIBUTES.uniq, Telemetry::ATTRIBUTES
  end

  private

  # Every Ruby file under ROOTS, as `{ relative path => code without comments }`.
  def sources
    @sources ||= ROOTS.flat_map { |root| Dir[Rails.root.join(root, "**/*.{rb,rake}")] }.sort.to_h do |path|
      [ path.delete_prefix("#{Rails.root}/"), without_comments(File.read(path)) ]
    end
  end

  def without_comments(code)
    Ripper.lex(code).reject { |(_, type, _)| type == :on_comment || type == :on_embdoc || type == :on_embdoc_beg || type == :on_embdoc_end }.map { |token| token[2] }.join
  end
end
