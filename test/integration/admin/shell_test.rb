require "test_helper"

class Admin::ShellTest < ActionDispatch::IntegrationTest
  setup { site_settings(:default).update!(setup_completed_at: Time.current) }

  test "the admin lives under ADMIN_PATH and requires sign-in" do
    assert_equal "cs-studio", ContentSpiel::ADMIN_PATH
    get "/cs-studio"
    assert_redirected_to "/cs-studio/sign-in"
  end

  test "signing in lands in CS Studio with the modules column" do
    post "/cs-studio/sign-in", params: { email_address: users(:one).email_address, password: "password" }
    assert_redirected_to "/cs-studio"
    follow_redirect!
    assert_select "nav[aria-label='Modules'] a", text: "Pages"
    assert_select "nav[aria-label='Modules'] a", text: "Posts"
    assert_select "nav[aria-label='Modules'] a", text: "Tags"
    assert_select "nav[aria-label='Modules'] a[href='/avo/resources/users']", text: /Users/
  end

  test "the old public sign-in routes are gone" do
    get "/session/new"
    assert_response :not_found
  end

  test "a root child page can't take the admin path as its slug" do
    page = Page.new(parent: root_page, title: "Studio", slug: "cs-studio")
    assert_not page.valid?
    assert page.errors.full_messages.any? { |message| message.include?("reserved for the admin") }
  end

  test "an unknown locale param falls back to the default" do
    sign_in_as(users(:one))
    get "/cs-studio", params: { locale: "xx" }
    assert_response :success
    assert_select "[data-admin-locale='#{Locales.default}']"
  end
end
