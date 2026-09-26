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
  # three configured locales without checking again -- an admin typing
  # anything else in here would otherwise make every page's cached path
  # unreachable at the site's own root.
  test "default_locale must be one of the configured locales" do
    setting = SiteSetting.instance
    setting.default_locale = "fr"

    assert_not setting.valid?
    assert_includes setting.errors[:default_locale], "is not included in the list"
  end

  test "default_locale accepts any configured locale" do
    setting = SiteSetting.instance

    I18n.available_locales.each do |locale|
      setting.default_locale = locale.to_s
      assert setting.valid?, "expected #{locale} to be a valid default_locale"
    end
  end
end
