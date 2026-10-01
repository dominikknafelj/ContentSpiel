require "test_helper"

# The dashboard as CS Studio's start page (dashboard spec §3-§4, Task 2):
# the admin root now renders the dashboard shell, not the pages list, and
# sign-in lands there. The pages list itself moves to /pages -- the sidebar
# still lists it, just no longer first, and no longer at the admin root.
class Admin::DashboardTest < ActionDispatch::IntegrationTest
  test "the admin root is the dashboard and sign-in lands there" do
    post admin_sign_in_path, params: { email_address: users(:one).email_address, password: "password" }
    assert_redirected_to admin_root_url
    follow_redirect!
    assert_select "h1", "Dashboard"
  end

  test "the pages list lives at /pages and the sidebar lists Dashboard first" do
    sign_in_as users(:one)
    get admin_pages_path
    assert_response :ok
    assert_select "nav[aria-label='Modules'] a", text: "Pages"
    assert_equal "Dashboard", css_select("nav[aria-label='Modules'] a").first.text.strip
  end

  # users(:editor_branch) is a member of the "Branch editors" group, which
  # (fixtures/access_control/grants.yml) holds no grants at all -- the one
  # fixture user who can read nothing. The dashboard opens for them anyway
  # (its MODULES entry has `permission: nil`), each of its own lists simply
  # coming back empty through the same read scopes every other list uses.
  test "a user who can read nothing still gets the dashboard" do
    sign_in_as users(:editor_branch)
    get admin_root_path
    assert_response :ok
    assert_select "h1", "Dashboard"
  end
end
