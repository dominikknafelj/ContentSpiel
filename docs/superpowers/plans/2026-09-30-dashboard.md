# Dashboard and Site Time Zone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** CS Studio opens on a dashboard with "Your work", "On the site" and quick create, and every CS Studio time is shown and parsed in a configurable site time zone.

**Architecture:**
- **Site time zone.** It is one `site_settings.time_zone` column. CS Studio and MCP requests run inside `Time.use_zone(Current.site.time_zone)`, so existing `Time.zone`/`TimeWithZone` code shows and parses local times without per-call changes.
- **Dashboard.** It is `Admin::DashboardController#show` at the admin root, and the pages list moves to `/<admin>/pages`.
- **Data.** One query object, `Dashboard::Feed`, builds every list from read-scoped relations, plus one batched "newest audit event per record" query. View components render the lists.

**Tech Stack:** Rails 8.1, Postgres (`DISTINCT ON`), ViewComponent, Minitest with fixtures, and Cuprite system tests.

**Spec:** `docs/superpowers/specs/2026-09-30-dashboard-design.md`

## Global Constraints

**Storage, scoping and audit**
- Storage stays UTC. Only display and parsing use the site zone.
- `site_settings.time_zone`: string, not null, default `"UTC"`, and it must be a name in `ActiveSupport::TimeZone.all.map(&:name)` (a `Rails` name such as `"Berlin"`; an `"Europe/Berlin"` identifier should be accepted too, through `ActiveSupport::TimeZone[...]`).
- Every list is read-scoped through `AccessControl.scope(Current.actor, "pages.read"/"posts.read", ...)`, which already excludes trashed records. Images are listed only for `can?("media.upload")`, and only `Media::Asset.kept`.
- No new permission, no new service and no new audit event. Quick draft goes through `Posts::Save`, the time zone through `Settings::Save`.
- Writes stay in services. Refusals answer like other admin writes: `forbidden_or(result)` (403 for a permission refusal).

**Dashboard content**
- Limits:
  - Drafts: 10.
  - Scheduled (mine): 10.
  - Recently edited by you: 10.
  - Going live next: 10.
  - Recently updated: 15.
- "Mine":
  - a **post** is mine when `author_id == user.id`, or when its newest audit event's actor is the user;
  - a **page** is mine when its newest audit event's actor is the user.
- "by" label:
  - "by <name>" from the newest audit event's actor;
  - "by System" when that event's actor is nil;
  - nothing when the record has no audit event.
- Empty states:
  - Drafts: "No drafts — start one above."
  - Scheduled (mine): "Nothing scheduled."
  - Recently edited by you: "Nothing edited yet."
  - Going live next: "Nothing scheduled on the site."
  - Recently updated: "No changes yet."
- The dashboard renders in a constant number of queries, whatever the data size.
- No browser dialogs. Never define `Admin::Dashboard` as a module that shadows a top-level constant; the top-level query object is `Dashboard::Feed`, so components are `Admin::DashboardScreen::*`.

**Conventions and process**
- Keep the codebase's comment density: long, load-bearing comments for non-obvious invariants.
- Commits use conventional messages ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never skip hooks.
- Tests: `PARALLEL_WORKERS=1 bin/rails test`, `bin/rails test:system`, `bin/rubocop`.

## Review Focus

1. **DST.** A schedule time typed during a DST gap (Berlin, last Sunday of March, 02:30) is saved, not refused with a 500 (Task 1 test).
2. **"Mine" for pages.** A page someone else last edited after me is no longer in my "Recently edited", but still is in the site's "Recently updated" (Task 3 test).
3. **Quick-draft types.** An Author whose `posts.create` is scoped to one content type sees only that type, and a forged other type gets a 403 (Task 4 test).
4. **Moved pages list.** Every place that meant "the pages list" still reaches it after `admin_root_path` becomes the dashboard: the tree, the trash's post-move redirect, the "back" links (Task 2 test).
5. **Query count.** With 20 records per list the dashboard runs the same number of queries as with 1 (Task 3 test).

---

### Task 1: Site time zone

**Files:**
- Create: `db/migrate/20260930100000_add_time_zone_to_site_settings.rb`
- Modify: `app/models/site_setting.rb` (validation and normalisation)
- Modify: `app/controllers/admin/base_controller.rb` (`around_action :use_site_time_zone`)
- Modify: `app/controllers/mcp_controller.rb` (the same around_action)
- Modify: `app/components/admin/settings_form_component.rb` + `.html.erb` (time zone select)
- Modify: `app/controllers/admin/settings_controller.rb` (permit `time_zone`; error slot in `autosave_stream`)
- Test: `test/models/site_setting_test.rb`, `test/integration/admin/settings_test.rb`, `test/integration/admin/time_zone_test.rb` (new), and an MCP date test in the existing MCP integration tests

**Interfaces:**
- Produces:
  - `SiteSetting#time_zone` (String);
  - every Admin and MCP request runs with `Time.zone` set to it.

- [ ] **Step 1: Write the failing tests**

```ruby
# test/models/site_setting_test.rb
test "time zone defaults to UTC and must be a known zone" do
  assert_equal "UTC", SiteSetting.new(title: "x").time_zone
  site = site_settings(:default)
  site.time_zone = "Mars/Olympus"
  assert_not site.valid?
  assert_includes site.errors[:time_zone], "isn't a known time zone"
  site.time_zone = "Berlin"
  assert site.valid?
  site.time_zone = "Europe/Berlin"
  assert site.valid?
end
```

```ruby
# test/integration/admin/time_zone_test.rb
require "test_helper"

# Site time zone (dashboard spec §5): CS Studio shows and parses times in
# `SiteSetting#time_zone`; storage stays UTC.
class Admin::TimeZoneTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(time_zone: "Europe/Berlin")
    sign_in_as users(:one)
    @post = Current.set(actor: users(:one)) { create_post(title: "Later", published: false) }
  end

  test "a schedule time is read as site-local and stored as UTC" do
    patch schedule_path_for(@post), params: { published_at: "2026-11-02T09:00" }
    assert_equal Time.utc(2026, 11, 2, 8, 0), @post.reload.published_at   # CET = UTC+1
  end

  test "a scheduled time shows in site-local time" do
    @post.update_columns(published_at: Time.utc(2026, 7, 1, 7, 30))      # CEST = UTC+2
    get admin_post_path(@post)
    assert_match "2026-07-01T09:30", response.body                       # the datetime-local value
  end

  test "a time in the spring-forward gap is saved, not a 500" do
    patch schedule_path_for(@post), params: { published_at: "2027-03-28T02:30" }
    assert_response :redirect
    assert @post.reload.published_at.present?
  end

  test "audit log and trash times render in the site zone" do
    # create an event/trash entry at a known UTC instant (travel_to), then assert the
    # rendered time string is the Berlin local time on /audit_events and /trash
  end
end
```

Fill in `schedule_path_for` with the real schedule action and params for posts (`grep -n "published_at" app/controllers/admin/posts_controller.rb`), and write the audit-log and trash assertions for real, matching how each screen formats times. Add an MCP test: with Berlin set, a post's `published_at` in an MCP `get_post` response carries `+01:00`/`+02:00`, not `Z`.

- [ ] **Step 2: Run them and see them fail**

Run: `PARALLEL_WORKERS=1 bin/rails test test/models/site_setting_test.rb test/integration/admin/time_zone_test.rb`
Expected: errors (`unknown attribute 'time_zone'`), then wrong-hour failures.

- [ ] **Step 3: Implement**

```ruby
# db/migrate/20260930100000_add_time_zone_to_site_settings.rb
class AddTimeZoneToSiteSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :site_settings, :time_zone, :string, null: false, default: "UTC"
  end
end
```

```ruby
# app/models/site_setting.rb
# The zone every CS Studio and MCP time is shown and parsed in (dashboard
# spec §5); storage stays UTC. Accepts a Rails zone name ("Berlin") or an
# IANA identifier ("Europe/Berlin") -- `ActiveSupport::TimeZone[]` resolves both.
validate :time_zone_is_known

def time_zone_is_known
  errors.add(:time_zone, "isn't a known time zone") unless ActiveSupport::TimeZone[time_zone.to_s]
end
```

```ruby
# app/controllers/admin/base_controller.rb
around_action :use_site_time_zone

# Every time CS Studio shows or parses -- schedule inputs, "Saved HH:MM",
# the trash and audit screens, the dashboard -- is in the site's zone
# (dashboard spec §5). Wrapping the request is what lets the existing
# `Time.zone.parse`/`strftime` call sites stay as they are.
def use_site_time_zone(&block)
  Time.use_zone(Current.site.time_zone, &block)
end
```

`McpController` gets the same `around_action`. Check how it loads `Current.site`, and fall back to `SiteSetting.instance` if `Current.site` isn't set there. MCP serialises times with `iso8601`, so the offset follows the zone.

Settings form: a `<select>` of `ActiveSupport::TimeZone.all` (label `"(GMT+01:00) Berlin"`, value `zone.name`), following the `default_locale` field markup. Permit `time_zone` in `SettingsController` and wire its error slot into `autosave_stream`, as `trash_retention_days` does.

- [ ] **Step 4: Run the tests, then the full suite.** `PARALLEL_WORKERS=1 bin/rails test`

- [ ] **Step 5: Commit** `git commit -m "feat: show and parse CS Studio times in a site time zone"`

---

### Task 2: Dashboard route, shell and the moved pages list

**Files:**
- Modify: `config/routes.rb` (admin `root to: "dashboard#show"`; the pages index stays at `/pages`)
- Create: `app/controllers/admin/dashboard_controller.rb`, `app/views/admin/dashboard/show.html.erb` (a shell: heading "Dashboard", two empty columns)
- Modify: `app/controllers/admin/base_controller.rb` (`MODULES`: Dashboard first, `permission: nil`; Pages `path: :admin_pages_path`)
- Modify: every place that means "the pages list" via `admin_root_path`/`admin_root_url`: `app/controllers/admin/pages_controller.rb`, `app/controllers/admin/starter_contents_controller.rb`, the trash post-move redirect (`grep -rn "admin_root_path\|admin_root_url" app`), plus `setup_controller.rb` and `authentication.rb`, which keep meaning "CS Studio home" (now the dashboard; leave them).
- Modify: tests that expect the pages list at the admin root (`grep -rln "admin_root_path" test`).
- Modify: the sidebar icon set, if an icon is needed (`icon: :dashboard`; follow the existing icon helper/component).
- Test: `test/integration/admin/dashboard_test.rb` (new), and the existing pages and trash tests

**Interfaces:**
- Produces:
  - `admin_root_path` is now the dashboard; `admin_pages_path` is the pages list;
  - `Admin::DashboardController#show` renders `admin/dashboard/show`.

- [ ] **Step 1: Write the failing tests**

```ruby
# test/integration/admin/dashboard_test.rb
require "test_helper"

class Admin::DashboardTest < ActionDispatch::IntegrationTest
  test "the admin root is the dashboard and sign-in lands there" do
    post admin_session_path, params: { email_address: users(:one).email_address, password: "password" }
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

  test "a user who can read nothing still gets the dashboard" do
    sign_in_as users(:reader)   # or a user in a group without grants; check fixtures
    get admin_root_path
    assert_response :ok
  end
end
```

Use the real sign-in route and params from `test/integration/sessions_test.rb`. Update the existing tests that expected the pages list or tree at the admin root to use `admin_pages_path`; Review Focus 4 is covered when the trash, tree and "back" link tests pass against the new path.

- [ ] **Step 2: Run them and see them fail.**

- [ ] **Step 3: Implement**

Routes, inside the admin scope: replace `root to: "pages#index"` with `root to: "dashboard#show"`. `resources :pages, only: %i[index …]` already gives `admin_pages_path`.

```ruby
module Admin
  # CS Studio's start page (dashboard spec §3-§4): "Your work", "On the
  # site" and quick create. Open to every signed-in user -- each list is
  # read-scoped, so someone who can read nothing just sees empty lists.
  class DashboardController < BaseController
    def show
    end
  end
end
```

Point the `MODULES` "Pages" entry at `:admin_pages_path` and add `{ label: "Dashboard", icon: :dashboard, path: :admin_root_path, permission: nil }` first. `PagesController#index`'s fallback `redirect_to(first_admin_module_path)` now lands on the dashboard for someone who can't read pages, which is fine.

- [ ] **Step 4: Run the full suite.** `PARALLEL_WORKERS=1 bin/rails test`

- [ ] **Step 5: Commit** `git commit -m "feat: make the dashboard CS Studio's start page"`

---

### Task 3: `Dashboard::Feed`, the lists and their last actors

**Files:**
- Create: `app/queries/dashboard/feed.rb`
- Test: `test/queries/dashboard/feed_test.rb`

**Interfaces:**
- Consumes: `AccessControl.scope`, `Audit::Event`, `Publishable` (`published_at`), `Media::Asset.kept`.
- Produces `Dashboard::Feed.new(actor:)`, with:
  - `#drafts`, `#scheduled` (mine), `#recently_edited` (mine), `#going_live_next` and `#recently_updated`, each an Array of records;
  - `#last_change(record)` returning `{ actor:, at: }` or nil (from one batched query, run lazily once for every record any list returned);
  - `Dashboard::Feed::LIMITS = { drafts: 10, scheduled: 10, recently_edited: 10, going_live_next: 10, recently_updated: 15 }`.

- [ ] **Step 1: Write the failing tests**

```ruby
# test/queries/dashboard/feed_test.rb
require "test_helper"

class Dashboard::FeedTest < ActiveSupport::TestCase
  setup { @me = users(:one); @other = users(:two) }

  def feed(actor = @me) = Current.set(actor:, channel: :admin) { Dashboard::Feed.new(actor:) }

  test "drafts are my unpublished pages and posts, newest change first" do
    mine = Current.set(actor: @me) { create_post(title: "Mine", published: false) }
    theirs = Current.set(actor: @other) { create_post(title: "Theirs", published: false) }
    theirs.update_columns(author_id: @other.id)
    page = Current.set(actor: @me) { create_page(title: "My draft page", published: false) }

    assert_equal [ page, mine ], feed.drafts
  end

  test "a page someone else edited after me leaves my recently edited but stays in recently updated" do
    page = Current.set(actor: @me) { create_page(title: "Shared") }
    Current.set(actor: @other) { Pages::Save.call(page, translations: { Locales.default => { title: "Shared!" } }) }

    assert_not_includes feed.recently_edited, page
    assert_includes feed.recently_updated, page
    assert_equal @other, feed.last_change(page)[:actor]
  end

  test "scheduled lists are ordered soonest first; going live next covers the whole readable site" do
    soon = Current.set(actor: @other) { create_post(title: "Soon", published: false) }
    soon.update_columns(published_at: 1.day.from_now)
    later = Current.set(actor: @me) { create_post(title: "Later", published: false) }
    later.update_columns(published_at: 3.days.from_now)

    assert_equal [ later ], feed.scheduled
    assert_equal [ soon, later ], feed.going_live_next.first(2)
  end

  test "lists are read-scoped and never show trashed records" do
    hidden = Current.set(actor: @me) { create_post(title: "Hidden", published: false) }
    Current.set(actor: @me) { Trash::Move.call(hidden) }
    assert_not_includes feed.recently_updated, hidden
    assert_not_includes feed.drafts, hidden
    # and an Author scoped to own posts doesn't see another user's draft in going_live_next/recently_updated
  end

  test "a system change reads as no actor; a record with no event has no last change" do
    # Audit an event with actor nil (Current channel :system) and assert last_change[:actor] nil but present;
    # a record created with update_columns/insert (no event) -> last_change nil
  end

  test "limits apply" do
    12.times { |i| Current.set(actor: @me) { create_post(title: "Draft #{i}", published: false) } }
    assert_equal 10, feed.drafts.size
  end

  test "constant query count however many records" do
    counts = [ 1, 20 ].map do |n|
      n.times { |i| Current.set(actor: @me) { create_post(title: "P#{n}-#{i}", published: false) } }
      f = feed
      queries = 0
      callback = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:sql].start_with?("BEGIN", "COMMIT", "SAVEPOINT", "RELEASE") }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        [ f.drafts, f.scheduled, f.recently_edited, f.going_live_next, f.recently_updated ].flatten.each { |r| f.last_change(r) }
      end
      queries
    end
    assert_equal counts.first, counts.last
  end
end
```

In the query-count test, use the repo's existing query-count helper if there is one (`grep -rn "sql.active_record" test`). Write out the two placeholder bodies with real assertions. Images must appear in `recently_updated`/`recently_edited` for a `media.upload` holder, and not for a viewer without it; add that test.

- [ ] **Step 2: Run them and see them fail.** `PARALLEL_WORKERS=1 bin/rails test test/queries/dashboard/feed_test.rb`

- [ ] **Step 3: Implement**

```ruby
# app/queries/dashboard/feed.rb
module Dashboard
  # Every list on the CS Studio dashboard (dashboard spec §4), read-scoped
  # through `AccessControl.scope` -- which already hides trashed records --
  # and built in a constant number of queries: one limited query per list,
  # then ONE batched "newest audit event per record" query for every row
  # any list returned (`#last_change`), plus one actor preload.
  #
  # "Mine": a post I authored, or any page/post/image whose newest audit
  # event is mine. Pages have no author, so for a page only the last change
  # counts -- someone editing it after me takes it off my list (but not off
  # the site's "Recently updated").
  class Feed
    LIMITS = { drafts: 10, scheduled: 10, recently_edited: 10, going_live_next: 10, recently_updated: 15 }.freeze

    def initialize(actor:)
      @actor = actor
      @user = actor.is_a?(ApiToken) ? actor.user : actor
    end

    def drafts = @drafts ||= mine_among(page_and_post_relations { |r| r.where(published_at: nil) }, order: :updated_desc, limit: LIMITS[:drafts])
    def scheduled = @scheduled ||= mine_among(page_and_post_relations { |r| r.where("published_at > ?", Time.current) }, order: :published_asc, limit: LIMITS[:scheduled])
    def going_live_next = @going_live_next ||= merge(page_and_post_relations { |r| r.where("published_at > ?", Time.current) }, order: :published_asc, limit: LIMITS[:going_live_next])
    def recently_updated = @recently_updated ||= merge(all_relations, order: :updated_desc, limit: LIMITS[:recently_updated])

    # The records whose newest audit event has me as actor, newest first.
    def recently_edited
      @recently_edited ||= begin
        events = newest_events_by(@user).first(LIMITS[:recently_edited] * 3)
        records = load_subjects(events.map { |e| [ e.subject_type, e.subject_id ] })
        events.filter_map { |e| records[[ e.subject_type, e.subject_id ]] }.first(LIMITS[:recently_edited])
      end
    end

    def last_change(record)
      @last_changes ||= load_last_changes
      @last_changes[[ record.class.base_class.name, record.id ]]
    end

    # ...private helpers: page_and_post_relations (scoped Page/Post), all_relations (+ Media::Asset.kept if
    # the actor holds media.upload), merge (limit each relation, sort in Ruby, take limit), mine_among
    # (authored posts OR last actor == me, using the batched newest-event lookup over a bounded candidate
    # set), newest_events_by(user) (DISTINCT ON over audit_events where actor is the user, newest first),
    # load_subjects (one scoped query per type), load_last_changes (one DISTINCT ON query over every listed
    # [type, id] + actor preload).
  end
end
```

Fill in the private helpers.
- **Newest event per subject:** use

  ```ruby
  Audit::Event
    .select("DISTINCT ON (subject_type, subject_id) audit_events.*")
    .where(...)
    .order(:subject_type, :subject_id, last_occurred_at: :desc)
  ```

  and preload `:actor` if `Audit::Event` has a polymorphic `actor` association (check the model). Bound every candidate set: "mine" candidates are at most `limit * 3` per relation, merged in Ruby, so query count and memory stay constant. Match the event's `actor_type`/`actor_id` for a `User`; a token's events count for its user (`user_id` column).
- **Audit subject type:** check how `Audit::Event` stores `subject_type` for `Media::Asset` (`LEGACY_POLYMORPHIC_TYPES`), and use the same names.
- **Comments:** keep the class comment, and comment each helper's bound.

- [ ] **Step 4: Run the tests.** `PARALLEL_WORKERS=1 bin/rails test test/queries`

- [ ] **Step 5: Commit** `git commit -m "feat: build the dashboard's lists in a constant number of queries"`

---

### Task 4: Dashboard UI and quick create

**Files:**
- Create: `app/components/admin/dashboard_screen/column_component.rb` + `.html.erb` (titled list + empty state + optional "Show all" link)
- Create: `app/components/admin/dashboard_screen/row_component.rb` + `.html.erb` (thumbnail for images, title, type label, status badge, time, "by …")
- Create: `app/components/admin/dashboard_screen/quick_create_component.rb` + `.html.erb`
- Modify: `app/controllers/admin/dashboard_controller.rb` (`show` builds the feed; `create_draft` action)
- Modify: `config/routes.rb` (`post "dashboard/draft", to: "dashboard#create_draft", as: :dashboard_draft` inside the admin scope)
- Modify: `app/views/admin/dashboard/show.html.erb`
- Test: `test/integration/admin/dashboard_test.rb`, `test/components/admin/dashboard_screen/*_test.rb`

**Interfaces:**
- Consumes: `Dashboard::Feed` (Task 3), `Posts::Save`, `Admin::StatusBadgeComponent`, `Admin::FlashComponent`.
- Produces: `admin_dashboard_draft_path` (POST, params `title`, `content_type`).

- [ ] **Step 1: Write the failing tests**

```ruby
# additions to test/integration/admin/dashboard_test.rb
test "both columns render their lists with labels and links" do
  Current.set(actor: users(:one)) { @draft = create_post(title: "Half-written", published: false) }
  sign_in_as users(:one)
  get admin_root_path
  assert_select "section[aria-labelledby=your-work] a[href='#{admin_post_path(@draft)}']", text: /Half-written/
  assert_select "section[aria-labelledby=on-the-site]", text: /by #{Regexp.escape(users(:one).name)}/   # use the real display-name method
end

test "empty lists say so" do
  sign_in_as users(:reader)
  get admin_root_path
  assert_match "No drafts — start one above.", response.body
  assert_match "Nothing scheduled on the site.", response.body
end

test "quick draft creates a draft and opens it" do
  sign_in_as users(:one)
  assert_difference -> { Post.count } do
    post admin_dashboard_draft_path, params: { title: "New idea", content_type: "blog" }
  end
  post = Post.order(:id).last
  assert_nil post.published_at
  assert_redirected_to admin_post_path(post)
end

test "a blank title re-renders the dashboard with the error" do
  sign_in_as users(:one)
  post admin_dashboard_draft_path, params: { title: "", content_type: "blog" }
  assert_response :unprocessable_entity
  assert_select "[role=alert]"
end

test "the type select lists only creatable types, and a forged type is refused" do
  # Build a group whose posts.create is scoped to content_types: ["blog"], a member user;
  # GET shows only Blog in select[name=content_type]; POST content_type: "now_update" -> 403, no post created.
end

test "New page, Upload image and the audit link follow permissions" do
  sign_in_as users(:reader)
  get admin_root_path
  assert_select "a", text: "New page", count: 0
  assert_select "a", text: "Upload image", count: 0
  assert_select "a", text: /Full audit log/, count: 0
  sign_in_as users(:one)
  get admin_root_path
  assert_select "a", text: "New page"
  assert_select "a", text: "Upload image"
  assert_select "a", text: /Full audit log/
end
```

Write the scoped-type test for real (copy the group setup from `test/services/posts/save_test.rb` or the scoping tests), and match the real display-name method for users. Component tests should cover a row for each type (page, post, image) and the "by System"/no-event cases.

- [ ] **Step 2: Run them and see them fail.**

- [ ] **Step 3: Implement**

```ruby
module Admin
  class DashboardController < BaseController
    def show
      @feed = Dashboard::Feed.new(actor: Current.actor)
    end

    # Quick draft (dashboard spec §4.1): a title and a content type, saved
    # through `Posts::Save` as an unpublished post and opened in the editor.
    # Refusals answer like every admin write (403 via `forbidden_or`);
    # validation errors re-render the dashboard with them inline.
    def create_draft
      result = Posts::Save.call(attributes: { content_type: params[:content_type].to_s, published: false },
                                translations: { Locales.default => { title: params[:title].to_s } })
      if result.ok?
        redirect_to admin_post_path(result.record, **admin_url_options), notice: "Draft created", status: :see_other
      else
        forbidden_or(result) do
          @feed = Dashboard::Feed.new(actor: Current.actor)
          @draft_errors = result.errors
          @draft_title = params[:title]
          render :show, status: :unprocessable_entity
        end
      end
    end
  end
end
```

`QuickCreateComponent` gets the creatable types:

```ruby
ContentTypes.all.select { |type| can?("posts.create", Post.new(content_type: type.name)) }
```

Check the real registry API (`ContentTypes`) and the type label. If no type is creatable, don't render the form. Lay the page out as two columns on wide screens and stacked below `lg`, using the existing admin Tailwind tokens. `ColumnComponent` takes `title:`, `id:` (for `aria-labelledby`), `records:`, `empty:`, `show_all_path: nil` and the feed (for `last_change`).

- [ ] **Step 4: Run the full suite.** `PARALLEL_WORKERS=1 bin/rails test`

- [ ] **Step 5: Commit** `git commit -m "feat: show your work, the site's activity and quick create on the dashboard"`

---

### Task 5: System test, docs and roadmap

**Files:**
- Create: `test/system/admin/dashboard_test.rb`
- Modify:
  - `CLAUDE.md`: a "Dashboard" paragraph under "Admin (CS Studio)"; the time zone in "Auth"/"Admin" or a new short "Site time zone" note; `DashboardController` in the controller list; the root now being the dashboard.
  - `docs/roadmap.md`: tick "Dashboard (drafts, scheduled, recent, quick create)"; resolve the interim state "CS Studio times … are UTC"; add rows for the out-of-scope items (per-user time zones, dashboard customisation and widgets, statistics, an audit-event feed on the dashboard, inline page quick create).
  - `docs/superpowers/specs/2026-09-30-dashboard-design.md`: an "Amendments" section for any behaviour-changing rulings made during implementation.

- [ ] **Step 1: Write the system test**

```ruby
# test/system/admin/dashboard_test.rb
require "application_system_test_case"

class Admin::DashboardSystemTest < ApplicationSystemTestCase
  test "land on the dashboard, quick-draft a post, schedule it and see it go live next in local time" do
    site_settings(:default).update!(time_zone: "Europe/Berlin")
    sign_in_via_form users(:one)
    assert_selector "h1", text: "Dashboard"

    fill_in "Title", with: "From the dashboard"
    press "Create draft"
    assert_text "Draft created"

    visit admin_root_path
    within("section[aria-labelledby=your-work]") { assert_text "From the dashboard" }

    post = Post.find_by!(content_type: "blog") # the newest; use the real lookup by title
    post.update!(published_at: Time.find_zone("Europe/Berlin").local(2030, 7, 1, 9, 30))
    visit admin_root_path
    within("section[aria-labelledby=on-the-site]") { assert_text "09:30" }
  end
end
```

Adjust the field label, the button text and the time format to the real markup.

- [ ] **Step 2: Run the system tests twice.** `bin/rails test:system`

- [ ] **Step 3: Update the docs.**

- [ ] **Step 4: Full verification**

```bash
PARALLEL_WORKERS=1 bin/rails test
bin/rails test:system
bin/rubocop
bin/brakeman -q --no-pager
bin/bundler-audit
bin/importmap audit
bin/rails zeitwerk:check
```

- [ ] **Step 5: Commit** `git commit -m "docs: describe the dashboard and site time zone"` (system test in the same commit or a `test:` commit before it)
