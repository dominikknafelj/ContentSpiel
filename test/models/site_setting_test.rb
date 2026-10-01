require "test_helper"

class SiteSettingTest < ActiveSupport::TestCase
  test "a second record cannot be created" do
    second = SiteSetting.new(title: "Second")

    assert_not second.valid?
    assert_includes second.errors[:base], "only one SiteSetting may exist"
  end

  test "instance creates the record on first access" do
    SiteSetting.delete_all

    assert_difference "SiteSetting.count", 1 do
      SiteSetting.instance
    end
  end

  test "instance returns the existing record on subsequent access" do
    assert_equal site_settings(:default), SiteSetting.instance
  end

  test "title is required" do
    setting = SiteSetting.instance
    setting.title = " "

    assert_not setting.valid?
    assert_includes setting.errors[:title], "can't be blank"
  end

  test "default_locale defaults to en" do
    assert_equal "en", SiteSetting.instance.default_locale
  end

  # PagesController and config/sitemap.rb both trust this value as one of the
  # enabled locales without checking again -- an admin typing anything else in
  # here would otherwise make every page's cached path unreachable at the
  # site's own root.
  test "default_locale must be one of the configured locales" do
    setting = SiteSetting.instance
    setting.default_locale = "fr"

    assert_not setting.valid?
    assert_includes setting.errors[:default_locale], "must be one of the enabled languages"
  end

  test "default_locale accepts any of the site's own enabled locales" do
    setting = SiteSetting.instance

    setting.locale_codes.each do |locale|
      setting.default_locale = locale
      assert setting.valid?, "expected #{locale} to be a valid default_locale"
    end
  end

  test "locales must be supported, unique and include the default" do
    setting = site_settings(:default)
    setting.locales = [ { "code" => "xx" } ]
    assert_not setting.valid?
    assert_includes setting.errors[:locales], "contains an unsupported language: xx"

    setting.locales = [ { "code" => "en" }, { "code" => "en" } ]
    assert_not setting.valid?
    assert_includes setting.errors[:locales], "lists a language twice"

    setting.locales = [ { "code" => "en" } ]
    setting.default_locale = "de"
    assert_not setting.valid?
    assert_includes setting.errors[:default_locale], "must be one of the enabled languages"

    setting.locales = [ { "code" => "en", "fallbacks" => [ "fr" ] } ]
    setting.default_locale = "en"
    assert_not setting.valid?
    assert_includes setting.errors[:locales], "en falls back to a language that isn't enabled: fr"

    setting.locales = []
    assert_not setting.valid?
    assert_includes setting.errors[:locales], "must enable at least one language"
  end

  # Final fix wave (E): a link the footer would refuse to render (no
  # scheme, or a scheme other than http/https/mailto) is a validation error
  # where it's typed, instead of saving fine and silently never appearing.
  test "social links must start with https://, http:// or mailto:" do
    setting = SiteSetting.instance

    setting.social_link_rows = [ { name: "GitHub", url: "github.com/dana" }, { name: "Evil", url: "javascript:alert(1)" } ]
    assert_not setting.valid?
    assert_includes setting.errors[:social_links], "GitHub must start with https://, http:// or mailto:"
    assert_includes setting.errors[:social_links], "Evil must start with https://, http:// or mailto:"

    setting.social_link_rows = [ { name: "GitHub", url: "https://github.com/dana" }, { name: "Mail", url: "MAILTO:dana@example.com" } ]
    assert setting.valid?, setting.errors.full_messages.to_sentence
  end

  # Trash spec §3.1: 0 means "never" (the sweep job skips it), so this is a
  # non-negative check, not `greater_than: 0`.
  test "trash retention defaults to 30 days and can't be negative" do
    site = site_settings(:default)
    assert_equal 30, SiteSetting.new(title: "x").trash_retention_days
    site.trash_retention_days = -1
    assert_not site.valid?
    assert_includes site.errors[:trash_retention_days], "must be greater than or equal to 0"
    site.trash_retention_days = 0
    assert site.valid?
  end

  # Dashboard spec §5: the zone every CS Studio and MCP time is shown and
  # parsed in. Accepts a Rails zone name ("Berlin") or an IANA identifier
  # ("Europe/Berlin") -- `ActiveSupport::TimeZone[]` resolves both.
  test "time zone defaults to UTC and must be a known zone" do
    assert_equal "UTC", SiteSetting.new(title: "x").time_zone
    site = site_settings(:default)
    site.time_zone = "Mars/Olympus"
    assert_not site.valid?
    assert_includes site.errors[:time_zone], "isn't a known time zone"
    site.time_zone = "Berlin"
    assert site.valid?
    site.time_zone = "Europe/Berlin"
    assert site.valid?
  end
end
