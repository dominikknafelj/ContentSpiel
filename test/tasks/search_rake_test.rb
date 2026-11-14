require "test_helper"
require "rake"

# `bin/rails search:reindex` (spec §6.5): the build `SiteSearch::ReindexJob`
# runs, in the foreground, for by-hand use.
class SearchRakeTest < ActiveSupport::TestCase
  include SearchBuildLock

  setup { Rails.application.load_tasks unless Rake::Task.task_defined?("search:reindex") }

  def run_task
    Rake::Task["search:reindex"].reenable
    capture_io { Rake::Task["search:reindex"].invoke }.first
  end

  test "search:reindex builds the index in the foreground" do
    page = create_page(title: "Lighthouse")
    create_page(title: "Buoy", published: false)
    SiteSearch::Entry.delete_all

    published = Page.kept.where.not(published_at: nil).count

    output = run_task

    assert_match "search:reindex: #{published} record(s) indexed by Postgres (postgres)", output
    assert SiteSearch::IndexState.for("postgres").ready?
    assert_equal Locales.enabled.sort, SiteSearch::Entry.where(record_type: "Page", record_id: page.id).pluck(:locale).sort
  end

  test "search:reindex builds nothing while another build runs, and says so" do
    create_page(title: "Lighthouse")
    Rake::Task["search:reindex"].reenable

    holding_build_lock("postgres") do
      error = assert_raises(SystemExit) { capture_io { Rake::Task["search:reindex"].invoke } }
      assert_not error.success?
    end

    assert_nil SiteSearch::IndexState.for("postgres")
  end
end
