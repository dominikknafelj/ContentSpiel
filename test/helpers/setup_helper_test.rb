require "test_helper"

class SetupHelperTest < ActionView::TestCase
  include SetupHelper

  test "setup_progress is the step's place in ten, as a fraction rounded to two places" do
    assert_equal({ number: 1, total: 10, fraction: 0.1 }, setup_progress("token"))
    assert_equal({ number: 4, total: 10, fraction: 0.4 }, setup_progress("passkey"))
    assert_equal({ number: 6, total: 10, fraction: 0.6 }, setup_progress("mail"))
    assert_equal({ number: 10, total: 10, fraction: 1.0 }, setup_progress("review"))
  end

  test "a step is done when it comes before the current one" do
    assert setup_step_done?("token", "admin")
    assert_not setup_step_done?("admin", "admin")
    assert_not setup_step_done?("site", "admin")
  end
end
