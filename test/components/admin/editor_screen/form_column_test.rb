require "test_helper"

# The editors' form column (layout points spec, decisions 1-3): one class for
# the 760px column, and a second one on a translation tab, whose pairs need two
# columns (Claude Design's O3).
class Admin::EditorScreen::FormColumnTest < ActiveSupport::TestCase
  include ContentHelper

  test "the default language's column is the 760px one, any other language's the pair's" do
    with_locales(%w[en de], default: "en")

    assert_equal "admin-form-column", Admin::EditorScreen::FormColumn.classes("en")
    assert_equal "admin-form-column admin-form-column--pair", Admin::EditorScreen::FormColumn.classes("de")
    assert_equal "admin-form-column admin-form-column--pair", Admin::EditorScreen::FormColumn.classes(:de)
  end
end
