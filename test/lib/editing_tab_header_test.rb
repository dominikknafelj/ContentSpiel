require "test_helper"

# Every write of an editor carries the tab's id (`X-Notes-Tab`, see
# `app/javascript/editing/requests.js`), or the server cannot say whose echo a
# signal is and the tab that wrote fetches what it has just drawn. The Turbo
# forms get it from the document listener there; the hand-built `fetch`es
# add it themselves. The first two are exercised in the browser
# (`test/system/admin/editing_live_test.rb`: "my own save…", "my own reorder
# and my own Turbo form…"); the page tree's move has no such test, so its
# source is held here.
class EditingTabHeaderTest < ActiveSupport::TestCase
  HAND_BUILT = %w[
    app/javascript/controllers/admin/saving/autosave_controller.js
    app/javascript/controllers/admin/editor/blocks_controller.js
    app/javascript/controllers/admin/pages/tree_controller.js
  ].freeze

  test "each hand-built write of an editor sends the tab header" do
    HAND_BUILT.each do |path|
      source = Rails.root.join(path).read
      assert_includes source, "[TAB_HEADER]: TAB", "#{path} sends a write without the tab header"
    end
  end

  test "Turbo's own requests get the header from one listener" do
    source = Rails.root.join("app/javascript/editing/requests.js").read
    assert_match(/turbo:before-fetch-request.*TAB_HEADER\] = TAB/m, source)
  end
end
