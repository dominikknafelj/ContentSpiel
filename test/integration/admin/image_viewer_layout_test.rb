require "test_helper"

# The image viewer is drawn once by the admin layout, outside `#content`
# and every form, and empty: nothing of anyone's notes is in it until a
# thumbnail is pressed.
class Admin::ImageViewerLayoutTest < ActionDispatch::IntegrationTest
  setup { site_settings(:default).update!(setup_completed_at: Time.current) }

  test "a CS Studio screen draws the viewer once, empty" do
    sign_in_as(users(:one))
    get admin_root_path

    assert_response :success
    assert_select "dialog#image-viewer", 1
    assert_select "dialog#image-viewer img[src]", 0
    assert_select "#content dialog#image-viewer", 0
  end
end
