require "test_helper"

class SiteSettingTest < ActiveSupport::TestCase
  test "a second record cannot be created" do
    SiteSetting.create!(title: "First")
    second = SiteSetting.new(title: "Second")

    assert_not second.valid?
    assert_includes second.errors[:base], "only one SiteSetting may exist"
  end

  test "instance creates the record on first access" do
    assert_difference "SiteSetting.count", 1 do
      SiteSetting.instance
    end
  end

  test "instance returns the existing record on subsequent access" do
    existing = SiteSetting.create!(title: "Existing")

    assert_equal existing, SiteSetting.instance
  end
end
