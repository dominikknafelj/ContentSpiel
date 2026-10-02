require "test_helper"
require Rails.root.join("db/migrate/20261002110000_translate_site_title_and_tagline").to_s

# Translation helpers Task 5's migration: `site_settings.title`/`tagline`
# go from plain strings to Mobility jsonb, each string moving into the
# site's default locale. The test database already ran it (same setup as
# test/migrations/rename_media_asset_type_test.rb), so each test migrates
# down first to stand up the "before" state, then exercises the real `up`.
# Postgres DDL is transactional, so the test's own rollback puts the
# columns back. Everything is read with raw SQL: `SiteSetting`'s cached
# column types are the jsonb ones throughout.
class TranslateSiteTitleAndTaglineMigrationTest < ActiveSupport::TestCase
  teardown { SiteSetting.reset_column_information }

  def migrate(direction) = ActiveRecord::Migration.suppress_messages { TranslateSiteTitleAndTagline.new.migrate(direction) }

  def row = ActiveRecord::Base.connection.select_one("SELECT title, tagline FROM site_settings LIMIT 1")

  def column_type(name) = ActiveRecord::Base.connection.select_value(<<~SQL)
    SELECT data_type FROM information_schema.columns WHERE table_name = 'site_settings' AND column_name = '#{name}'
  SQL

  def set_strings(title:, tagline:, default_locale:)
    ActiveRecord::Base.connection.exec_update(
      "UPDATE site_settings SET title = $1, tagline = $2, default_locale = $3", "SQL",
      [ title, tagline, default_locale ]
    )
  end

  test "up moves each string into the site's default locale, and down restores it" do
    migrate(:down)
    assert_equal "character varying", column_type("title")
    set_strings(title: "Danas Notizen", tagline: "Was ich gelernt habe", default_locale: "de")

    migrate(:up)

    assert_equal "jsonb", column_type("title")
    assert_equal "jsonb", column_type("tagline")
    assert_equal({ "de" => "Danas Notizen" }, JSON.parse(row["title"]))
    assert_equal({ "de" => "Was ich gelernt habe" }, JSON.parse(row["tagline"]))

    migrate(:down)

    assert_equal "character varying", column_type("title")
    assert_equal({ "title" => "Danas Notizen", "tagline" => "Was ich gelernt habe" }, row)
  end

  test "a blank tagline becomes an empty translation, and goes back to NULL" do
    migrate(:down)
    set_strings(title: "Test Site", tagline: nil, default_locale: "en")

    migrate(:up)
    assert_equal({}, JSON.parse(row["tagline"]))

    migrate(:down)
    assert_nil row["tagline"]
  end

  test "down keeps a title that exists only in another language rather than losing it" do
    ActiveRecord::Base.connection.execute(%(UPDATE site_settings SET title = '{"de": "Nur Deutsch"}'::jsonb, default_locale = 'en'))

    migrate(:down)

    assert_equal "Nur Deutsch", row["title"]
  end
end
