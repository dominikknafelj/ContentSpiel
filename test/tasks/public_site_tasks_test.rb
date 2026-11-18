require "test_helper"
require "rake"

# `public_site:after_restore` (`PublicSite.after_restore!`): after a restored
# backup the counter is above every value it held before, and the render
# cache, which a restore leaves holding renders made under a value the
# restored content may reuse, is empty.
class PublicSiteTasksTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("public_site:after_restore")
    @cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = @cache }

  test "after_restore puts the version above every value the counter held, and empties the cache" do
    7.times { PublicSite::Version.bump! }
    before = PublicSite::Version.current
    Rails.cache.write("probe", 1)
    now = Time.utc(2026, 11, 18, 12, 0, 0)

    out = travel_to(now) do
      Rake::Task["public_site:after_restore"].reenable
      capture_io { Rake::Task["public_site:after_restore"].invoke }.first
    end

    counter = PublicSite::Version.current
    assert_operator counter, :>, before
    assert_operator counter, :>, now.to_i * 1_000_000 - 1
    assert_nil Rails.cache.read("probe")
    assert_includes out, "Public content version: #{counter}"
    assert_includes out, "Cache cleared. If a CDN caches the site's pages, purge it now."
  end
end
