require "test_helper"

# The two halves of "the index follows the copies" (spec §5.4, §6.1, §12):
# `SiteSearch::Indexing` is the one caller of a backend's `index` and
# `remove`, so every event that moves a copy reaches the backend in use the
# same way, inline or after the commit; and `SiteSearch::Postgres` is the
# one writer of `search_entries`, a derived table nobody writes by hand.
# Read in `app/` and `lib/`, comment lines skipped.
class SiteSearchGuardsTest < ActiveSupport::TestCase
  # path => why it may ask a backend to index or remove.
  INDEXERS = {
    "app/models/site_search/indexing.rb" => "the entry point, for the built-in in the caller's transaction",
    "app/jobs/site_search/sync_job.rb" => "the job Indexing enqueues for an outside backend after the commit"
  }.freeze

  # An index or a remove asked of a backend: a receiver named like one, or the
  # registry's chosen one.
  ASKS = /\b(?:backend|Backends\.current)\.(?:index|remove)\b/

  WRITES = /\.(?:update_all|update_columns|update_column|update!?|upsert|upsert_all|insert_all!?|insert!?|create!?|delete_all|delete_by|delete|destroy_all|destroy_by|destroy!?|touch_all|touch)\b/

  WRITERS = { "app/models/site_search/postgres.rb" => "the built-in backend, the table's one writer" }.freeze

  def sources = %w[app lib].flat_map { |root| Rails.root.glob("#{root}/**/*.{rb,rake,erb}") }.to_h { |path| [ path.to_s.delete_prefix("#{Rails.root}/"), path.read ] }

  def code_lines(source) = source.lines.reject { |line| line.strip.start_with?("#") }

  test "only SiteSearch::Indexing asks a backend to index or remove" do
    askers = sources.select { |_path, source| code_lines(source).any? { |line| line.match?(ASKS) } }.keys

    assert_equal INDEXERS.keys.sort, askers.sort,
      "a backend is asked to index or remove through SiteSearch::Indexing (spec §5.4); a new asker is named in INDEXERS with its reason"
    assert_includes Rails.root.join("app/models/site_search/indexing.rb").read, "SyncJob", "the entry point names the job it enqueues"
  end

  test "the asking pattern catches a backend's index and remove and lets the rest through" do
    [ "backend.index(documents)", "SiteSearch::Backends.current.remove(record_type: \"Page\", record_id: 1)", "Backends.current.index([])" ].each { |line| assert_match ASKS, line }
    [ "text.index(\"a\")", "list.remove(1)", "Entry.where(id: 1)", "Backends.current_name" ].each { |line| assert_no_match ASKS, line }
  end

  test "only SiteSearch::Postgres writes search_entries" do
    writers = sources.select do |path, source|
      own = path.start_with?("app/models/site_search/", "app/queries/site_search/", "app/jobs/site_search/")
      code_lines(source).any? do |line|
        line.match?(/(?:\bSiteSearch::Entry\b|\bsearch_entries\b)[^\n]*#{WRITES}/) || (own && line.match?(/(?<![:\w])Entry\b[^\n]*#{WRITES}/))
      end
    end.keys

    assert_equal WRITERS.keys, writers, "search_entries is derived: written by SiteSearch::Postgres alone (spec §6.1)"
  end
end
