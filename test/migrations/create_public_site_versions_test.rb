require "test_helper"
require Rails.root.join("db/migrate/20261005150000_create_public_site_versions").to_s

# The migration leaves exactly one version row, counting from 0, so a
# migrated database never depends on the first bump to create it. The table
# exists on the test database (without the row: it is built from
# `db/schema.rb`), so the test rolls the migration back inside its own
# transaction (Postgres DDL is transactional) and runs `up` again.
class CreatePublicSiteVersionsMigrationTest < ActiveSupport::TestCase
  setup do
    ActiveRecord::Migration.suppress_messages { CreatePublicSiteVersions.new.migrate(:down) }
    PublicSite::Version.reset_column_information
  end

  def migrate_up
    previous = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    CreatePublicSiteVersions.new.migrate(:up)
    PublicSite::Version.reset_column_information
  ensure
    ActiveRecord::Migration.verbose = previous
  end

  test "down drops the table" do
    assert_not ActiveRecord::Base.connection.table_exists?(:public_site_versions)
  end

  test "up creates the table with its one row, at 0, and the first bump counts from there" do
    migrate_up

    assert_equal [ [ PublicSite::Version::ROW_ID, 0 ] ], PublicSite::Version.pluck(:id, :counter)
    assert_equal 0, PublicSite::Version.current

    PublicSite.bump_version!

    assert_equal [ 1 ], PublicSite::Version.pluck(:counter)
  end
end
