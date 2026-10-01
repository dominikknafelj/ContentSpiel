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

## 9. Amendments

Behaviour-changing rulings made during implementation (plan `docs/superpowers/plans/2026-09-30-dashboard.md`, ledger `.superpowers/sdd/2026-09-30-dashboard/progress.md`), none of which this spec anticipated in its original text above:

- **"Mine" is computed in SQL, not Ruby.** §4.5 described loading extra candidates and filtering them in Ruby (effectively a `limit * 3` over-fetch) to land on exactly the right page of "my" records. The implementation instead joins each candidate relation to its newest audit event with a `LATERAL` subquery (`Dashboard::Feed#with_newest_event`) and filters *before* the `LIMIT`, in the database. Reasons: a Ruby-side "over-fetch then filter" can still come up short of the list's limit when more than `limit * 3` candidates exist and few of them are mine, and the query-count test requires exactly one query per model per list regardless of how much data exists — the LATERAL join keeps both properties. Cost if this turns out wrong: a per-row correlated subquery on a large drafts/scheduled table costs more than a plan `LIMIT`-then-filter would on a small one; revisit if `EXPLAIN` on a realistic data size shows it.
- **A token-made change reads as its user, not the token.** §4.3's "by <name>" is specified only in terms of "the record's newest audit event" without saying what to show when that event's actor is an `ApiToken`. The dashboard resolves it to the token's own `user` (`Audit::Event#user`, which `Audit.record` fills for both a `User` actor and an `ApiToken` actor) — so a change an AI assistant made through MCP reads exactly like one the same person made by hand in CS Studio. The audit log is still the place to see that a token, specifically, made the change. Cost if wrong: the dashboard can't distinguish an assistant's edits from the person's own at a glance.
- **An unrecognised stored time zone falls back to UTC instead of 500ing.** §5 says `site_settings.time_zone` is validated to be a known zone on save, which is true, but doesn't cover a *previously* stored value that stops resolving later (the zone database changing, a direct SQL edit, a seed/fixture typo) — `Time.use_zone` raises on a name `ActiveSupport::TimeZone[...]` can't resolve, which would 500 every CS Studio and MCP request behind `Admin::BaseController`/`McpController`'s own `around_action`. `SiteSetting#effective_time_zone` (not the bare `time_zone` attribute) is what every time-zone-aware call site now reads, and it falls back to UTC rather than raising. Found and fixed during Task 1's review, before this ruling was written down elsewhere, so it's recorded here for the historical record.
- **"Show all" opens the status-filtered posts list, not a dedicated dashboard list view.** §4.2/§4.3 call for a "Show all" link "where a filtered list exists" without naming the destination. It's `admin_posts_path(status:)` — the posts index's own existing status filter — for Drafts, Scheduled and Going live next; there's no "Show all" for Drafts/Scheduled's page-tree counterpart (pages have no equivalent filtered list) or for Recently edited/Recently updated. It shows every readable post in that state, not only mine, and not pages — the fuller list, not the same list made longer.
- **"By <name>" is the user's email address.** §4.3 says "by <name>" without defining what "name" means for a `User`, which has no name column (only `email_address`). Every "by" label on the dashboard reads the email address of the newest event's user (`user_id`). *Corrected in the final fix wave (M4):* `audit_events` has no foreign key on `actor_id`/`user_id`, so the event still knows who acted after the account is gone. The label is now: nothing for a record with no event; "by <email>" when `user_id` names an existing user (including a change made through a token deleted since); "by a deleted user" when `user_id` names a user who no longer exists; and "by System" only when the event has no `user_id` at all (a nil actor on a trusted channel).
- **A refused attempt is not a change (final fix wave, I1).** `ApplicationService#denied` records `access.denied` with the refused record as its subject, and those events coalesce — so taken literally, "the newest audit event" let a user who was merely refused on someone else's page take it over in "mine", "Recently edited by you" and the "by" label. Both places that decide the newest event (the `LATERAL` join and the batched `DISTINCT ON`) exclude `access.denied` (`Dashboard::Feed::NOT_A_CHANGE`), so they always agree.
- **Content-block edits count as edits of their owner (final fix wave, I3).** A block event's subject is the block, so block edits were invisible to the dashboard. Now (a) `ContentBlocks::Save`/`Destroy`/`Reorder` `touch` the owning page or post inside their transaction — `touch` runs no validations and no save callbacks, so a page's path/hierarchy rebuild doesn't run, and `PublicSite.content_version` moves with the owner's `updated_at` — so "Recently updated" bumps; and (b) a page's or post's newest event is the newer of its own and those about any block it *currently* owns, in both the `LATERAL` join and the batched query, so "mine", "Recently edited by you" and "by" reflect block edits. An edit to a block deleted since only shows through the owner's `updated_at` (the block row that would lead back to the owner is gone). Because the touch moves the page's `updated_at`, every block response also streams the page settings form's fresh `base_updated_at`, so that form's next autosave on the same screen isn't reported as "Changed elsewhere".
- **The stored time zone is normalised to a Rails name (final fix wave, I2).** §5 allowed an IANA identifier, but the Settings select's option values are Rails names: a stored `"Europe/Berlin"` matched no option, the browser showed the first one, and the next autosave of any field (the form resends everything) silently saved "International Date Line West". `SiteSetting` now normalises an IANA identifier to its Rails name before validation (`ActiveSupport::TimeZone::MAPPING.key`), validates against Rails names only when the value changes, and the select always includes the stored value as its selected option, so a value written around the model is resent unchanged.
- **"Recently edited by you" scans readable records, not the actor's events (final fix wave, M8).** §4.5 says the list is driven from the audit events table — the actor's newest events, deduplicated, then loaded through the scoped relations. It is instead computed like the other lists: each scoped relation is joined to its records' newest event with the same `LATERAL` subquery, filtered to the viewer, ordered by that event's time and limited. That keeps "mine" identical across lists and the query count constant, at the cost of probing every readable record; an index on `audit_events (subject_type, subject_id, last_occurred_at DESC)` (migration `20260930110000`) makes each probe an index read.
- **Public-site dates stay UTC (final fix wave, M6).** `ThemeHelper#post_date` on the public site and `/preview` runs outside `Time.use_zone`, as §5 intended ("the public site is unchanged"). Showing them in the site zone needs the render cache to vary on the zone; recorded in `docs/roadmap.md`.
