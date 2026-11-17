require "test_helper"
require Rails.root.join("db/migrate/20261116140000_keep_version_publishers").to_s

# The migration marks the copies `CreatePublishedVersions` made of what was
# live when history was switched on: a first copy with no publisher taken
# before any copy a person published or any second copy. A first copy with
# no publisher taken later (a seed's, the console's) is the system's, and
# keeps no mark.
class KeepVersionPublishersMigrationTest < ActiveSupport::TestCase
  def mark = ActiveRecord::Migration.suppress_messages { KeepVersionPublishers.new.mark_first_copies }

  def kept(record) = Publishing::Version.of(record).order(:number).pluck(:kept_when_history_began)

  test "the first copies before any person's publish are marked, a later first copy with no publisher is not" do
    before = [ create_page(title: "Before"), create_post(title: "Before too") ]
    before.each { |record| Publishing::Version.of(record).update_all(created_by_id: nil) } # version: none (a test makes the migration's copies)
    person = as(users(:one)) { create_page(title: "A person's") }
    Publishing::Version.take!(person.reload, by: users(:one)) # version: none (a test takes a copy)
    seeded = create_page(title: "Seeded")
    Publishing::Version.of(seeded).update_all(created_by_id: nil) # version: none (a test makes a seed's copy)
    Publishing::Version.update_all(kept_when_history_began: false) # version: none (a test empties the column the migration fills)

    mark

    before.each { |record| assert_equal [ true ], kept(record), record.title }
    assert_equal [ false, false ], kept(person)
    assert_equal [ false ], kept(seeded)
  end
end
