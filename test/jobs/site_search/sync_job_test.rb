require "test_helper"

# An outside backend is kept by `SiteSearch::SyncJob` (spec §5.4, §5.5,
# §5.7): one job per write, enqueued after the outermost commit, that reads
# the record as it is and sends its documents with their time bounds, or
# removes it. The outside backend here is the in-memory fake, registered as a
# gem's would be.
class SiteSearch::SyncJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include LogCapture

  # The fake counts the calls that reach it, failed ones included.
  # `failing_index` makes `index` alone raise, as an engine that takes
  # removals and refuses new documents; `before_index`, when set, is called
  # once before the next `index` stores anything.
  class CountingFake < SiteSearch::Fake
    attr_reader :calls
    attr_accessor :failing_index, :before_index

    def initialize(...)
      super
      @calls = 0
    end

    def index(documents)
      @calls += 1
      raise IOError, "http://engine/update?doc=secret" if failing_index

      hook, self.before_index = before_index, nil
      hook&.call

      super
    end

    def prune_record(**)
      @calls += 1
      super
    end

    def remove(**)
      @calls += 1
      super
    end
  end

  setup do
    @fake = CountingFake.new
    fake = -> { @fake }
    SiteSearch::Backends.register "test/fake", label: "Fake", backend: fake
    @was = ENV["SEARCH_BACKEND"]
    ENV["SEARCH_BACKEND"] = "test/fake"
    SiteSearch::Backends.forget!
  end

  teardown do
    @was.nil? ? ENV.delete("SEARCH_BACKEND") : ENV["SEARCH_BACKEND"] = @was
    SiteSearch::Backends.forget!
    Rails.application.reloader.prepare!
  end

  def documents_of(record) = @fake.documents.values.select { |document| document.record_type == record.class.polymorphic_name && document.record_id == record.id }

  test "an outside backend gets one job per write after the commit and none for a rolled-back write" do
    page = create_page(title: "Lighthouse", published: false)
    clear_enqueued_jobs

    Page.transaction do
      assert Pages::Save.call(page.reload, attributes: { published: true }).ok?
      assert_no_enqueued_jobs only: SiteSearch::SyncJob
    end
    assert_enqueued_jobs 1, only: SiteSearch::SyncJob
    assert_enqueued_with(job: SiteSearch::SyncJob, args: [ "Page", page.id ])
    assert_equal 0, SiteSearch::Entry.count, "an outside backend leaves the built-in's table alone"

    draft = create_page(title: "Foghorn", published: false)
    clear_enqueued_jobs
    Page.transaction do
      assert Pages::Save.call(draft.reload, attributes: { published: true }).ok?
      raise ActiveRecord::Rollback
    end
    assert_no_enqueued_jobs only: SiteSearch::SyncJob
  end

  test "the trial copy of foresee enqueues nothing" do
    page = create_page(title: "Lighthouse")
    assert Pages::Save.call(page.reload, translations: { "en" => { title: "Foghorn" } }).ok?
    clear_enqueued_jobs

    PublicSite::Paths.foresee(page.reload)

    assert_no_enqueued_jobs only: SiteSearch::SyncJob
  end

  test "the job sends the copy in force and the pending copy with their bounds" do
    page = perform_enqueued_jobs(only: SiteSearch::SyncJob) { create_page(title: "Lighthouse") }
    current = Publishing.current(page)
    assert_equal Locales.enabled.sort, documents_of(page).map(&:language).sort
    assert documents_of(page).all? { |document| document.shown_until.nil? }

    at = 1.day.from_now.change(usec: 0)
    perform_enqueued_jobs(only: SiteSearch::SyncJob) do
      assert Pages::Save.call(page.reload, translations: { "en" => { title: "Foghorn" } }).ok?
      publish_changes(page, at: at)
    end
    pending = Publishing.pending(page)

    by_copy = documents_of(page).group_by(&:copy_id)
    assert_equal [ current.id, pending.id ].sort, by_copy.keys.sort
    by_copy[current.id].each do |document|
      assert_equal current.live_at, document.shown_from
      assert_equal at, document.shown_until, "the copy in force gives way at the pending copy's time"
    end
    by_copy[pending.id].each do |document|
      assert_equal at, document.shown_from
      assert_nil document.shown_until
    end
  end

  test "a record no longer kept and published is removed" do
    page = perform_enqueued_jobs(only: SiteSearch::SyncJob) { create_page(title: "Lighthouse") }
    post = perform_enqueued_jobs(only: SiteSearch::SyncJob) { create_post(title: "Harbour") }
    assert_not_empty documents_of(page)
    assert_not_empty documents_of(post)

    perform_enqueued_jobs(only: SiteSearch::SyncJob) { assert Trash::Move.call(page).ok? }
    assert_empty documents_of(page)

    perform_enqueued_jobs(only: SiteSearch::SyncJob) { assert Posts::Save.call(post.reload, attributes: { published: false }).ok? }
    assert_empty documents_of(post)

    perform_enqueued_jobs(only: SiteSearch::SyncJob) { assert Trash::Restore.call(page.reload).ok? }
    assert_not_empty documents_of(page), "a record restored is sent again"

    perform_enqueued_jobs(only: SiteSearch::SyncJob) { assert delete_for_good(page.reload) }
    assert_empty documents_of(page)
  end

  test "a withdrawn pending copy re-sends the copy in force with no shown_until" do
    page = perform_enqueued_jobs(only: SiteSearch::SyncJob) { create_page(title: "Lighthouse") }
    current = Publishing.current(page)
    perform_enqueued_jobs(only: SiteSearch::SyncJob) do
      assert Pages::Save.call(page.reload, translations: { "en" => { title: "Foghorn" } }).ok?
      publish_changes(page, at: 1.day.from_now)
    end
    assert_equal 2, documents_of(page).map(&:copy_id).uniq.size

    perform_enqueued_jobs(only: SiteSearch::SyncJob) { assert Publishing::CancelScheduledChange.call(page.reload).ok? }

    assert_equal [ current.id ], documents_of(page).map(&:copy_id).uniq
    assert documents_of(page).all? { |document| document.shown_until.nil? }
  end

  test "a failure retries and is reported without its message" do
    page = create_page(title: "Lighthouse")
    @fake = CountingFake.new(raise_with: RuntimeError.new("http://engine/select?q=secret"))
    SiteSearch::Backends.forget!
    exporter = Rails.application.config.x.otel_test_exporter
    exporter.reset

    report = nil
    log = capture_log do
      report = assert_error_reported(SiteSearch::Unavailable) do
        perform_enqueued_jobs(only: SiteSearch::SyncJob) { SiteSearch::SyncJob.perform_later("Page", page.id) }
      end
    end

    assert_equal 5, @fake.calls, "five attempts"
    assert_includes log, "SiteSearch::Unavailable", "the retries are logged, by the scrubbed error"
    assert_not_includes log, "secret"
    spans = exporter.finished_spans
    assert_equal 5, spans.count { |span| span.name == "search.index" }
    written = spans.map { |span| [ span.name, span.attributes.to_a, span.status&.description, Array(span.events).map { |event| [ event.name, event.attributes.to_a ] } ].flatten.compact.join(" ") }.join("\n")
    assert_includes written, "SiteSearch::Unavailable", "the span records the scrubbed error"
    assert_not_includes written, "secret"
    assert_nil report.error.cause
    assert_equal "test/fake: RuntimeError", report.error.message
    assert_not_includes report.error.message, "secret"
    assert_equal "test/fake", report.error.backend
    assert_equal "RuntimeError", report.error.error_class
  end

  test "the job records search.index with the backend and the count" do
    page = create_page(title: "Lighthouse")
    exporter = Rails.application.config.x.otel_test_exporter
    exporter.reset

    SiteSearch::SyncJob.perform_now("Page", page.id)

    span = exporter.finished_spans.find { |each| each.name == "search.index" }
    assert span, exporter.finished_spans.map(&:name).inspect
    job = exporter.finished_spans.find { |each| each.kind == :consumer }
    assert_equal job.span_id, span.parent_span_id, "under the job's consumer span"
    assert_equal "test/fake", span.attributes["search.backend"]
    assert_equal Locales.enabled.size, span.attributes["search.documents"]
  end

  test "a failing index leaves the record's old documents in place" do
    page = perform_enqueued_jobs(only: SiteSearch::SyncJob) { create_page(title: "Lighthouse") }
    before = documents_of(page).map(&:key).sort
    @fake.failing_index = true

    assert_error_reported(SiteSearch::Unavailable) do
      perform_enqueued_jobs(only: SiteSearch::SyncJob) do
        assert Pages::Save.call(page.reload, translations: { "en" => { title: "Foghorn" } }).ok?
        publish_changes(page)
      end
    end

    assert_equal before, documents_of(page).map(&:key).sort, "the documents sent before stand until new ones are taken"
  end

  test "a page's change enqueues its subpages too" do
    parent = create_page(title: "Coast")
    child = create_page(title: "Lighthouse", parent: parent)
    grandchild = create_page(title: "Lamp room", parent: child)
    clear_enqueued_jobs

    assert Trash::Move.call(parent.reload).ok?

    [ parent, child, grandchild ].each { |page| assert_enqueued_with(job: SiteSearch::SyncJob, args: [ "Page", page.id ]) }
  end

  test "a page moved enqueues its job" do
    page = create_page(title: "Lighthouse")
    other = create_page(title: "Coast")
    clear_enqueued_jobs

    assert Pages::Move.call(page.reload, parent: other.reload, position: 0).ok?

    assert_enqueued_with(job: SiteSearch::SyncJob, args: [ "Page", page.id ])
  end

  test "a record rescheduled with no copy taken resends its documents from the new time" do
    first = 1.day.from_now.change(usec: 0)
    later = 3.days.from_now.change(usec: 0)
    page = perform_enqueued_jobs(only: SiteSearch::SyncJob) do
      page = create_page(title: "Lighthouse", published: false)
      assert Pages::Save.call(page.reload, attributes: { published_at: first }).ok?
      page
    end
    assert documents_of(page).all? { |document| document.shown_from == first }
    copies = Publishing::Version.of(page).count

    perform_enqueued_jobs(only: SiteSearch::SyncJob) { assert Pages::Save.call(page.reload, attributes: { published_at: later }).ok? }

    assert_equal copies, Publishing::Version.of(page).count, "a reschedule takes no copy"
    assert_not_empty documents_of(page)
    assert documents_of(page).all? { |document| document.shown_from == later }
  end

  test "a job that built a superseded copy's documents leaves the new copy's in place" do
    page = perform_enqueued_jobs(only: SiteSearch::SyncJob) { create_page(title: "Lighthouse") }
    old = Publishing.current(page)

    # Job A has built the old copy's documents; before they reach the
    # engine an editor publishes, and job B, for the new copy, runs in full.
    @fake.before_index = lambda do
      assert Pages::Save.call(page.reload, translations: { "en" => { title: "Beacon" } }).ok?
      publish_changes(page)
      SiteSearch::SyncJob.perform_now("Page", page.id)
    end
    SiteSearch::SyncJob.perform_now("Page", page.id)

    current = Publishing.current(page)
    assert_not_equal old.id, current.id
    assert_equal [ current.id ], documents_of(page).map(&:copy_id).uniq, "the new copy's documents stand, the old copy's are pruned"
  end

  test "a database error while the job reads the record is retried with the job's backoff" do
    page = create_page(title: "Lighthouse")
    clear_enqueued_jobs

    with_singleton_override(Page, :find_by, ->(*) { raise ActiveRecord::Deadlocked, "deadlock detected" }) do
      SiteSearch::SyncJob.perform_now("Page", page.id)
    end

    assert_enqueued_with(job: SiteSearch::SyncJob, args: [ "Page", page.id ])
    assert_equal 0, @fake.calls, "nothing reached the engine"
  end

  test "an enqueue that raises after the commit is reported and the write stands" do
    page = create_page(title: "Lighthouse", published: false)

    report = assert_error_reported(SiteSearch::Unavailable) do
      with_singleton_override(SiteSearch::SyncJob, :perform_later, ->(*) { raise ActiveRecord::ConnectionNotEstablished, "queue at postgres://secret" }) do
        assert Pages::Save.call(page.reload, attributes: { published: true }).ok?
      end
    end

    assert page.reload.live?
    assert copied?(page)
    assert_equal "test/fake: ActiveRecord::ConnectionNotEstablished", report.error.message
  end
end
