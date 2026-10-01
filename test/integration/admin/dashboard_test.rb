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

  # Task 4 (dashboard spec §4): the two columns' lists, quick create and
  # the permission-dependent links. A user's display name in CS Studio is
  # their email address (`User` has no name column) -- the same label the
  # audit log and the trash already use.
  test "both columns render their lists with labels and links" do
    @draft = Current.set(actor: users(:one)) { create_post(title: "Half-written", published: false) }
    sign_in_as users(:one)
    get admin_root_path
    assert_select "section[aria-labelledby=your-work] h2#your-work", "Your work"
    assert_select "section[aria-labelledby=on-the-site] h2#on-the-site", "On the site"
    assert_select "section[aria-labelledby=your-work] a[href='#{admin_post_path(@draft)}']", text: /Half-written/
    assert_select "section[aria-labelledby=on-the-site]", text: /by #{Regexp.escape(users(:one).email_address)}/
  end

  test "a change made through an API token reads as its user's" do
    post = Current.set(actor: users(:one)) { create_post(title: "From MCP") }
    token, = ApiToken.generate!(users(:two), group: access_control_groups(:admin))
    Current.set(actor: token, channel: :mcp) { Posts::Save.call(post, translations: { Locales.default => { title: "From MCP!" } }) }

    sign_in_as users(:one)
    get admin_root_path
    assert_select "section[aria-labelledby=on-the-site] li", text: /From MCP!.*by #{Regexp.escape(users(:two).email_address)}/m
  end

  test "empty lists say so" do
    sign_in_as users(:reader)
    get admin_root_path
    assert_match "No drafts — start one above.", response.body
    assert_match "Nothing scheduled.", response.body
    assert_match "Nothing edited yet.", response.body
    assert_match "Nothing scheduled on the site.", response.body
    assert_match "No changes yet.", response.body
  end

  test "quick draft creates a draft and opens it" do
    sign_in_as users(:one)
    assert_difference -> { Post.count } do
      post admin_dashboard_draft_path, params: { title: "New idea", content_type: "blog" }
    end
    post = Post.order(:id).last
    assert_nil post.published_at
    assert_equal "blog", post.content_type
    assert_equal "New idea", post.title
    assert_redirected_to admin_post_path(post)
    follow_redirect!
    assert_match "Draft created", response.body
  end

  test "a blank title re-renders the dashboard with the error" do
    sign_in_as users(:one)
    assert_no_difference -> { Post.count } do
      post admin_dashboard_draft_path, params: { title: "", content_type: "blog" }
    end
    assert_response :unprocessable_entity
    assert_select "[role=alert]"
    assert_select "h1", "Dashboard"
    assert_select "select[name=content_type] option[selected][value=blog]"
  end

  # Review Focus 3: an Author whose `posts.create` is scoped to one content
  # type is offered only that type, and a forged other type is refused with
  # a 403 by `Posts::Save` itself, not merely hidden from the select.
  test "the type select lists only creatable types, and a forged type is refused" do
    bloggers = AccessControl::Group.create!(name: "Bloggers")
    bloggers.grants.create!(permission: "posts.read", scope: {})
    bloggers.grants.create!(permission: "posts.create", scope: { "content_types" => [ "blog" ] })
    blogger = User.create!(email_address: "blogger@example.com", password: "password123")
    AccessControl::Membership.create!(user: blogger, group: bloggers)

    sign_in_as blogger
    get admin_root_path
    assert_select "select[name=content_type] option", count: 1
    assert_select "select[name=content_type] option[value=blog]", "Blog"

    assert_no_difference -> { Post.count } do
      post admin_dashboard_draft_path, params: { title: "Sneaky", content_type: "now_update" }
    end
    assert_response :forbidden
  end

  test "a user who can create no post type gets no quick draft form" do
    sign_in_as users(:reader)
    get admin_root_path
    assert_select "select[name=content_type]", count: 0
    assert_select "form[action='#{admin_dashboard_draft_path}']", count: 0
  end

  test "New page, Upload image and the audit link follow permissions" do
    sign_in_as users(:reader)
    get admin_root_path
    assert_select "a", text: "New page", count: 0
    assert_select "a", text: "Upload image", count: 0
    assert_select "a", text: /Full audit log/, count: 0

    sign_in_as users(:one)
    get admin_root_path
    assert_select "a[href='#{new_admin_page_path}']", text: "New page"
    assert_select "a[href='#{admin_media_path}']", text: "Upload image"
    assert_select "a[href='#{admin_audit_events_path}']", text: /Full audit log/
  end

  # Spec §4.5, at the view level: everything a row renders -- status
  # badges, editor paths, "by" names (a token's user included), image
  # thumbnails -- comes from the feed's constant set of queries. Signed in
  # as users(:two), a non-owner Admin-group member, so every `can?` and
  # every read scope goes through the grant path rather than the owner
  # shortcut.
  test "the dashboard renders in the same number of queries with 1 or 20 records per list" do
    me = users(:two)
    token, = ApiToken.generate!(me, group: access_control_groups(:admin))
    counts = [ 1, 20 ].map do |n|
      n.times do |i|
        Current.set(actor: me, channel: :admin) do
          create_post(title: "D#{n}-#{i}", published: false)
          create_post(title: "S#{n}-#{i}", published: false).update_columns(published_at: (i + 1).days.from_now)
          create_page(title: "P#{n}-#{i}", published: false)
          create_media_asset.tap { |asset| Audit.record("media.uploaded", subject: asset) }
        end
        Current.set(actor: token, channel: :mcp) { create_post(title: "T#{n}-#{i}", published: false) }
      end
      sign_in_as me
      get admin_root_path # warm-up: first-render template compilation, schema loads
      queries = 0
      callback = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:sql].start_with?("BEGIN", "COMMIT", "SAVEPOINT", "RELEASE") }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get admin_root_path }
      assert_response :ok
      assert_select "section[aria-labelledby=your-work] li"
      assert_select "section[aria-labelledby=on-the-site] li img"
      queries
    end
    assert_equal counts.first, counts.last
  end
end
