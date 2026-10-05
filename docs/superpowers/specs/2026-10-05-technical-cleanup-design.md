# Technical cleanup

A sub-project slotted before the Mind graph on a canvas and the block and type catalogue. The design was agreed with the user on 2026-10-05 in three sections. This is the binding spec for one implementation plan and one PR.

## 1. Purpose

Some of the technical debt in `docs/roadmap.md` costs the same whenever it is paid. Some of it costs more with every feature added on top. This sub-project pays the second kind now:

- The system tests hide two classes of bug (JavaScript errors, covered buttons) and flake on fixed sleeps, and every new test is built on that base.
- New admin strings are written as inline English because no key scheme exists.
- Nothing enforces which layer may know which, so each feature can add another dependency pointing the wrong way.
- The service contract is checked by reading source text, which a service can satisfy without being correct.
- Access-control data can be in shapes the screens can't show (two grants for one permission) or can hand on a right its giver doesn't hold (a dormant removed-type name). With no production data these are simple migrations.
- Every page save re-derives the URLs of its whole subtree, and any write, a draft autosave included, moves the public cache key. The demo data set planned next would run straight into both.
- `app/javascript/autosave/queue.js` and `CLAUDE.md` grow with every round.

**Success:**
- A system test fails when the page throws a JavaScript error or when a button it presses is covered by another element, and no system test waits on a fixed sleep without a stated reason.
- Every service is proven by behaviour to refuse an actor with no grants, audit the refusal once and change nothing.
- A guard test fails when a model, query or service references a component, a helper or a route helper.
- The i18n key scheme is written down and proven on the shared components and one whole screen.
- A group holds at most one grant per permission; a right can't be handed on by someone who couldn't grant it; two admins can't silently overwrite each other on a group or a user.
- A page save that changes no URL-relevant field syncs no URL, and a draft autosave doesn't move the public content version.
- Nothing an editor can do today is lost. The behaviour changes editors can notice are listed in §6.

## 2. Decisions

Agreed on 2026-10-05:

| Topic | Decision |
|---|---|
| i18n depth | **The scheme plus a reference conversion**: the shared components and the Tags screen. Every other screen is converted in the German UI sub-project. New work uses keys from this point on. |
| Packaging | **One PR**, with the test and structure work ordered before the data work (§5). |
| `CLAUDE.md` | **Rules stay, descriptions move to `docs/reference/`** behind an explicit index. Every pitfall that has caused a bug stays in `CLAUDE.md` itself. |
| URLs and the content version | **Stay in the models, made conditional, for now** (§4.7, §4.8). Moving their maintenance into the services is revisited with the caching sub-project, when the version row gets its second consumer. |
| A stale group or user save | **Refused with a 409**, never merged. |
| Existing API tokens | **Revoked by the migration** and reissued by hand, because only their bcrypt hash is stored (§4.5). Acceptable with no production. |

## 3. Tests, structure, i18n, docs

### 3.1 System tests fail on JavaScript errors

`test/application_system_test_case.rb` runs Cuprite with `js_errors: false`, because Turbo throws one harmless error: an `AbortError` that escapes when a `<turbo-frame>` is disconnected mid-load.

- Turn `js_errors` on.
- Filter exactly that error, identified by its name and by coming from an aborted frame fetch, in one place with a comment that says why.
- Every other error the suite then surfaces is either fixed in the application or, if it is noise the application can't prevent, added to the filter with a written reason.
- **Stop rule:** if more than twelve distinct errors surface, stop and show the user the list before fixing further.

### 3.2 Native clicks by default

`press(label)` clicks through `element.click()`. A scripted click succeeds on a button another element covers.

- `press` becomes a native click.
- A second helper with a name that says what it does (`press_by_script`) remains for the cases a native click can't serve: an element inside a closed menu that the test opens by other means, and a control revealed only by a `hover:` style, which CI's headless Chrome never shows. Each use carries a comment giving its reason.
- `press_insert` and the other helpers that click by script are reviewed the same way.
- A press that now fails because the element is covered or off-screen is a finding: fix the layout, or the test's setup if the test was wrong.

### 3.3 No fixed sleeps

There are 57 `sleep` calls in `test/system`.

- Each becomes a wait on a condition: a waiting Capybara assertion, the shared `click_frame_link` helper, or a flag a test stub sets (the pattern `promotion_hold_test.rb` uses with `hold_frame_fetches` / `release_frame`).
- A sleep that proves an absence ("nothing happened within N ms") stays only where no event marks the end of the window, and carries a comment.
- A guard test in `test/lib` fails on a `sleep` in a system test unless the same line ends with a `# sleep:` reason.

### 3.4 The service contract, by behaviour

`test/services/service_contract_test.rb` reads the file `#call` lives in and looks for `authorize!(` and `record_event(`. One `# audit: none` comment skips both checks.

- Keep the grep as a tripwire, with the two exemptions separated: `# audit: none (reason)` skips only the audit check, `# authorize: none (reason)` only the authorisation check.
- Add a behavioural contract: for every `ApplicationService` subclass, a generated test calls it as a user with no grants on the `:admin` channel and asserts it answers `denied?`, records exactly one `access.denied` event, and changes nothing: the row counts of the tables the service writes and the attributes of its subject are the same before and after.
- Each service gets a small factory entry (the arguments for a valid call) in one file; a service without an entry fails the contract test, so a new service can't be added without one.
- Services that are open to any signed-in user by design (for example a user changing their own password or profile) are listed with their reason and tested for their actual rule instead.

### 3.5 Dependency direction

`CLAUDE.md` states the order: models, queries and services know nothing of components, helpers or controllers. Three inversions remain.

- `RichText::BuiltIns` / `RichText::HtmlRenderer` render components through `ApplicationController.render` from a model. The renderer takes a rendering callable from its caller instead; the default for callers that don't pass one lives outside `app/models`.
- `StarterContent` (a model) calls `Pages::Save`, `Posts::Save` and `ContentBlocks::Save`. The orchestration moves into the `StarterContents` service that already exists; the model keeps the data.
- `Media::Asset#url` and its neighbours, `Jump::Search` and `PostGraph` use route helpers. They return what a URL is built from (a route name and parameters, as `Audit::Sentence` does); the component or controller resolves it.

Then a guard test in `test/lib`: no file under `app/models`, `app/queries` or `app/services` references a `…Component` constant, `helpers`, `url_helpers`, a `_path` / `_url` route helper, `content_tag`, `link_to` or `html_safe`. The one named exception is a content or block type definition registering its components. The test's allow-list is empty apart from that.

### 3.6 The i18n key scheme and its reference

**The scheme**

- Admin strings live under `config/locales/admin/`, one file per screen (`tags.en.yml`, `components.en.yml`), all under the top-level key `admin`.
- A view's keys mirror its path, so Rails' lazy lookup works: `t(".title")` in `app/views/admin/tags/index.html.erb` reads `admin.tags.index.title`.
- A component's keys live under `admin.components.<component path>`: `Admin::ConfirmDialogComponent` reads `admin.components.confirm_dialog.cancel`. Components get one small lookup helper so a component writes `t(".cancel")` too.
- Strings a script shows (a toast, "Uploading…", a live-region announcement) are rendered by the server into data attributes or `<template>` elements and read from there. No user-visible English in a `.js` file.
- Counts use Rails pluralisation (`one` / `other`), never a hand-built "1 post / 2 posts".
- A string with a name or a number in it is one key with interpolation, never a sentence glued from parts, so a translator can reorder it.
- Flash and toast texts set in controllers use the same files, under the controller's own key.

**The reference conversion**

- The shared components: buttons, dialogs and confirm dialogs, toasts, the save footer and its leave dialog, status and translation chips, language tabs, pagination, time-ago, empty states, the error summary, the chip input.
- The Tags screen end to end: the list, inline rename, the row menu, the Merge and Delete dialogs with their counts, the controller's toasts and the strings `admin--tag-dialogs` shows.
- A guard test keeps those files free of inline English: in the converted templates and components, text nodes and the string attributes that carry copy (`aria-label`, `title`, `placeholder`, button labels) must come from a lookup. The list of converted files lives in the test and grows with the German UI sub-project.

**Named as out of scope:** every other screen; and the sentences built in Ruby (`Audit::Sentence`, `Post.human_attribute_name` / `ContentBlock.human_attribute_name`, the denial message in `ApplicationService`). The scheme document says how those will be handled (one key per whole sentence with interpolation), but they are not converted here.

### 3.7 Splitting `queue.js`

`app/javascript/autosave/queue.js` is 917 lines and holds four jobs. It becomes modules under `app/javascript/autosave/`, each with one job and its own header comment:

- the queue itself (one write at a time, bases refreshed at send time, `drained()`);
- the frame-navigation hold and the stale-answer refetch;
- the promotion hold;
- the page-generation bookkeeping they share.

No behaviour changes. The existing system tests pass unchanged; an edited assertion needs a stated reason. The importmap pins keep `preload: "admin"`.

### 3.8 Splitting `CLAUDE.md`

`CLAUDE.md` is about 143 KB and loaded whole into every session.

- **Stays in `CLAUDE.md`:** what the repo is; setup and commands; the test rules and traps; "Key Conventions" including the dependency order and the namespace rules; every pitfall that has shipped as a bug (two pages on one URL, nil positions, the namespace shadowing, the Accept-header 500, the promoted-visit trap in tests); and an index.
- **The index** is a list of rules of the form "Before changing X, read `docs/reference/<topic>.md`", one per topic, each naming the directories it covers.
- **Moves to `docs/reference/`**, content unchanged: the page tree and public routing; content blocks and types; CS Studio's shell and dashboard; the design system and shared components; the save rule and the write queue; the editors and translation pair; Settings, Languages and AI; media; trash; access control and audit; users, groups and tokens; rich text; translations.
- A check script (run once, its output in the PR) confirms that every sentence of the old `CLAUDE.md` exists in the new `CLAUDE.md` or in exactly one reference file, so the move loses nothing and duplicates nothing.
- The reference files are verified against the code where this sub-project changes what they describe.

## 4. Data and write paths

### 4.1 One grant per permission in a group

`access_control_grants` has a non-unique index on `(group_id, permission)`, while the group editor shows one grant per permission and a save from the screen drops a second one.

- A migration merges duplicates, then replaces the index with a unique one.
- Merging: grants combine with OR, so two grants for one permission become one whose scope grants what the pair granted. Where one of them is unscoped, the result is unscoped. Where both are scoped on the same keys, the lists are united. Where they are scoped on different keys (one by content type, one by `own`), no single scope expresses the pair exactly; the migration keeps the wider reading and reports each such group by name in its output.
- `AccessControl::Grant` validates the uniqueness so a violation is a validation failure, not a database error.
- `Groups::Save#live`'s greedy matching can no longer meet two stored grants for one permission; its claim bookkeeping is simplified accordingly.

### 4.2 Dormant removed-type names judged as stored

`AccessControl.can_assign_group?`, `can_manage_group?` and the member loop in `Groups::Save` judge a group's grants through `LiveGrants#entries`, which strips unregistered content-type names. A name that is stripped grants nothing today, but it revives if a type of that name is registered again, and someone who couldn't grant it can hand it on with a membership or a token.

- The three places judge the grants as stored (`carried_attributes`): a grant whose scope names a type the actor couldn't grant is one the actor couldn't hand out, registered or not.
- `Groups::Save#live` keeps its one exemption: a posted grant that is exactly a stored grant, carried name included, is unchanged.
- `AccessControl.holds?` stops counting a grant whose content types are all unregistered, so its holder no longer sees a Posts entry leading to an empty list.

### 4.3 No lost updates on groups and users

`Groups::Save` replaces all grants and members; `Users::Save` replaces a user's groups. Neither form carries a stale check.

- Both forms carry `base_updated_at` (ISO 8601 with microseconds), as the Settings form does.
- A save whose base is older than the record as loaded is answered 409 before any service is called: nothing is written or audited, and the form re-renders with the typed values and the banner Settings uses, naming who changed the record when the audit log says.
- `Groups::Save` touches the group when it changes grants or members, and `Users::Save` touches the user when it changes groups, so the base moves on every kind of change. A membership change touches both sides: the user form changing a user's groups touches each group gained or lost, and the group form changing members touches each user added or removed. Otherwise the other screen's open form would save an old list over the new one.
- A blank or unparseable base is not stale, as elsewhere.
- The owner endpoint and the delete zones are single actions and carry no base.

### 4.4 The owner flag through one door

- `:owner` leaves `user_params`. `PATCH users/:id/owner` is the only request that changes it.
- `Users::Save#owner_change?` treats a blank or absent value as no change.
- A forged `user[owner]` in the ordinary form is therefore ignored where it was refused; the endpoint still refuses a non-owner with one `access.denied`. The tests that pinned the 403 on the ordinary form move to the endpoint.

### 4.5 API token lookup by digest

`ApiToken.authenticate` compares the presented token against every active token with bcrypt. Cost grows with the number of tokens and an unauthenticated caller pays it.

- A token is random and high-entropy, not a password, so a fast digest is the appropriate lookup. Add `api_tokens.lookup_digest` (SHA-256 of the raw token, hex), not null, with a unique index. `authenticate` computes the digest, finds the row by index among active tokens and compares in constant time.
- `has_secure_password :token` and `token_digest` are removed in the same migration.
- Existing tokens can't be converted. The migration revokes every active token (`revoked_at`), fills `lookup_digest` with a value that can never match, and reports how many it revoked. The AI assistant screen already shows revoked tokens and how to issue a new one.
- `Audit::Snapshot::NEVER_STORED` and the parameter filter cover the new column name.

### 4.6 Language changes under a row lock

`Locales::Enable`, `Disable`, `MakeDefault`, `Configure#apply` and `Settings::Save` read `site_settings.locales`, change it in memory and write it back. Each locks the row (`lock!`) at the start of its transaction, then reads. A test runs two changes against one row in sequence on stale copies and asserts neither is lost.

### 4.7 URLs synced only when they can have changed

`Page` and `Post` call `PublicSite::Paths` from `after_save` on every save. A homepage autosave therefore re-derives every page and every listed post inside its transaction.

- **Skip when nothing relevant changed.** A page's URL depends on its slug (per language), parent, position, publication and trash state; a post's on its slug, content type, tags, publication and trash state. The model captures those values in `before_save`, because closure_tree's reload clears the dirty flags, and compares after. No difference, no sync. A new record always syncs.
- **Set-based when it runs.** `sync_subtree` loads the subtree and its stored `public_paths` rows in two queries, computes the new paths in memory and writes only the rows that differ. `sync_posts` computes `canonical_pages` once per batch instead of once per post per language.
- **The other callers** (a listing block's save and destroy, `Tags::Rename`, `Tags::Destroy`, `Tags::Merge`, `Locales::Enable`) keep calling the same entry points and get the set-based path.
- **Guarantees re-proven** by the existing tests plus new ones: no `(locale, path)` with two current rows; an old URL becomes a redirect; a trashed record's rows are deleted and nothing resurrects them; `bin/rails`-level rebuild (`PublicSite::Paths.rebuild!`) still produces the same table as the incremental path, asserted by a parity test over a tree with moves, renames, trashes and restores.
- **Query-count tests at two sizes:** a homepage save that changes only the title issues no `public_paths` query; a slug change on a page with 20 and with 200 descendants costs the same number of queries.

### 4.8 A content version that moves only on published changes

`PublicSite.content_version` is 14 aggregate queries per public request plus `Current.site.updated_at`, and any write moves it. It is the public ETag and part of every rich-text render cache key.

- **One row** in a new table `public_site_versions` holds an integer counter. It is not a column on `site_settings`, because that row's `updated_at` is the Settings form's stale-check base.
- **Bumped in `after_commit`** by an atomic increment, only by changes that can affect published output:
  - a page or post that is live before or after the change (so publishing, unpublishing, trashing, restoring and editing a live record all bump; editing a draft does not);
  - a content block whose page is live;
  - a `public_paths` row created, changed or deleted;
  - a library image created, changed, trashed or purged, and a processed image variant;
  - the site settings row;
  - a tag renamed, merged or deleted, and a post's tags changed on a live post.
- **Scheduled go-lives** involve no write. The version therefore also carries the newest `published_at` that has already passed, for pages and for posts: two indexed lookups. `PublicSite.content_version` is then three queries.
- **Conservative by rule:** where it is unclear whether a change can be seen, it bumps. A test enumerates every model the old aggregate covered and asserts that a visible change to each bumps the counter and that a draft-only change does not.
- **By hand:** `bin/rails public_site:bump_version` for a console change or a restored backup.
- **S8:** `PagesController#show` runs its record and image preload after the `stale?` check, so a 304 no longer pays for it.
- **Memoisation:** `RichText::Schema.version` and a document's digest are memoised per request rather than recomputed on every `to_html`.

### 4.9 Indexes

`published_at` and `updated_at` on `pages` and `posts`; `block_type` on `content_blocks`. The `published_at` indexes are what §4.8's two lookups use.

## 5. Order

One PR. The plan's tasks follow this order, each reviewed on its own:

1. JavaScript errors on (§3.1).
2. Native clicks (§3.2).
3. No fixed sleeps, with the guard (§3.3).
4. The behavioural service contract (§3.4).
5. Dependency fixes and the guard (§3.5).
6. The i18n scheme document and the shared components (§3.6).
7. The Tags screen converted, with the guard (§3.6).
8. `queue.js` split (§3.7).
9. The unique grant index and its migration (§4.1).
10. Dormant names judged as stored (§4.2).
11. The stale check on groups and users (§4.3).
12. The owner flag (§4.4).
13. Token lookup by digest (§4.5).
14. The language row lock (§4.6).
15. URL sync (§4.7).
16. The content version and indexes (§4.8, §4.9).
17. `CLAUDE.md` split (§3.8), after the tasks above have updated the text it moves.
18. Sweep: the roadmap rows this closes, the reference files checked against the code, static checks, the suites.

Tasks 10, 15 and 16 are done and reviewed on the stronger model.

## 6. What editors and admins can notice

- A group that still carries a removed content type becomes view-only for a manager who couldn't grant that type, until an owner or an unscoped holder presses Remove on it (§4.2).
- The second of two admins saving the same group or user gets "changed elsewhere" and must reload (§4.3).
- Every existing API token stops working and must be reissued (§4.5).
- Nothing else: the same screens, copy and permissions.

## 7. Proof

- **Behaviour changes** (§4.1–§4.6) are written test-first: the test fails on the old code.
- **Refactors without behaviour change** (§3.5, §3.7, §3.8) are proven by the existing suites passing unchanged.
- **Performance changes** (§4.7, §4.8) are pinned by query-count tests at two sizes, so a per-row cost can't hide under a ceiling.
- **Migrations** (§4.1, §4.5) are tested against prepared data.
- **Before the PR:** the unit suite, the system suite three times in a row, rubocop, brakeman and both audits, run by the controller session, with every failure named.

## 8. Out of scope

- A whole-page cache, a Clear cache button, CDN settings, per-page cache lifetimes, image proxy mode: the caching sub-project, which also revisits moving URL and version maintenance into the services.
- Converting the rest of the admin to translation keys, and the German translations themselves: the German UI sub-project.
- Observability, the pre-launch checklist, a script CSP with nonces.
- The polish backlog and the write-queue follow-ups listed in the roadmap.
- Lazy-loading Tiptap and d3-force (the latter with the Mind graph on a canvas).
- Sibling positions that can't collide, and an atomic stale-autosave check.

## 9. Risks

- **JavaScript errors on** may surface more real errors than expected. The stop rule in §3.1 bounds it.
- **Native clicks** may expose covered or off-screen controls. Each is a real defect; a large number would stretch task 2, and the same stop rule applies at twelve.
- **URL sync** is the code with a history of shipped bugs (`da80c58`). It runs late, on the hardened suite, with the parity test against a full rebuild as its safety net.
- **A missed version bump** leaves a stale public page. The rule is conservative, the enumeration test covers every model the old aggregate read, and the rake task bumps by hand.
- **The `CLAUDE.md` split** depends on sessions following the index. Pitfalls with an incident history stay in `CLAUDE.md` for that reason.

## 10. Amendments from the code inventory

Reading the code for the plan (2026-10-05) corrected the following. Where this section and the text above disagree, this section wins.

- **§3.1, how an error fails a test.** Cuprite's `js_errors` is all or nothing, and when on it raises asynchronously in the main thread, wherever the test happens to be. The driver option stays off. A module prepended to `Ferrum::Page` listens for `Runtime.exceptionThrown`, drops the filtered error and collects the rest; the test's teardown fails with the collected errors. The failure is attributed to the test, at a fixed place.
- **§3.2, §3.3, counts.** 198 `press` lines and 21 `press_insert`; 59 sleeps, of which about 28 prove an absence, about 8 sit inside hand-rolled wait loops, a handful are wall-clock preconditions and a handful hold a stub provider open.
- **§3.3, replacements by kind.** A wait loop becomes the one shared `assert_eventually` (three incompatible copies exist today). "Nothing was saved" waits on the write queue's `settled()` and then asserts no write. A wall-clock precondition becomes an explicit timestamp or `travel_to` (the server runs in the test process). A stub provider's delay becomes a gate the test releases.
- **§3.4, exemptions.** `Posts::Bulk` and `Posts::BulkRestore` return their own result type and treat an unreadable id as not found; they are tested for that rule. `ApiTokens::Issue`, `ApiTokens::Revoke`, `Users::UpdatePassword` and `Users::UpdateProfile` are open to a signed-in user for their own record and are tested for that rule. No fixture user has no grants and no group; the contract creates one.
- **§3.5, what the guard forbids.** References to a `…Component` constant, `ApplicationController`, `ActionController`, `url_helpers` and `Rails.application.routes` under `app/models`, `app/queries` and `app/services`. Route names handed up as symbols (the `Audit::Sentence` pattern) are allowed. Two named exceptions besides the type definitions: `RichText::HtmlRenderer` and `RichText::BuiltIns` build HTML strings with Action View's tag helpers, which is their job, but no longer render components through a controller; and `Media::Asset`'s URL methods use Active Storage's own URL helpers, which address stored files rather than application routes. `Setup` (a model) also reaches the save services through `StarterContent`; that call moves with the rest.
- **§3.6.** ViewComponent's built-in lookup resolves `t(".x")` in `Admin::ConfirmDialogComponent` to `admin.confirm_dialog_component.x`, so the lookup helper on the admin components' base class is required to get `admin.components.confirm_dialog.x`. `raise_on_missing_translations` is switched on in the test environment, so a mistyped key fails a test. Dates in the converted components go through `I18n.l` with named formats. The messages `Tags::Merge` returns are looked up from the Tags file. The leave dialog lives in the admin layout and is converted with the save footer. How CS Studio chooses its own UI language is the German UI sub-project's decision; this sub-project runs the admin in English.
- **§3.8.** `CLAUDE.md` is split by paragraph, and where a pitfall is the last sentence of a description paragraph, by sentence. The check compares sentences.
- **§4.1, enforcement.** The database index is the guarantee. `Groups::Save` refuses a request that lists one permission twice. There is no model-level uniqueness validation, because `Groups::Save` validates the new grants before it deletes the old rows. Tests that relied on two grants for one permission in one group are rewritten (grants still combine with OR across a user's groups).
- **§4.3, the banner.** Groups and users get the Settings pattern: a fixed message and a Reload link. It does not name who changed the record; only the autosave editors' notice does.
- **§4.3, what touches.** `Groups::Destroy` and `Users::Destroy` touch the other side's records they detach.
- **§4.4.** "No change" is a nil or an empty-string `owner` value, not `blank?`, since `false` is a real value.
- **§4.5.** `lookup_digest` is added to `Audit::Snapshot::NEVER_STORED`; the parameter filter doesn't match the name by itself. The existing token-name migration test is updated for the dropped column.
- **§4.6.** In each service the lock is the first statement of the transaction, and the checks and the in-memory computation that read `locales` move inside, after it.
- **§4.7.** `HasPublicPaths`' availability validation computes paths on every validation; it gets the same skip.
- **§4.8, writers around callbacks.** Many writes use `update_all`, `update_columns`, `touch_all`, `insert_all` or `delete_all` and fire no `after_commit`. The bump is therefore one method, `PublicSite.bump_version!`, called from the models' `after_commit` and explicitly from each service that writes around callbacks. A guard test fails on such a write to a version-relevant table in a file that neither bumps nor carries a `# version: none (reason)` comment. Processed image variants bump through a hook on `ActiveStorage::VariantRecord`.
- **§4.8, the rule for "live".** A page, post or block bumps when its own publication time is in the past before or after the change, whatever its ancestors' state: more bumps than strictly needed, never fewer.
- **§4.8, readers.** `RichText::RenderContext` reads the version by default for every render, in preview and MCP too; it stays, at three memoised queries per request.
