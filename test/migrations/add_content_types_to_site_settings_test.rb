require "test_helper"
require Rails.root.join("db/migrate/20261116090000_add_content_types_to_site_settings").to_s

# Run inside the test's own transaction (Postgres DDL is transactional).
class AddContentTypesToSiteSettingsMigrationTest < ActiveSupport::TestCase
  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { AddContentTypesToSiteSettings.new.migrate(direction) }
    SiteSetting.reset_column_information
  end

  test "an existing row gets every built-in type and a new row Blog alone" do
    migrate(:down)
    migrate(:up)

    assert_equal %w[blog resume_entry now_update], site_settings(:default).reload.content_types

    SiteSetting.delete_all
    SiteSetting.connection.execute("INSERT INTO site_settings (created_at, updated_at) VALUES (now(), now())") # sql: a row as a plain insert makes it
    assert_equal [ "blog" ], SiteSetting.first.content_types
  ensure
    SiteSetting.reset_column_information
  end
end
