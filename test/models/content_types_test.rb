require "test_helper"

class ContentTypesTest < ActiveSupport::TestCase
  test "switched_on is the declared types the site names, in registration order" do
    site = SiteSetting.new(content_types: [ "now_update", "blog", "gone/type" ])

    assert_equal %w[blog now_update], ContentTypes.switched_on(site: site).map(&:name)
    assert_equal %w[blog now_update], ContentTypes.switched_on_names(site: site)
  end

  test "switched_on? is false for an undeclared name and a declared one switched off" do
    site = SiteSetting.new(content_types: [ "blog", "gone/type" ])

    assert ContentTypes.switched_on?("blog", site: site)
    assert ContentTypes.switched_on?(:blog, site: site)
    assert_not ContentTypes.switched_on?("gone/type", site: site)
    assert_not ContentTypes.switched_on?("now_update", site: site)
  end

  test "default is the first switched-on type, else the first declared" do
    switch_on_content_types("now_update", "resume_entry")
    assert_equal "resume_entry", ContentTypes.default.name

    Current.site = SiteSetting.new(content_types: [ "gone/type" ])
    assert_equal ContentTypes.all.first, ContentTypes.default
  end
end
