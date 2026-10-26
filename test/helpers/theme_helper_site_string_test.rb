require "test_helper"

class ThemeHelperSiteStringTest < ActionView::TestCase
  include ThemeHelper
  include LogCapture

  teardown { ThemeHelper.instance_variable_set(:@unknown_site_strings, nil) }

  test "site_string answers the site's words in English" do
    assert_equal "In this section", site_string(:in_this_section)
    assert_equal "Tagged", site_string("tagged")
  end

  test "a key that is not the site's raises where a theme is written, and names the keys" do
    error = assert_raises(ArgumentError) { site_string(:in_this_sektion) }
    assert_includes error.message, ":in_this_section"
    assert_includes error.message, ":tagged"
  end

  test "in production an unknown key is no word and one log line" do
    ThemeHelper.instance_variable_set(:@unknown_site_strings, nil)
    with_singleton_override(Rails, :env, -> { ActiveSupport::EnvironmentInquirer.new("production") }) do
      log = capture_log do
        assert_equal [ "", "" ], [ site_string(:nope), site_string(:nope) ]
      end
      assert_equal 1, log.scan("ThemeHelper#site_string has no :nope").size
      assert_no_match(/ranslation missing/, log)
    end
  end
end
