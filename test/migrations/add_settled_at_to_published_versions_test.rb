require "test_helper"
require Rails.root.join("db/migrate/20261011122000_add_settled_at_to_published_versions").to_s

# The migration marks the copies that show when it runs, in SQL and with no
# application class. What it marks must be what the application would have:
# a copy that shows is settled, at its own time; one that does not show yet
# is left for `Publishing::Version.settle!`.
class AddSettledAtToPublishedVersionsMigrationTest < ActiveSupport::TestCase
  def marks(record) = Publishing::Version.of(record).order(:number).map { |copy| copy.settled_at && copy.settled_at == copy.live_at }

  test "the mark settles every copy that shows, at its own time, and leaves a pending change, a scheduled record's copy and an unpublished record's copy" do
    # An hour ago: the SQL's NOW() is the start of the test's transaction.
    live, post, scheduled, unpublished = travel_to(1.hour.ago) do
      root_page
      live = create_page(title: "Live")
      assert Pages::Save.call(live, translations: { "en" => { subtitle: "Later" } }).ok?
      publish_changes(live, at: 1.day.from_now)
      scheduled = create_page(title: "Scheduled", published: false)
      assert Pages::Save.call(scheduled, attributes: { published_at: 1.day.from_now }).ok?
      unpublished = create_page(title: "Was live")
      assert Pages::Save.call(unpublished, attributes: { published: false }).ok?
      [ live, create_post(title: "Hello"), scheduled, unpublished ]
    end
    Publishing::Version.update_all(settled_at: nil) # version: none (a test empties the column the migration fills)

    ActiveRecord::Migration.suppress_messages { AddSettledAtToPublishedVersions.new.mark_shown }

    assert_equal [ true, nil ], marks(live), "the copy in force, and not the change with a time"
    assert_equal [ true ], marks(post)
    assert_equal [ nil ], marks(scheduled), "due when the page goes live"
    assert_equal [ nil ], marks(unpublished), "never due: the first refresh marks it"

    travel_to 2.days.from_now do
      PublicSite::Paths.refresh
      assert_empty Publishing::Version.where(settled_at: nil), "and the application settles the rest as their time comes"
    end
  end
end
