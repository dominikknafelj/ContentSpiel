require "test_helper"
require Rails.root.join("db/migrate/20261110090000_default_site_locales_to_english").to_s

# Only the column's default changes: a site that exists keeps the languages
# it has, and the migration goes back to the three it replaced. Run inside
# the test's own transaction (Postgres DDL is transactional).
class DefaultSiteLocalesToEnglishMigrationTest < ActiveSupport::TestCase
  THREE = [ { "code" => "en" }, { "code" => "de" }, { "code" => "es" } ].freeze

  def column_default
    SiteSetting.reset_column_information
    SiteSetting.column_defaults["locales"]
  end

  test "up changes the default to English alone and leaves an existing site's languages as they are" do
    ActiveRecord::Migration.suppress_messages { DefaultSiteLocalesToEnglish.new.migrate(:down) }
    assert_equal THREE, column_default
    site_settings(:default).update_columns(locales: [ { "code" => "en" }, { "code" => "fr", "fallbacks" => [ "en" ] } ])

    ActiveRecord::Migration.suppress_messages { DefaultSiteLocalesToEnglish.new.migrate(:up) }

    assert_equal [ { "code" => "en" } ], column_default
    assert_equal [ { "code" => "en" }, { "code" => "fr", "fallbacks" => [ "en" ] } ], site_settings(:default).reload.locales
  ensure
    SiteSetting.reset_column_information
  end
end
