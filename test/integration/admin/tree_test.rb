require "test_helper"

class Admin::TreeTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
    @a = create_page(title: "Alpha")
    @b = create_page(title: "Beta")
    @child = create_page(title: "Child", parent: @a)
  end

  test "the pages home shows the tree with status and child counts" do
    get "/cs-studio"
    assert_select "turbo-frame#tree li[data-page-id='#{@a.id}']" do
      assert_select "[data-status='live']"
      assert_select "[data-child-count]", text: "1"
    end
  end

  test "moving a page reparents it and re-renders the tree" do
    patch "/cs-studio/tree", params: { page_id: @child.id, parent_id: @b.id, position: 0 }, as: :turbo_stream
    assert_response :success
    assert_equal @b, @child.reload.parent
    assert_includes response.body, %(<turbo-stream action="replace" target="tree">)
  end

  test "an invalid move re-renders the tree unchanged with an error" do
    patch "/cs-studio/tree", params: { page_id: @a.id, parent_id: @child.id, position: 0 }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_equal root_page, @a.reload.parent
    assert_includes response.body, "can't be moved under itself"
  end
end
