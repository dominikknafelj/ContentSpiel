require "test_helper"

class Admin::Shell::SidebarComponentTest < ViewComponent::TestCase
  def all_modules = StudioModules.entries.map(&:to_row)

  def modules(*labels) = all_modules.select { |entry| labels.include?(entry[:label]) }

  def render_sidebar(labels:, user: users(:one), badges: {}, current_path: "/cs-studio/posts")
    with_request_url "/cs-studio" do
      render_inline(Admin::Shell::SidebarComponent.new(modules: modules(*labels), user: user,
        current_path: current_path, url_options: {}, badges: badges))
    end
  end

  def link(label) = page.find("nav[aria-label='#{t("admin.components.shell.sidebar.label")}'] a", text: label, match: :prefer_exact)

  def t(key) = I18n.t(key)

  test "modules are grouped under Content, People and System, in the design's order" do
    render_sidebar(labels: all_modules.map { |entry| entry[:label] })
    assert_equal %w[Content People System], page.all("nav[aria-label='Modules'] h2").map(&:text)
    content = page.all("nav[aria-label='Modules'] section")[0].all("a").map(&:text).map(&:strip)
    assert_equal [ "Dashboard", "Pages", "Posts", "Media", "Forms", "Translations", "Tags", "Mind graph", "Trash" ], content
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

  def chip(label) = link(label).find("span[aria-hidden=true][class~='rounded-chip']")

  test "no module's chip is neutral, and each is its family's" do
    render_sidebar(labels: all_modules.map { |entry| entry[:label] }, current_path: "/cs-studio/account")

    all_modules.each do |entry|
      classes = chip(entry[:label])[:class].split
      assert_includes classes, "bg-ic-#{entry[:family]}-bg", entry[:label]
      assert_includes classes, "text-ic-#{entry[:family]}", entry[:label]
      assert_not_includes classes, "bg-sunken", entry[:label]
      assert_not_includes classes, "bg-accent-tint", entry[:label]
    end
  end

  test "the current module keeps its chip's family on the accent-tint row with accent words" do
    render_sidebar(labels: %w[Dashboard Posts Media])

    current = page.find("a[aria-current=page]")
    assert_equal "Posts", current.text.strip
    assert_includes current[:class].split, "bg-accent-tint"
    assert_includes current[:class].split, "text-accent"
    assert current.has_selector?("span[aria-hidden=true][class~='bg-ic-lists-bg'][class~='text-ic-lists']")
    assert_no_selector "span[aria-hidden=true][class~='rounded-chip'][class~='bg-accent-tint']"
    # The other rows rest on the column, sunken under the pointer, in 8px corners.
    other = link("Media")
    assert_includes other[:class].split, "rounded-button"
    assert_includes other[:class].split, "hover:bg-sunken"
    assert_not_includes other[:class].split, "bg-accent-tint"
    assert_includes chip("Media")[:class].split, "bg-ic-media-bg"
  end

  test "the labels and headings are read from keys" do
    render_sidebar(labels: all_modules.map { |entry| entry[:label] })

    assert_selector "nav[aria-label='#{t("admin.components.shell.sidebar.label")}']"
    assert_equal StudioModules.groups.map { |group| t("admin.module_groups.#{group}") }, page.all("nav h2").map(&:text)
    assert_equal StudioModules.entries.map { |entry| t("admin.modules.#{entry.name}") }, page.all("nav section a").map { |a| a.text.strip }
    assert_selector "button", text: t("admin.components.shell.sidebar.jump")
    assert_selector "button", text: t("admin.components.shell.sidebar.sign_out")
    assert_selector ".admin-wordmark", text: t("admin.components.shell.sidebar.wordmark")
  end

  test "the trash badge shows a count, and is in the page hidden and empty at zero" do
    render_sidebar(labels: %w[Trash], badges: { trash: 3 })
    assert_selector "a", text: /Trash\s*3/
    assert_selector "a #sidebar-badge-trash[data-badge]", text: "3"
    # A plain number in sans: the sidebar's one filled badge is the Dashboard's.
    assert_no_selector "#sidebar-badge-trash[class*=accent]"
    assert_no_selector "#sidebar-badge-trash[class*=mono]"
    render_sidebar(labels: %w[Trash], badges: { trash: 0 })
    assert_no_selector "[data-badge]"
    assert_selector "#sidebar-badge-trash[hidden]", visible: :all
  end

  # Notes spec §5: the viewer's unread notes, on the Dashboard entry. The
  # element is always there (a live signal fills it), hidden and empty at
  # zero; accent, the one filled badge, because it means "unread and
  # addressed to you".
  test "the Dashboard badge shows the unread count as a filled accent pill, and is in the page hidden and empty at zero" do
    render_sidebar(labels: %w[Dashboard Trash], badges: { dashboard: 3 })
    assert_selector "a[href='/cs-studio'] #sidebar-badge-dashboard[data-badge].bg-accent.text-on-accent.rounded-full", text: "3"
    assert_no_selector "#sidebar-badge-trash"
    assert_selector "#sidebar-badge-trash[hidden]", visible: :all

    render_sidebar(labels: %w[Dashboard Trash], badges: {})
    assert_selector "#sidebar-badge-dashboard", visible: :all, count: 1
    assert_equal "", page.find("#sidebar-badge-dashboard", visible: :all).text(:all)
    assert_selector "#sidebar-badge-dashboard[hidden]:not([data-badge])", visible: :all
  end

  test "a module registered with a filled badge draws it filled, and a plain one plain" do
    StudioModules.with(StudioModules.entries) do
      StudioModules.badge(:posts, style: :filled) { |viewer:| 2 }
      StudioModules.badge(:dashboard) { |viewer:| 1 }
      render_sidebar(labels: %w[Dashboard Posts], badges: { posts: 2, dashboard: 1 })
    end

    assert_selector "#sidebar-badge-posts[data-badge].bg-accent.text-on-accent.rounded-full", text: "2"
    assert_selector "#sidebar-badge-dashboard[data-badge]", text: "1"
    assert_no_selector "#sidebar-badge-dashboard[class*=accent]"
  end

  test "an entry that has no badge gets none, whatever is handed in" do
    render_sidebar(labels: %w[Posts], badges: { posts: 4 })
    assert_no_selector "[data-badge]"
  end

  test "the account block names the user, their email and their role line" do
    user = users(:one)
    user.name = "Ada Lovelace"
    render_sidebar(labels: %w[Dashboard], user: user)
    assert_selector ".admin-account", text: "Ada Lovelace"
    assert_selector ".admin-account", text: user.email_address
    # The entry reads "Your account" (the handoff's decision 25), and the
    # name block above it leads to the same screen.
    assert_selector ".admin-account a[href='/cs-studio/account']", text: /\AYour account\z/
    assert_selector ".admin-account a#account-identity[href='/cs-studio/account']", text: "Ada Lovelace"
    assert_no_selector ".admin-account a", text: "Change password"
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
    assert_selector "button[data-action='admin--shell--command-palette#open']", text: "Jump to…"
  end

  # Signing out ends the document (ledger C-M2): never a Turbo submission,
  # which would keep module state for the next user of the tab.
  test "Sign out is a real navigation" do
    render_inline Admin::Shell::SidebarComponent.new(modules: [], user: users(:one), current_path: "/cs-studio", url_options: {})

    assert_selector "form[data-turbo=false][action$='/sign-out'] button", text: "Sign out"
  end
end
