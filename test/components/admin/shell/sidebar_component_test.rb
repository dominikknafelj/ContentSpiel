require "test_helper"

class Admin::Shell::SidebarComponentTest < ViewComponent::TestCase
  def modules(*labels) = Admin::BaseController::MODULES.select { |entry| labels.include?(entry[:label]) }

  def render_sidebar(labels:, user: users(:one), trash_count: 0)
    with_request_url "/cs-studio" do
      render_inline(Admin::Shell::SidebarComponent.new(modules: modules(*labels), user: user,
        current_path: "/cs-studio/posts", url_options: {}, trash_count: trash_count))
    end
  end

  test "modules are grouped under Content, People and System, in the design's order" do
    render_sidebar(labels: Admin::BaseController::MODULES.map { |entry| entry[:label] })
    assert_equal %w[Content People System], page.all("nav[aria-label='Modules'] h2").map(&:text)
    content = page.all("nav[aria-label='Modules'] section")[0].all("a").map(&:text).map(&:strip)
    assert_equal [ "Dashboard", "Pages", "Posts", "Media", "Translations", "Tags", "Mind graph", "Trash" ], content
  end

  test "a group with no visible module disappears, heading and all" do
    render_sidebar(labels: [ "Dashboard", "AI assistant" ])
    assert_equal %w[Content System], page.all("nav[aria-label='Modules'] h2").map(&:text)
    assert_no_text "People"
  end

  test "the current module is marked" do
    render_sidebar(labels: %w[Dashboard Posts])
    assert_selector "a[aria-current=page]", text: "Posts"
    assert_no_selector "a[aria-current=page]", text: "Dashboard"
  end

  test "Dashboard is current only on an exact match" do
    with_request_url "/cs-studio" do
      render_inline(Admin::Shell::SidebarComponent.new(modules: modules("Dashboard", "Posts"), user: users(:one),
        current_path: "/cs-studio", url_options: {}))
    end
    assert_selector "a[aria-current=page]", text: "Dashboard"
  end

  test "the trash badge shows a count and hides at zero" do
    render_sidebar(labels: %w[Trash], trash_count: 3)
    assert_selector "a", text: /Trash\s*3/
    render_sidebar(labels: %w[Trash], trash_count: 0)
    assert_no_selector "[data-badge]"
  end

  test "the account block names the user, their email and their role line" do
    user = users(:one)
    user.name = "Ada Lovelace"
    render_sidebar(labels: %w[Dashboard], user: user)
    assert_selector ".admin-account", text: "Ada Lovelace"
    assert_selector ".admin-account", text: user.email_address
    assert_selector ".admin-account a", text: "Change password"
    assert_selector ".admin-account button", text: "Sign out"
    # Email and role share one line (review C, M9).
    assert_selector ".admin-account span", text: "#{user.email_address} · Owner", count: 1
  end

  test "the wordmark is uppercase with the site name under it" do
    render_sidebar(labels: %w[Dashboard])
    assert_selector ".admin-wordmark", text: "CONTENT·SPIEL"
    assert_selector ".admin-wordmark + .admin-site-name", text: Current.site.title
  end

  test "a user without a name shows the email once, with the role inline" do
    user = users(:one)
    user.name = nil
    render_sidebar(labels: %w[Dashboard], user: user)
    assert_selector ".admin-account", text: user.email_address, count: 1
    assert_equal 1, page.find(".admin-account").text.scan(user.email_address).size
    assert_selector ".admin-account", text: "Owner"
    assert_no_selector ".admin-account .font-cs-mono", text: /owner/i
  end

  test "the role line: Owner, up to two groups then +N, or No groups" do
    component = ->(user) { Admin::Shell::SidebarComponent.new(modules: [], user: user, current_path: "/", url_options: {}) }
    owner = User.new(owner: true)
    assert_equal "Owner", component.call(owner).role_line
    none = User.new
    assert_equal "No groups", component.call(none).role_line
    many = User.new
    many.define_singleton_method(:groups) { %w[Editor Author Reviewer Guest].map { |name| AccessControl::Group.new(name: name) } }
    assert_equal "Editor, Author +2", component.call(many).role_line
  end

  test "a long name or email truncates instead of widening the sidebar" do
    user = users(:one)
    user.name = "A" * 120
    render_sidebar(labels: %w[Dashboard], user: user)
    assert_selector ".admin-account .truncate[title='#{'A' * 120}']"
  end

  test "the Jump to button is wired for the command palette" do
    render_sidebar(labels: %w[Dashboard])
    assert_selector "button[data-action='admin--command-palette#open']", text: "Jump to…"
  end
end
