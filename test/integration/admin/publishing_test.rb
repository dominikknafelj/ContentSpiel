require "test_helper"

class Admin::PublishingTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "One")
    assert Pages::Save.call(@page, translations: { "en" => { title: "Two" } }).ok?
    sign_in_as users(:one)
  end

  test "publish takes a copy and goes back to the editor saying so" do
    post admin_publishing_publish_path(kind: "page", id: @page.id)

    assert_redirected_to admin_page_path(@page)
    assert_equal 2, Publishing.current(@page).number
    follow_redirect!
    assert_includes response.body, "Changes published"
  end

  test "a post is published the same way and returns to its own editor" do
    record = create_post(title: "Post")

    post admin_publishing_publish_path(kind: "post", id: record.id)

    assert_redirected_to admin_post_path(record)
    assert_equal 2, Publishing.current(record).number
  end

  test "a trashed record and one that never existed are not found, and nothing is published" do
    assert Trash::Move.call(@page).ok?

    post admin_publishing_publish_path(kind: "page", id: @page.id)
    assert_response :not_found
    post admin_publishing_publish_path(kind: "page", id: 0)
    assert_response :not_found
    assert_equal 1, Publishing::Version.of(@page).count
  end

  test "a draft goes back to the editor with the reason, and nothing is published" do
    draft = create_page(title: "Draft", published: false)

    post admin_publishing_publish_path(kind: "page", id: draft.id)

    assert_redirected_to admin_page_path(draft)
    assert_empty Publishing::Version.of(draft)
  end
end
