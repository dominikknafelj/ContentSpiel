require "test_helper"

# The index builds itself (spec §6.6): the boot's check finds it empty or
# stale for the backend in use and enqueues `SiteSearch::ReindexJob`, which
# replaces the documents record by record and marks the backend's state row
# ready with the fingerprint it built. A language change enqueues the job
# after its commit (§6.5).
class SiteSearch::ReindexJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include SearchBuildLock

  # The built-in, wrapped: each `index` is counted, `on_index` is called
  # with the count before the real one, and `raise_on` (a page) makes the
  # call that sends its documents raise, as an engine that stops answering
  # half way. By the record and not by the count, since the fixtures' pages
  # are sent too, in an order of their own.
  class Wrapped
    attr_reader :indexed

    def initialize(raise_on: nil, on_index: nil)
      @backend = SiteSearch::Postgres.new
      @raise_on = raise_on
      @on_index = on_index
      @indexed = 0
    end

    def index(documents)
      @indexed += 1
      @on_index&.call(@indexed)
      raise IOError, "http://engine/update?secret" if @raise_on && documents.any? { |document| document.record_id == @raise_on.id }

      @backend.index(documents)
    end

    def remove(**) = @backend.remove(**)
    def prune_record(**) = @backend.prune_record(**)
  end

  def entries_of(record) = SiteSearch::Entry.where(record_type: record.class.polymorphic_name, record_id: record.id)

  def found(text, language: "en")
    query = SiteSearch::Query.new(text: text, language: language, page: 1, per_page: 10, now: Time.current)
    SiteSearch::Postgres.new.search(query, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3).hits.map { |hit| [ hit.record_type, hit.record_id ] }
  end

  def state(name = "postgres") = SiteSearch::IndexState.for(name)

  # The built-in's fingerprint as it reads with `Documents::REVISION` at
  # `revision`: the fingerprint of an index built by older rules.
  def fingerprint_with(revision:)
    was = SiteSearch::Documents::REVISION
    silence_warnings { SiteSearch::Documents.const_set(:REVISION, revision) }
    SiteSearch::IndexState.fingerprint("postgres")
  ensure
    silence_warnings { SiteSearch::Documents.const_set(:REVISION, was) }
  end

  def with_fake
    fake = SiteSearch::Fake.new
    SiteSearch::Backends.register "test/fake", label: "Fake", backend: -> { fake }
    was = ENV["SEARCH_BACKEND"]
    ENV["SEARCH_BACKEND"] = "test/fake"
    SiteSearch::Backends.forget!
    yield fake
  ensure
    was.nil? ? ENV.delete("SEARCH_BACKEND") : ENV["SEARCH_BACKEND"] = was
    SiteSearch::Backends.forget!
    Rails.application.reloader.prepare!
  end

  test "an empty index is built at the boot's check with nobody asking" do
    page = create_page(title: "Lighthouse")
    post = create_post(title: "Foghorn")
    draft = create_page(title: "Buoy", published: false)
    SiteSearch::Entry.delete_all
    assert_nil state
    clear_enqueued_jobs

    SiteSearch::IndexCheckJob.perform_now
    assert_enqueued_with(job: SiteSearch::ReindexJob, args: [ "postgres" ])

    perform_enqueued_jobs(only: SiteSearch::ReindexJob)

    assert state.ready?
    assert_equal SiteSearch::IndexState.fingerprint("postgres"), state.fingerprint
    kept = Page.kept.where.not(published_at: nil).count + Post.kept.where.not(published_at: nil).count
    assert_equal kept, state.total
    assert_equal kept, state.done
    assert_equal Locales.enabled.sort, entries_of(page).pluck(:locale).sort
    assert_equal Locales.enabled.sort, entries_of(post).pluck(:locale).sort
    assert_empty entries_of(draft)
    assert_equal [ [ "Page", page.id ] ], found("lighthouse")

    clear_enqueued_jobs
    SiteSearch::IndexCheckJob.perform_now
    assert_no_enqueued_jobs only: SiteSearch::ReindexJob
  end

  test "a fallback change makes the index stale and the job rebuilds it" do
    page = create_page(title: "Lighthouse", translations: { "en" => { title: "Lighthouse", slug: "tower" }, "de" => { title: "Leuchtturm", slug: "turm" }, "es" => { slug: "torre" } })
    SiteSearch::Rebuild.new.call
    assert_equal [ [ "Page", page.id ] ], found("lighthouse", language: "es")
    clear_enqueued_jobs

    assert Locales::Configure.call([ { code: "en" }, { code: "de" }, { code: "es", fallbacks: [ "de" ] } ], actor: nil).ok?

    assert_enqueued_with(job: SiteSearch::ReindexJob)
    assert SiteSearch::IndexState.empty_or_stale?("postgres")
    assert_empty found("leuchtturm", language: "es"), "the old documents answer until the job has run"

    perform_enqueued_jobs(only: SiteSearch::ReindexJob)

    assert_equal [ [ "Page", page.id ] ], found("leuchtturm", language: "es")
    assert_empty found("lighthouse", language: "es")
    assert_not SiteSearch::IndexState.empty_or_stale?("postgres")
  end

  test "REVISION 2 makes a REVISION 1 index stale and the build rewrites it" do
    page = create_page(title: "Lighthouse", translations: { "en" => { title: "Lighthouse", slug: "beacon-tower" } })
    SiteSearch::Rebuild.new.call
    state.ready!(fingerprint_with(revision: 1), languages: Locales.enabled, done: state.done)
    SiteSearch::Entry.where(record_type: "Page", record_id: page.id).delete_all # version: none (a test stands in for an index built before the slug was a document's word)
    clear_enqueued_jobs

    assert_equal 2, SiteSearch::Documents::REVISION
    assert SiteSearch::IndexState.empty_or_stale?("postgres")
    perform_enqueued_jobs { SiteSearch::IndexCheckJob.perform_now }

    assert_equal SiteSearch::IndexState.fingerprint("postgres"), state.fingerprint
    assert_not SiteSearch::IndexState.empty_or_stale?("postgres")
    assert_equal [ [ "Page", page.id ] ], found("beacon")
  end

  test "the built-in's fingerprint holds Postgres::REVISION" do
    was = SiteSearch::Postgres::REVISION
    before = SiteSearch::IndexState.fingerprint("postgres")
    silence_warnings { SiteSearch::Postgres.const_set(:REVISION, was + 1) }
    assert_not_equal before, SiteSearch::IndexState.fingerprint("postgres")
  ensure
    silence_warnings { SiteSearch::Postgres.const_set(:REVISION, was) }
  end

  test "a new SEARCH_BACKEND finds its index empty and builds it" do
    page = create_page(title: "Lighthouse")
    SiteSearch::Rebuild.new.call
    postgres = state.attributes

    with_fake do |fake|
      clear_enqueued_jobs
      SiteSearch::IndexCheckJob.perform_now
      assert_enqueued_with(job: SiteSearch::ReindexJob, args: [ "test/fake" ])
      perform_enqueued_jobs(only: SiteSearch::ReindexJob)

      assert state("test/fake").ready?
      assert_equal Locales.enabled.sort, fake.documents.values.select { |document| document.record_id == page.id && document.record_type == "Page" }.map(&:language).sort
      assert_not_equal SiteSearch::IndexState.fingerprint("postgres"), SiteSearch::IndexState.fingerprint("test/fake"), "the built-in's fingerprint holds its configurations"
    end

    assert_equal postgres, state.reload.attributes, "the old backend's row is left"
  end

  test "a second job enqueued while one runs is discarded, and one run after it finds nothing to do" do
    assert_equal 1, SiteSearch::ReindexJob.concurrency_limit
    assert_equal :discard, SiteSearch::ReindexJob.concurrency_on_conflict
    assert_equal 1.hour, SiteSearch::ReindexJob.concurrency_duration
    assert_equal "site_search_reindex:postgres", SiteSearch::ReindexJob.new("postgres").concurrency_key.split("/").last
    assert_equal "site_search_reindex:postgres", SiteSearch::ReindexJob.new.concurrency_key.split("/").last

    create_page(title: "Lighthouse")
    SiteSearch::ReindexJob.perform_now("postgres")
    finished = state.finished_at
    clear_enqueued_jobs

    assert_no_changes -> { SiteSearch::Entry.maximum(:created_at) } do
      SiteSearch::ReindexJob.perform_now("postgres")
    end
    assert_equal finished, state.reload.finished_at
    assert_no_enqueued_jobs only: SiteSearch::ReindexJob
  end

  test "search answers from the old documents while the build is half way" do
    first = create_page(title: "Lighthouse")
    second = create_page(title: "Foghorn")
    old = entries_of(second).pluck(:id).sort

    assert_raises(SiteSearch::Unavailable) { SiteSearch::Rebuild.new(backend: Wrapped.new(raise_on: second)).call }

    assert state.building?
    assert_nil state.fingerprint, "a build that stopped is stale"
    assert SiteSearch::IndexState.empty_or_stale?("postgres")
    assert_equal old, entries_of(second).pluck(:id).sort, "the record not reached keeps its documents"
    assert_equal [ [ "Page", first.id ] ], found("lighthouse")
    assert_equal [ [ "Page", second.id ] ], found("foghorn")
  end

  test "a language switched off loses its documents at the end of the build" do
    page = create_page(title: "Lighthouse")
    draft = create_page(title: "Buoy")
    assert Pages::Save.call(draft.reload, attributes: { published: false }).ok?
    assert_includes entries_of(draft).pluck(:locale), "es"
    SiteSearch::Rebuild.new.call
    clear_enqueued_jobs

    assert Locales::Disable.call("es", actor: nil).ok?
    assert_enqueued_with(job: SiteSearch::ReindexJob)
    assert_includes entries_of(page).pluck(:locale), "es"

    perform_enqueued_jobs(only: SiteSearch::ReindexJob)

    assert_equal %w[de en], entries_of(page).pluck(:locale).sort
    assert_equal %w[de en], entries_of(draft).pluck(:locale).sort, "a record the build does not index loses the language too"
  end

  test "a language changed while the job builds enqueues the job again" do
    create_page(title: "Lighthouse")
    create_page(title: "Foghorn")
    clear_enqueued_jobs
    moved = ->(count) { site_settings(:default).update_columns(locales: [ { "code" => "en" }, { "code" => "de" } ]) if count == 1 } # version: none (another process's change of the languages, mid-build)

    backend = Wrapped.new(on_index: moved)
    with_singleton_override(SiteSearch::Backends, :current, -> { backend }) { SiteSearch::ReindexJob.perform_now("postgres") }

    assert state.ready?
    assert SiteSearch::IndexState.empty_or_stale?("postgres", site: SiteSetting.first)
    assert_enqueued_with(job: SiteSearch::ReindexJob, args: [ "postgres" ])
    job = enqueued_jobs.find { |each| each["job_class"] == "SiteSearch::ReindexJob" }
    assert job["scheduled_at"], "enqueued for later, once this run has let go of its limit"
  end

  test "a copy taken during the build keeps its documents" do
    first = create_page(title: "Lighthouse")
    later = create_page(title: "Foghorn", translations: { "en" => { title: "Foghorn", slug: "signal" } })
    publish_later = lambda do |count|
      next unless count == 1

      assert Pages::Save.call(later.reload, translations: { "en" => { title: "Beacon" } }).ok?
      publish_changes(later)
    end

    SiteSearch::Rebuild.new(backend: Wrapped.new(on_index: publish_later)).call

    assert_equal [ [ "Page", first.id ] ], found("lighthouse")
    assert_equal [ [ "Page", later.id ] ], found("beacon"), "the copy taken mid-build is found"
    assert_empty found("foghorn")
    assert_equal [ Publishing.current(later).id ], entries_of(later).distinct.pluck(:published_version_id)
  end

  test "an outside backend keeps a copy taken during the build and forgets the one it superseded" do
    first = create_page(title: "Lighthouse")
    later = create_page(title: "Foghorn")
    old = Publishing.current(later)

    with_fake do |fake|
      sent = 0
      # Another editor publishes the later page while the build sends the
      # first, and its SyncJob has already sent the new copy.
      publish_later = lambda do
        assert Pages::Save.call(later.reload, translations: { "en" => { title: "Beacon" } }).ok?
        publish_changes(later)
        fake.index(SiteSearch::Documents.for_record(later.reload, now: Time.current))
      end
      wrapped = Object.new
      wrapped.define_singleton_method(:index) do |documents|
        sent += 1
        publish_later.call if sent == 1
        fake.index(documents)
      end
      wrapped.define_singleton_method(:prune_record) { |**args| fake.prune_record(**args) }
      wrapped.define_singleton_method(:remove) { |**args| fake.remove(**args) }

      SiteSearch::Rebuild.new(name: "test/fake", backend: wrapped).call

      copies = fake.documents.values.select { |document| document.record_id == later.id && document.record_type == "Page" }.map(&:copy_id).uniq
      assert_equal [ Publishing.current(later).id ], copies
      assert_not_equal old.id, copies.first
      assert fake.documents.values.any? { |document| document.record_id == first.id }
    end
  end

  test "an outside backend's build forgets the documents of a record no longer kept and published" do
    with_fake do |fake|
      page = create_page(title: "Lighthouse")
      post = create_post(title: "Harbour")
      [ page, post ].each { |record| fake.index(SiteSearch::Documents.for_record(record.reload, now: Time.current)) }
      assert Pages::Save.call(page.reload, attributes: { published: false }).ok?
      assert Trash::Move.call(post.reload).ok?
      kept = create_page(title: "Foghorn")

      SiteSearch::Rebuild.new(name: "test/fake", backend: fake).call

      held = ->(record) { fake.documents.values.select { |document| document.record_type == record.class.polymorphic_name && document.record_id == record.id } }
      assert_empty held.(page), "an unpublished page's stale documents are gone"
      assert_empty held.(post), "a trashed post's stale documents are gone"
      assert_not_empty held.(kept)
    end
  end

  test "a second build while one holds the backend raises Busy and touches nothing" do
    create_page(title: "Lighthouse")

    holding_build_lock("postgres") do
      assert_raises(SiteSearch::Rebuild::Busy) { SiteSearch::Rebuild.new.call }
      assert_nil state
    end

    SiteSearch::Rebuild.new.call
    assert state.ready?
  end

  test "a build drops the languages switched off since the last one, and only those" do
    create_page(title: "Lighthouse")
    SiteSearch::Rebuild.new.call
    assert_equal %w[de en es], state.languages

    removed = []
    counting = Wrapped.new
    counting.define_singleton_method(:remove) { |**args| removed << args[:languages] }
    SiteSearch::Rebuild.new(backend: counting).call
    assert_empty removed, "nothing was switched off since the last build"

    assert Locales::Disable.call("es", actor: nil).ok?
    SiteSearch::Rebuild.new(backend: counting).call
    assert_equal [ [ "es" ] ], removed.uniq
    assert_equal %w[de en], state.reload.languages
  end

  test "a job for a backend the site no longer uses does nothing" do
    create_page(title: "Lighthouse")

    assert_nil SiteSearch::ReindexJob.perform_now("test/gone")

    assert_nil state("test/gone")
    assert_nil state
  end

  test "a database before the migration is left alone" do
    clear_enqueued_jobs

    with_singleton_override(SiteSearch::IndexState, :table_exists?, -> { false }) { SiteSearch::IndexCheckJob.perform_now }

    assert_no_enqueued_jobs
  end

  test "a stalled build is a building row over an hour old with no job running" do
    page = create_page(title: "Lighthouse")
    assert_raises(SiteSearch::Unavailable) { SiteSearch::Rebuild.new(backend: Wrapped.new(raise_on: page)).call }
    started = state.started_at

    assert_not state.stopped?(now: started + 59.minutes, job_running: false)
    assert_not state.stopped?(now: started + 2.hours, job_running: true)
    assert state.stopped?(now: started + 2.hours, job_running: false)

    SiteSearch::Rebuild.new.call
    assert_not state.reload.stopped?(now: started + 2.hours, job_running: false)
  end
end
