require "test_helper"

class Admin::JumpControllerTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @post = create_post(title: "Jumpmatch post")
  end

  test "signed out redirects to sign-in" do
    get admin_jump_path(q: "jump")
    assert_redirected_to admin_sign_in_path
  end

  test "a matching post is a link, in a bare fragment without the layout" do
    sign_in_as users(:one)
    get admin_jump_path(q: "jumpmatch")
    assert_response :success
    assert_select "turbo-frame#jump-results a[href=?]", admin_post_path(@post), text: /Jumpmatch post/
    assert_select "nav[aria-label=Modules]", count: 0
  end

  test "a percent sign is literal text and finds no post" do
    sign_in_as users(:one)
    get admin_jump_path(q: "%")
    assert_response :success
    assert_select "a[href=?]", admin_post_path(@post), count: 0
    assert_select "p", text: /No results for/
  end

  test "an overlong or non-string query is a short search, not an error" do
    sign_in_as users(:one)
    get admin_jump_path(q: "a" * 500)
    assert_response :success
    get "#{admin_jump_path}?q[]=x"
    assert_response :success
  end

  test "a title containing markup is escaped" do
    create_post(title: "<script>alert(1)</script>")
    sign_in_as users(:one)
    get admin_jump_path(q: "alert")
    assert_response :success
    assert_not_includes response.body, "<script>alert(1)</script>"
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
  end

  test "an empty query lists modules and actions" do
    sign_in_as users(:one)
    get admin_jump_path
    assert_select "h3", text: "Settings"
    assert_select "h3", text: "Actions"
  end

  test "a user with no grants sees only what they can read" do
    nobody = User.create!(email_address: "nogrants@example.com", password: "a long enough password")
    sign_in_as nobody
    get admin_jump_path(q: "jumpmatch")
    assert_response :success
    assert_select "a[href=?]", admin_post_path(@post), count: 0
  end
end
