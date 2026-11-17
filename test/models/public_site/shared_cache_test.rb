require "test_helper"

class PublicSite::SharedCacheTest < ActiveSupport::TestCase
  test "unset or blank is 0, and a whole number of 0 or more is its seconds" do
    assert_equal 0, PublicSite::SharedCache.parse(nil)
    assert_equal 0, PublicSite::SharedCache.parse("  ")
    assert_equal 0, PublicSite::SharedCache.parse("0")
    assert_equal 60, PublicSite::SharedCache.parse(" 60 ")
    assert_equal 8, PublicSite::SharedCache.parse("08"), "a leading zero is not octal"
    assert_equal 60, PublicSite::SharedCache.read({ "PUBLIC_SHARED_CACHE_SECONDS" => "60" })
    assert_equal 0, PublicSite::SharedCache.read({})
  end

  test "anything else stops with a message that names the variable and not the value" do
    [ "-1", "1.5", "60s", "1e3", "sixty", "0x10", "+5" ].each do |value|
      error = assert_raises(PublicSite::SharedCache::Invalid, value) { PublicSite::SharedCache.parse(value) }
      assert_includes error.message, "PUBLIC_SHARED_CACHE_SECONDS"
      assert_not_includes error.message, value, value
    end
  end

  test "on? only above 0, and with gives a block its own value back" do
    PublicSite::SharedCache.with(0) { assert_not PublicSite::SharedCache.on? }
    PublicSite::SharedCache.with(60) { assert PublicSite::SharedCache.on? }
    assert_equal 0, PublicSite::SharedCache.seconds
  end
end
