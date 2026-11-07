require "test_helper"

# The dashboard is CS Studio's start page: the admin root renders it and
# sign-in lands there. The Pages module is at /pages, after Dashboard in the
# sidebar.
class Admin::DashboardTest < ActionDispatch::IntegrationTest
  test "the admin root is the dashboard and sign-in lands there" do
    post admin_sign_in_path, params: { email_address: users(:one).email_address, password: "password" }
    assert_redirected_to admin_root_url
    follow_redirect!
    assert_select "h1", "Dashboard"
    assert_select "html[data-surface=studio]"
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
  # (its module in `StudioModules` has `permission: nil`), each of its own lists simply
  # coming back empty through the same read scopes every other list uses.
  test "a user who can read nothing still gets the dashboard" do
    sign_in_as users(:editor_branch)
    get admin_root_path
    assert_response :ok
    assert_select "h1", "Dashboard"
  end

  # Each panel is headed by its job, with one line under it, and tinted by
  # its kind.
  test "the panels and the activity feed render, each headed by its job" do
    draft = Current.set(actor: users(:one)) { create_post(title: "Half-written", published: false) }
    sign_in_as users(:one)
    get admin_root_path

    assert_select "section.admin-dashboard-panel--shortcuts[aria-labelledby=dashboard-drafts] h2", "Pick up where you left off"
    assert_select "section[aria-labelledby=dashboard-drafts] .admin-dashboard-panel__line", "Your drafts, the latest first."
    assert_select "section[aria-labelledby=dashboard-drafts] a[href='#{admin_post_path(draft)}']", text: "Half-written"
    assert_select "section.admin-dashboard-panel--information[aria-labelledby=dashboard-going-live-next] h2", "Publishing on its own"
    assert_select "section[aria-labelledby=dashboard-going-live-next] .admin-dashboard-panel__line", "Scheduled pages and posts, the soonest first."
    assert_select "turbo-frame#dashboard-waiting section.admin-dashboard-panel--action[aria-labelledby=dashboard-waiting-title] h2", "Waiting for you"
    assert_select "section.admin-dashboard-panel--information[aria-labelledby=dashboard-activity] h2", "What changed recently"
    assert_select "section[aria-labelledby=dashboard-activity] .admin-dashboard-panel__line", "The latest changes to pages, posts and images."
    assert_select "section[aria-labelledby=dashboard-activity] li", text: /Half-written/
  end

  test "the needs-translation card is hidden with one language" do
    with_locales(%w[en], default: "en")
    sign_in_as users(:one)
    get admin_root_path
    assert_select "section[aria-labelledby=dashboard-needs-translation]", count: 0
  end

  test "going live next shows the date tile, a relative phrase and by you" do
    # Pinned to midday: a phrase counts calendar days, so a run late in the
    # evening must not change the answer.
    travel_to Time.zone.local(2030, 1, 10, 12) do
      post = Current.set(actor: users(:one)) { create_post(title: "Soon", published: false) }
      post.update_columns(published_at: Time.zone.local(2030, 1, 15, 13))
      sign_in_as users(:one)
      get admin_root_path

      assert_select "section[aria-labelledby=dashboard-going-live-next] li", text: /Soon.*in 5 days.*by you/m
      assert_no_match "Schedule a draft", response.body
    end
  end

  test "the needs-translation card shows each target language's numbers with several languages" do
    with_locales(%w[en de], default: "en")
    Current.set(actor: users(:one)) { create_post(title: "Untranslated") }
    sign_in_as users(:one)
    get admin_root_path

    assert_select "section.admin-dashboard-panel--information[aria-labelledby=dashboard-needs-translation] h2", "Languages behind English"
    assert_select "section[aria-labelledby=dashboard-needs-translation] .admin-dashboard-panel__line", "What is missing or outdated, per language."
    assert_select "section[aria-labelledby=dashboard-needs-translation] [data-locale=de]", text: /Deutsch.*1 missing/m
    assert_select "section[aria-labelledby=dashboard-needs-translation] [role=progressbar]"
  end

  test "a change made through an API token reads as its user's, via the token's name, never the token" do
    post = Current.set(actor: users(:one)) { create_post(title: "From MCP") }
    token, = ApiToken.generate!(users(:two), group: access_control_groups(:admin), name: "Claude desktop")
    Current.set(actor: token, channel: :mcp) { Posts::Save.call(post, translations: { Locales.default => { title: "From MCP!" } }) }

    sign_in_as users(:one)
    get admin_root_path
    assert_select "section[aria-labelledby=dashboard-activity] li", text: /#{Regexp.escape(users(:two).email_address)} via Claude desktop edited “From MCP!”/
  end

  # Each panel's empty line, and the two actions.
  test "every empty card says its one line, with Start a draft and Drafts → for someone who may create and read posts" do
    with_locales(%w[en], default: "en")
    sign_in_as users(:one)
    get admin_root_path

    lines = css_select("p[data-panel-empty]").to_h { |line| [ line.ancestors("section").first["aria-labelledby"], line.text.squish ] }
    assert_equal({ "dashboard-notes-for-you" => "No notes for you.", "dashboard-waiting-title" => "Nothing is waiting for you.",
                   "dashboard-drafts" => "No drafts. Start a draft", "dashboard-going-live-next" => "Nothing scheduled. Drafts →",
                   "dashboard-activity" => "No recent activity." }, lines)
    assert_select "section[aria-labelledby=dashboard-going-live-next] p[data-panel-empty] a[href='#{admin_posts_path(scope: "drafts")}'][data-turbo-frame=_top] span[aria-hidden=true]", text: "→"
    assert_select ".admin-empty-state", count: 0
  end

  test "someone who may create nothing reads No drafts. alone, and Drafts → only with posts.read" do
    sign_in_as users(:reader)
    get admin_root_path
    assert_select "section[aria-labelledby=dashboard-drafts] p[data-panel-empty]", text: "No drafts."
    assert_select "a", text: "Start a draft", count: 0
    # The read-only group holds posts.read (test/fixtures/access_control/grants.yml).
    assert_select "section[aria-labelledby=dashboard-going-live-next] p[data-panel-empty] a[href='#{admin_posts_path(scope: "drafts")}']", count: 1

    sign_in_as users(:editor_branch)
    get admin_root_path
    assert_select "section[aria-labelledby=dashboard-going-live-next] p[data-panel-empty]", text: "Nothing scheduled."
    assert_select "section[aria-labelledby=dashboard-going-live-next] p[data-panel-empty] a", count: 0
  end

  test "empty lists say so" do
    sign_in_as users(:reader)
    get admin_root_path
    assert_match "No drafts.", response.body
    assert_match "Nothing scheduled.", response.body
    assert_match "No recent activity.", response.body
  end

  test "a user who can read nothing gets empty cards and no activity" do
    Current.set(actor: users(:one)) { create_post(title: "Not for you", published: false) }
    sign_in_as users(:editor_branch)
    get admin_root_path
    assert_response :ok
    assert_no_match "Not for you", response.body
    assert_match "No recent activity.", response.body
    assert_select "section[aria-labelledby=dashboard-needs-translation]", count: 0
  end

  # The heading row: "New post…" is the screen's one primary, "New page…"
  # its secondary before it, each a link to its standalone page that opens
  # the layout's dialog, and each drawn only for its right.
  test "New post… is the screen's one primary and New page… its secondary, each with its right" do
    root_page
    new_post = "div.admin-dashboard__head a[href='#{new_admin_post_path}'][data-turbo-frame=_top]" \
      "[data-action='admin--ui--dialog#open'][data-admin--ui--dialog-id-param=new-post-dialog]"
    new_page = "div.admin-dashboard__head a[href='#{new_admin_page_path}'][data-turbo-frame=_top]" \
      "[data-action='admin--ui--dialog#open'][data-admin--ui--dialog-id-param=new-page-dialog]"
    primary = Admin::Ui::ButtonComponent.classes(:primary)
    secondary = Admin::Ui::ButtonComponent.classes(:secondary)

    sign_in_as users(:one)
    get admin_root_path
    assert_select "div.admin-dashboard__head > h1", "Dashboard"
    assert_select new_post, exact_text: "New post…", count: 1
    assert_select new_page, exact_text: "New page…", count: 1
    assert_equal primary, css_select(new_post).first["class"]
    assert_equal secondary, css_select(new_page).first["class"]
    assert_equal %w[New\ page… New\ post…], css_select("div.admin-dashboard__head a").map { |link| link.text.strip }
    # Nothing else on the screen is a primary.
    assert_equal 1, css_select(".admin-dashboard a, .admin-dashboard button").count { |control| control["class"].to_s.split.include?("bg-accent") }

    sign_in_as users(:author) # posts.create, no pages.create
    get admin_root_path
    assert_select new_post, count: 1
    assert_select new_page, count: 0

    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.create", scope: { "page_ids" => [ root_page.id ] })
    sign_in_as users(:editor_branch) # pages.create alone
    get admin_root_path
    assert_select new_post, count: 0
    assert_select new_page, count: 1

    sign_in_as users(:reader) # neither
    get admin_root_path
    assert_select "div.admin-dashboard__head > h1", "Dashboard"
    assert_select "div.admin-dashboard__head a", count: 0
  end

  test "Start a draft opens the New post dialog, for someone who may create posts" do
    sign_in_as users(:author)
    get admin_root_path
    assert_select "section[aria-labelledby=dashboard-drafts] p[data-panel-empty] a[href='#{new_admin_post_path}'][data-turbo-frame=_top]" \
      "[data-action='admin--ui--dialog#open'][data-admin--ui--dialog-id-param=new-post-dialog]", exact_text: "Start a draft"

    sign_in_as users(:reader)
    get admin_root_path
    assert_select "a", text: "Start a draft", count: 0
  end

  test "POST dashboard/draft is gone" do
    sign_in_as users(:one)
    assert_no_difference -> { Post.count } do
      post "/cs-studio/dashboard/draft", params: { title: "New idea", content_type: "blog" }
    end
    assert_response :not_found
    assert_not Rails.application.routes.url_helpers.respond_to?(:admin_dashboard_draft_path)
    assert_not respond_to?(:admin_dashboard_draft_path)
  end

  test "the full audit log link needs audit.view" do
    sign_in_as users(:one)
    get admin_root_path
    assert_select "a", text: /Full audit log/

    sign_in_as users(:reader)
    get admin_root_path
    assert_select "a", text: /Full audit log/, count: 0
  end

  # Drafts are tiles: each its own record's type, title, excerpt and time.
  test "Pick up where you left off draws the viewer's drafts as tiles that end in Continue" do
    draft = Current.set(actor: users(:one)) { create_post(title: "Half-written", published: false) }
    sign_in_as users(:one)
    get admin_root_path
    assert_select "section[aria-labelledby=dashboard-drafts] ul.admin-draft-tiles > li > article.admin-draft-tile" do
      assert_select "a.admin-draft-tile__link[href='#{admin_post_path(draft)}']", text: "Half-written"
      assert_select "span.admin-row-verb", "Continue"
    end
    assert_select "section[aria-labelledby=dashboard-drafts] a[aria-label='All drafts'][href='#{admin_posts_path(scope: "drafts")}']", text: "→"
  end

  # Everything a row renders -- editor paths, type labels, the activity
  # sentences (a token's user included), the translation panel and every
  # kind of row Waiting for you has -- comes from a constant set of queries.
  # Signed in as users(:two), a non-owner Admin-group member who may publish
  # pages and posts, so every `can?` and every read scope goes through the
  # grant path rather than the owner shortcut. Waiting for you's kinds are
  # made last, so its five rows are the same kinds with one set as with
  # twenty: an image's thread, a page's thread, a page and a post the feed
  # alone brings, and a post with both reasons.
  test "the dashboard renders in the same number of queries with 1 or 20 records per list" do
    me = users(:two)
    token, = ApiToken.generate!(me, group: access_control_groups(:admin))
    counts = [ 1, 20 ].map do |n|
      n.times do |i|
        Current.set(actor: me, channel: :admin) do
          create_post(title: "D#{n}-#{i}", published: false).update_columns(excerpt: { Locales.default => "An excerpt #{i}" })
          create_post(title: "S#{n}-#{i}", published: false).update_columns(published_at: (i + 1).days.from_now)
          create_page(title: "P#{n}-#{i}", published: false)
          create_media_asset.tap { |asset| Audit.record("media.uploaded", subject: asset) }
        end
        Current.set(actor: token, channel: :mcp) { create_post(title: "T#{n}-#{i}", published: false) }
        as(users(:one)) do
          [ create_media_asset, create_page(title: "Discussed #{n}-#{i}") ].each { |record| assert Notes::Start.call(record, body: "A note").ok? }
        end
        [ create_page(title: "Marked page #{n}-#{i}"), create_post(title: "Marked post #{n}-#{i}") ].each { |record| record.update_columns(unpublished_changes_at: Time.current) }
        both = create_post(title: "Both #{n}-#{i}")
        as(users(:one)) { assert Notes::Start.call(both, body: "A note").ok? }
        both.update_columns(unpublished_changes_at: Time.current)
      end
      sign_in_as me
      get admin_root_path # warm-up: first-render template compilation, schema loads
      queries = 0
      callback = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:sql].start_with?("BEGIN", "COMMIT", "SAVEPOINT", "RELEASE") }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get admin_root_path }
      assert_response :ok
      assert_select "section[aria-labelledby=dashboard-drafts] article.admin-draft-tile p.line-clamp-2", text: /An excerpt/
      assert_select "section[aria-labelledby=dashboard-activity] li"
      assert_select "section[aria-labelledby=dashboard-needs-translation] li"
      assert_select ".admin-waiting-row", count: 5
      assert_select ".admin-waiting-row a", text: "Review and publish…", count: 3
      assert_select ".admin-waiting-row .admin-notes-marker", count: 3
      queries
    end
    assert_equal counts.first, counts.last
    # Waiting for you's count beside its heading is 3 of these: the threads'
    # records in one statement and the unpublished ones in one per model.
    assert_operator counts.last, :<=, 46, "the dashboard's statements: #{counts.last}"
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

  # The failed-send notice (spec "The states"; plan ruling P3): the
  # dashboard's, for whoever holds settings.manage, and only while the last
  # send failed. It is the sentence of the state, never the server's line.
  include MailState

  test "the notice is shown to settings.manage only, and only while the last send failed" do
    sign_in_as users(:one)

    with_mail_state(:failed) do
      get admin_root_path

      assert_select "#mail-failed-notice[role=alert]", text: /Last send failed .*: the server refused the login\./ do
        assert_select "a[href=?]", "/cs-studio/settings#mail", text: "Open Mail settings →"
      end
      assert_no_match(/535 5\.7\.8/, response.body)
    end

    %i[working untested not_set_up].each do |state|
      with_mail_state(state) do
        get admin_root_path

        assert_select "#mail-failed-notice", count: 0
      end
    end
  end

  test "someone without settings.manage is shown no notice while the last send failed" do
    sign_in_as users(:reader)

    with_mail_state(:failed) do
      get admin_root_path

      assert_response :ok
      assert_select "#mail-failed-notice", count: 0
    end
  end
end
