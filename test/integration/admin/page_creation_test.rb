require "test_helper"

class Admin::PageCreationTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
    @a = create_page(title: "Alpha")
  end

  test "creating a page from just a title makes a draft child with an auto slug" do
    assert_difference "Page.count", 1 do
      post "/cs-studio/pages", params: { page: { title: "New", parent_id: @a.id } }
    end

    page = Page.last
    assert_equal @a, page.parent
    assert_not page.live?
    assert_equal "new", Mobility.with_locale(Locales.default) { page.slug }
    assert_redirected_to admin_page_path(page)
  end

  test "a blank title re-renders new with the error" do
    assert_no_difference "Page.count" do
      post "/cs-studio/pages", params: { page: { title: "", parent_id: @a.id } }
    end

    assert_response :unprocessable_entity
    assert_select "form"
  end
end
