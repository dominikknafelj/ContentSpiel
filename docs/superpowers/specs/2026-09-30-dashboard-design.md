# Dashboard and site time zone

Sub-project 6c of the own-admin roadmap, built after 6b (trash, PR #32). Approved in brainstorming on 2026-09-30. This is the binding spec for the implementation plan.

## 1. Purpose

CS Studio opens on the pages list. It has no place that answers the questions an editor opens it with:
- What was I working on?
- What goes live next?
- What changed lately?

The roadmap row "Dashboard (drafts, scheduled, recent, quick create)" (Should) is still open. So is the interim state "CS Studio times are UTC — no site time zone".

This sub-project:
- makes a **dashboard** CS Studio's start page, with a personal column, a site column and quick create;
- adds a **site time zone** so every CS Studio time, including the dashboard's go-live times, shows in local time.

**Success:**
- After signing in, an editor sees their drafts, their scheduled items and what they edited last, and can start a new post from a title in one step.
- An editor or admin sees what goes live next across the site and what changed recently, and by whom.
- Every list shows only what the viewer may read; trashed items never appear.
- A site set to Europe/Berlin shows and accepts schedule times in Berlin time everywhere in CS Studio.

## 2. Decisions (from brainstorming)

| Topic | Decision |
|---|---|
| Whose view | **Both, in two columns:** "Your work" and "On the site", read-filtered. |
| Start page | **The dashboard is the start page:** `/<admin>` and sign-in land on it, and the pages list moves to `/<admin>/pages`. |
| Quick create | **Quick draft for posts** (title + creatable content type), plus **New page** and **Upload image** buttons. |
| Recent activity | **Recently updated records** with "by <user>" taken from their newest audit event. No audit feed, so no `audit.view` is needed. |
| Time zone | **Site time zone in Settings** (default UTC). All CS Studio times are shown and parsed in it; storage stays UTC. |

## 3. Routes and navigation

- `root to: "dashboard#show"` inside the admin scope (`Admin::DashboardController`).
- The pages list is `resources :pages`' index at `/<admin>/pages` (`admin_pages_path`). Every link, redirect and test that means "the pages list" while using `admin_root_path` switches to `admin_pages_path`, including the trash's post-move redirect and the "back" links. `admin_root_path` then means the dashboard.
- Sign-in, setup completion and the "back to CS Studio" links land on `admin_root_path`, which is the dashboard.
- Sidebar: "Dashboard" is the first entry, visible to every signed-in user (`permission: nil`). The existing entries keep their order.

## 4. The dashboard

### 4.1 Quick create (top bar)

- **Quick draft:** a form with a title field, a content-type `<select>` and a **Create draft** button.
  - The select lists the registered post content types the viewer may create, judged by `AccessControl.allowed?(actor, "posts.create", Post.new(content_type:))` for each type. If there's no creatable type, the form isn't shown.
  - Submitting calls `Posts::Save` with `published: false`, the title in the default locale and the content type. On success it redirects to the post's editor with the flash "Draft created".
  - On failure (a blank title, a refusal) it re-renders the dashboard with the errors inline, status 422. A permission refusal answers like every other admin write: 403 via `forbidden_or`.
- **New page** links to the existing new-page flow. It's shown when `can?("pages.create")`.
- **Upload image** links to the Media module (`admin_media_path`, which has the upload area). It's shown when `can?("media.upload")`.

### 4.2 "Your work" (left column)

"Mine" means:
- **for a post:** `author_id == current user`, or the post's newest audit event has the current user as actor;
- **for a page:** the page's newest audit event has the current user as actor.

| List | Contents | Order | Limit |
|---|---|---|---|
| Drafts | my pages and posts with `published_at IS NULL` | `updated_at desc` | 10 |
| Scheduled | my pages and posts with `published_at > now` | `published_at asc` | 10 |
| Recently edited by you | pages, posts and images whose newest audit event has me as actor | that event's time, desc | 10 |

- Each list ends with a "Show all" link where a filtered list exists (posts index filters). Otherwise there's no link.
- Rows link to the record's editor and show the existing status badge.

### 4.3 "On the site" (right column)

| List | Contents | Order | Limit |
|---|---|---|---|
| Going live next | every readable page and post with `published_at > now` | `published_at asc` | 10 |
| Recently updated | readable pages, posts and images | `updated_at desc` | 15 |

- **Who changed it:** each "Recently updated" row says "by <name>" from the record's newest audit event. It says "by System" when that event's actor is nil, and nothing when there is no event at all.
- **Audit log link:** "Full audit log →" is shown when `can?("audit.view")`.

### 4.4 Visibility and states

- Pages and posts go through `AccessControl.scope(actor, "pages.read"/"posts.read", ...)`, which already excludes trashed records. Images are listed for viewers holding `media.upload` (the library isn't read-scoped), and only kept ones.
- Each empty list shows one sentence instead of an empty box, e.g. "No drafts — start one above." or "Nothing scheduled."
- A user who can read nothing still gets the dashboard. Every list is empty, and quick create shows only what they can do.

### 4.5 Query cost

The dashboard renders in a **constant number of queries**:
- one scoped, limited query per list;
- **one** batched query for the newest audit event of every listed record (`SELECT DISTINCT ON (subject_type, subject_id) … ORDER BY subject_type, subject_id, last_occurred_at DESC` over the listed ids);
- one preload of those events' actors.

"Recently edited by you" is driven from the audit events table: it takes the actor's newest events, deduplicates them by subject, then loads the subjects through the scoped relations. A test pins the query count.

## 5. Site time zone

- **Setting:** `site_settings.time_zone` (string, not null, default `"UTC"`), validated to be an `ActiveSupport::TimeZone` name.
  - Settings shows it as a `<select>` of `ActiveSupport::TimeZone.all` names; autosave goes through `Settings::Save` (`settings.manage`).
  - The `settings.updated` audit event records the change.
- **Use:**
  - `Admin::BaseController` wraps every request in `Time.use_zone(Current.site.time_zone)` (an `around_action`).
  - The MCP controller does the same. MCP dates are emitted as ISO-8601 with an offset.
  - So every time CS Studio shows or parses is in the site zone. That covers the dashboard, the schedule `datetime-local` inputs (value and parsing), "Saved HH:MM", the scheduled hover, the Trash screen, the audit log and token dates.
- **Storage:** stays UTC. The public site shows no times and is unchanged.
- **Parsing:** a schedule time is parsed with `Time.zone.parse`, so a time typed during a DST change follows ActiveSupport's rules: a nonexistent time moves forward, and an ambiguous one takes the first occurrence. There's no extra UI.
- **Roadmap:** the interim state "CS Studio times … are UTC — no site time zone" is resolved.

## 6. Permissions, services, audit

- **No new permission.** Every list is read-scoped. Quick draft uses `posts.create` through `Posts::Save`.
- **No new service.** Quick draft calls `Posts::Save`; the time zone goes through `Settings::Save`.
- **No new audit events.** Quick draft records the usual `post.created`, and the time zone records `settings.updated`.

## 7. Testing

- **Routes:** `/<admin>` renders the dashboard, and `/<admin>/pages` renders the pages list. Sign-in lands on the dashboard. Existing redirects and links that meant the pages list still reach it.
- **Lists:** for each list:
  - contents, order and limit;
  - "mine" semantics, including the author vs. last-actor cases for posts and the last-actor case for pages;
  - read scoping (an Author with own-posts scope; a branch-scoped editor);
  - trashed items never shown;
  - "by <name>" and "by System" labels;
  - empty states.
- **Quick draft:**
  - creates a draft and redirects to the editor;
  - the type select lists only creatable types and is hidden when there are none;
  - a blank title shows the error inline with status 422;
  - a forged type the user can't create gets a 403.
- **Buttons:** New page and Upload image appear only with their permissions. The audit link appears only with `audit.view`.
- **Query count:** constant for 1 vs. 20 records per list.
- **Time zone:**
  - the setting validates;
  - with `Europe/Berlin` set, a scheduled time renders in Berlin time, and a `datetime-local` value round-trips to the right UTC instant;
  - the DST edge (a nonexistent local time);
  - the audit log and trash screen times render in the zone;
  - MCP dates carry the offset.
- **System (Cuprite):**
  - sign in and land on the dashboard;
  - quick-draft a post and see it under Drafts;
  - schedule it and see it under "Going live next" at the local time.

## 8. Out of scope

Recorded in `docs/roadmap.md`:
- per-user time zones;
- dashboard customisation and widgets;
- statistics and counts;
- an audit-event feed on the dashboard;
- quick create for pages inline.
