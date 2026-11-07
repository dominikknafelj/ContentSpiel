require "test_helper"

# `?review=publish` (the dashboard's "Review and publish…") opens the editor's
# Publish changes dialog, from a GET only.
class Admin::ReviewPublishTest < ActionDispatch::IntegrationTest
  OPEN = "[data-admin--ui--dialog-open-on-load]".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @live = create_page(title: "Pricing")
    assert Pages::Save.call(@live, translations: { "en" => { title: "Pricing, edited" } }).ok?
    sign_in_as users(:one)
  end

  test "a live page with changes opens Publish changes on load from review=publish" do
    get admin_page_path(@live, review: "publish")

    assert_response :success
    assert_select "dialog#publish-changes-page-#{@live.id}#{OPEN}", 1
    get admin_page_path(@live)
    assert_select "dialog#publish-changes-page-#{@live.id}", 1
    assert_select OPEN, 0
  end

  test "review=publish on a draft, on a clean live page, or for a viewer without publish opens nothing" do
    draft = create_page(title: "Draft", published: false)
    clean = create_page(title: "Clean")

    get admin_page_path(draft, review: "publish")
    assert_response :success
    assert_select OPEN, 0
    get admin_page_path(clean, review: "publish")
    assert_response :success
    assert_select OPEN, 0

    sign_in_as users(:reader)
    get admin_page_path(@live, review: "publish")
    assert_response :success
    assert_select OPEN, 0
  end

  # The answer streams the publishing chip and no header, so this holds that
  # no answer opens the dialog; the GET-only guard on the header itself is
  # held by `header_component_test.rb` ("review=publish opens Publish
  # changes from a GET and not from a PATCH").
  test "a save's answer, review=publish or not, carries no dialog that opens on load" do
    record = create_post(title: "Post")
    assert Posts::Save.call(record, translations: { "en" => { title: "Post, edited" } }).ok?

    get admin_post_path(record, review: "publish")
    assert_select "dialog#publish-changes-post-#{record.id}#{OPEN}", 1

    [ {}, { review: "publish" } ].each do |extra|
      patch "/cs-studio/posts/#{record.id}", params: { base_updated_at: record.reload.updated_at.iso8601(6), post: { excerpt: "Typed" } }.merge(extra), as: :turbo_stream
      assert_response :success
      assert_includes response.body, "publishing-chip"
      assert_not_includes response.body, "data-admin--ui--dialog-open-on-load"
    end
  end
end
