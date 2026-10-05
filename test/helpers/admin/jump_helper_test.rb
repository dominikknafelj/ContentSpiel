require "test_helper"

class Admin::JumpHelperTest < ActionView::TestCase
  include Admin::JumpHelper

  # The view's own `admin_url_options` (the editing locale), stubbed.
  def admin_url_options = { locale: "de" }

  test "a route on the list resolves with its arguments, params and the request's URL options" do
    page = create_page(title: "Linked")

    assert_equal "/cs-studio/pages/#{page.id}?locale=de", jump_row_path([ :admin_page_path, [ page ], {} ])
    assert_equal "/cs-studio/settings?locale=de#ai", jump_row_path([ :admin_settings_path, [], { anchor: "ai" } ])
  end

  test "a name that is not on the list is refused, never sent to public_send" do
    error = assert_raises(ArgumentError) { jump_row_path([ :destroy_all, [], {} ]) }
    assert_match(/not a route/, error.message)
  end
end
