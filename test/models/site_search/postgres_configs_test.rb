require "test_helper"

# Every language the CMS can serve is parsed with a text search
# configuration Postgres ships (spec §6.2): one the database does not have
# would raise on the first publish in that language.
class SiteSearch::PostgresConfigsTest < ActiveSupport::TestCase
  test "every code of SUPPORTED_LOCALES maps to a configuration pg_ts_config has" do
    assert_equal SUPPORTED_LOCALES.keys.sort, SiteSearch::Postgres::CONFIGS.keys.sort

    shipped = ActiveRecord::Base.connection.select_values("SELECT cfgname FROM pg_ts_config")
    SiteSearch::Postgres::CONFIGS.each do |code, config|
      assert_includes shipped, config, code
    end
  end

  test "a language Postgres has no stemmer for is simple, and so is a code no one supports" do
    assert_equal "german", SiteSearch::Postgres.config_for("de")
    assert_equal "simple", SiteSearch::Postgres.config_for("ja")
    assert_equal "simple", SiteSearch::Postgres.config_for("xx")
    assert_equal %w[ja ko th zh], SiteSearch::Postgres::LIMITED
    SiteSearch::Postgres::LIMITED.each { |code| assert_equal "simple", SiteSearch::Postgres.config_for(code), code }
  end
end
