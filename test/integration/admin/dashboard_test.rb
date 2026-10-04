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
    root_page
    get admin_pages_path
    assert_response :see_other # opens Home's editor
    follow_redirect!
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

  # Round 2, Task 16: quick create, three cards and one activity feed (the
  # old "Your work" / "On the site" columns and their lists are gone).
  test "the three cards and the activity feed render; the old two columns are gone" do
    draft = Current.set(actor: users(:one)) { create_post(title: "Half-written", published: false) }
    sign_in_as users(:one)
    get admin_root_path

    assert_select "section[aria-labelledby=dashboard-drafts] h2", "Your drafts"
    assert_select "section[aria-labelledby=dashboard-drafts] a[href='#{admin_post_path(draft)}']", text: "Half-written"
    assert_select "section[aria-labelledby=dashboard-going-live-next] h2", "Going live next"
    assert_select "section[aria-labelledby=dashboard-activity] h2", "Recent activity"
    assert_select "section[aria-labelledby=dashboard-activity] li", text: /Half-written/
    assert_select "#your-work, #on-the-site, #dashboard-recently-updated, #dashboard-recently-edited, #dashboard-scheduled", count: 0
  end

  test "the needs-translation card is hidden with one language" do
    with_locales(%w[en], default: "en")
    sign_in_as users(:one)
    get admin_root_path
    assert_select "section[aria-labelledby=dashboard-needs-translation]", count: 0
  end

  test "going live next shows the date tile, a relative phrase and by you" do
    post = Current.set(actor: users(:one)) { create_post(title: "Soon", published: false) }
    post.update_columns(published_at: 5.days.from_now + 1.hour)
    sign_in_as users(:one)
    get admin_root_path

    assert_select "section[aria-labelledby=dashboard-going-live-next] li", text: /Soon.*in 5 days.*by you/m
    assert_select "section[aria-labelledby=dashboard-going-live-next]", text: /Schedule a draft to see it here\./
  end

  test "the needs-translation card shows each target language's numbers with several languages" do
    with_locales(%w[en de], default: "en")
    Current.set(actor: users(:one)) { create_post(title: "Untranslated") }
    sign_in_as users(:one)
    get admin_root_path

    assert_select "section[aria-labelledby=dashboard-needs-translation] li[data-locale=de]", text: /Deutsch.*1 missing/m
    assert_select "section[aria-labelledby=dashboard-needs-translation] [role=progressbar]"
  end

  test "a change made through an API token reads as its user's, via an API token, never the token" do
    post = Current.set(actor: users(:one)) { create_post(title: "From MCP") }
    token, = ApiToken.generate!(users(:two), group: access_control_groups(:admin))
    Current.set(actor: token, channel: :mcp) { Posts::Save.call(post, translations: { Locales.default => { title: "From MCP!" } }) }

    sign_in_as users(:one)
    get admin_root_path
    assert_select "section[aria-labelledby=dashboard-activity] li", text: /#{Regexp.escape(users(:two).email_address)} via an API token edited “From MCP!”/
  end

  test "empty lists say so" do
    sign_in_as users(:reader)
    get admin_root_path
    assert_match "No drafts — start one above.", response.body
    assert_match "Nothing scheduled on the site.", response.body
    assert_match "No activity yet.", response.body
  end

  test "a user who can read nothing gets empty cards and no activity" do
    Current.set(actor: users(:one)) { create_post(title: "Not for you", published: false) }
    sign_in_as users(:editor_branch)
    get admin_root_path
    assert_response :ok
    assert_no_match "Not for you", response.body
    assert_match "No activity yet.", response.body
    assert_select "section[aria-labelledby=dashboard-needs-translation]", count: 0
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
    blogger = User.create!(email_address: "blogger@example.com", password: "password12345")
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

  test "the type select ends with Page for someone who may create pages, and the bar has no New page or Upload image buttons" do
    sign_in_as users(:one)
    get admin_root_path
    assert_equal "page", css_select("select[name=content_type] option").last["value"]
    assert_select "select[name=content_type] option", text: "Page"
    assert_select "a", text: "Upload image", count: 0
    assert_select "form[action='#{admin_dashboard_draft_path}'] a[data-admin--dialog-id-param=new-page-dialog][hidden]", count: 1
    assert_select "a", text: /Full audit log/
  end

  test "Page is offered only with pages.create, and the audit link needs audit.view" do
    sign_in_as users(:reader)
    get admin_root_path
    assert_select "select[name=content_type] option[value=page]", count: 0
    assert_select "a", text: /Full audit log/, count: 0
  end

  test "submitting the quick draft form with Page goes to the standalone New page screen" do
    sign_in_as users(:one)
    assert_no_difference -> { Post.count + Page.count } do
      post admin_dashboard_draft_path, params: { title: "Ignored", content_type: "page" }
    end
    assert_redirected_to new_admin_page_path
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
      assert_select "section[aria-labelledby=dashboard-drafts] li"
      assert_select "section[aria-labelledby=dashboard-activity] li"
      assert_select "section[aria-labelledby=dashboard-needs-translation] li"
      queries
    end
    assert_equal counts.first, counts.last
  end

  test "a user with no groups sees only the open modules, no empty group headings, and No groups" do
    user = User.create!(email_address: "nobody@example.com", password: "a long enough password")
    sign_in_as user
    get admin_root_path
    assert_response :success
    assert_select "nav[aria-label='Modules'] h2", count: 2 # Content (Dashboard) and System (AI assistant)
    assert_select "nav[aria-label='Modules'] h2", text: "People", count: 0
    assert_select ".admin-account", text: /No groups/
  end
end
