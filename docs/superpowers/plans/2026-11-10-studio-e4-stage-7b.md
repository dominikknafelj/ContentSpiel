# CS Studio in E4, Stage 7b (people and system) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** These screens take E4:
- Users and invites, Groups with the permission matrix, the AI assistant (API tokens), Your account and System status;
- sign-in, the password reset, the invitation, the 403 and the 404;
- the mails, in their reduced form.

Each list is a heading and one card holding a real table. Every configuration form is drawn in the Settings card frame. Every hand-written alert box becomes one shared notice. Four zones that each do one job, and two copy scripts that do one job, each become one. Every word these screens still say in English becomes a key. The mails gain one violet button.

**Architecture:**
- The looks that two or more parts now share become shared parts in `app/components/admin/ui/`, each with the full contract:
  - `Admin::Ui::NoticeComponent` draws every alert box in the flow of a screen (the artifact's Alerts, Gap 2, decided by the owner).
  - `Admin::Ui::ActionZoneComponent` is the instant action after a form: the users' delete and owner zones, the groups' delete zone and the forms builder's trash zone (Q3).
  - `Admin::Ui::CopyValueComponent` is a value with a Copy button. The tokens' three boxes and a system check's command draw it, on the one copy script, `admin--ui--clipboard` (Q5).
- Two stylesheet classes and two small changes:
  - `.admin-row-link` stretches a row's one link over its row (Users, Groups, the audit log).
  - `BadgeComponent` gains a `mark` slot, so a scope chip is a badge.
  - `.cs-checkbox:disabled` loses its opacity.
- No query, service, route, model or permission changes. The only Ruby beyond components is three things:
  - the controllers' flash words become keys;
  - `Setup::SystemCheck` stays English (named out of scope in `docs/reference/i18n.md`);
  - the shared `setup/_system_check_results` partial takes its list's class from its caller.

**Tech Stack:** Rails 8.1, ViewComponent 4.23 with Lookbook previews, Tailwind v4 (`tailwindcss-rails`), Turbo, Stimulus over import maps, Minitest with Capybara on Cuprite 0.20, Action Mailer.

**Spec:** `docs/superpowers/specs/2026-11-06-studio-e4-design.md` (approved 2026-11-06). The sections used:
- "Decided on 2026-11-06", decision 5 (the mails);
- "The design, as decided": the tokens, the radii, one type voice, the buttons, the four roles and status;
- "Every screen, and its stage": the rows marked 7b;
- "The rule for a screen the artifact does not draw", rules 1 to 6;
- "Stage 7", the bullet 7b and "Mails, a reduced E4";
- "Architecture-review findings", "The guard after E4" and "Constraints".

The drawing is the Design System artifact (https://claude.ai/artifact/Pg9o6tAeyWk98YFsrMmXxT) at version `1794290753-3cf0` (v177). The design agent answered Q1–Q11 on 2026-11-10 (answers: `/private/tmp/claude-501/-Users-dknafelj-src-ContentSpiel/dd7bb8f3-e1e2-40d2-a449-0b6c377c5f48/scratchpad/design-answers-7b.md`): every recommendation accepted, except Q2's invitation circle (below). It drew the 7b screens as Decided, not built: StudioUsers, StudioGroups, StudioTokens, StudioAccount, StudioSystemStatus, StudioSignIn, StudioErrors, with ActionZone and CopyValue, and redrew PatternDestructiveActions (no box), Mails (decision 5) and Alerts (the sweep reaches the editor's boxes). Where this plan says "recommended answer assumed", the answer is now decided. What it decides for 7b is also on these cards:
- `Alerts` (Gaps 1 and 2);
- `PasswordField` (Gaps 1 and 2);
- `StudioListTable` (the users list's gaps);
- `PatternDestructiveActions` (the group delete zone's keys);
- `FormControls` (Gap 1);
- `StudioEmptyState` (the tokens' keys);
- `Mails`.

Every look the artifact does not decide is a question in `.superpowers/7b-design-questions.md` (Q1–Q11, git-ignored). Implementers do not read or edit the artifact. It belongs to the design agent.

**One pull request** on branch `studio-e4-7b`, made from `main` at d99b0dc1, targeting `main`.

---

## Design answers (assumed, pending the owner)

The questions file holds Q1–Q11, each with a recommended answer. **Until the owner answers, each step that depends on a question is marked "(per Qn, recommended answer assumed)".** An answer that differs from the recommendation is written back into this section, and into each step it changes, before that task starts. In short:

- **Q1, the lists.**
  - No filter bar.
  - The heading row: `text-h1`, the intro in `text-small dim`, and the actions on the right, wrapping under the heading below 640px.
  - One card holding a real `<table>` in `.admin-table-scroll--x`, with the first column sticky and the head `text-label meta` over `line-strong`.
  - A row that opens an editor has its name as `.admin-row-link`, ends in `.admin-row-verb` "Edit", and is `paper` under the pointer.
- **Q2, a user's row.**
  - `AvatarComponent :md`: `:own` for you, `:other` for anyone else, `:other` for an open invitation too, told apart by its "Invited" / "Invite expired" badge (decided: the dashed edge means away, and someone not yet in is not away).
  - The badges: Owner, Invited, Invite expired.
  - A group is a `BadgeComponent :neutral`. No groups reads "No groups".
- **Q3, the zones.** `ActionZoneComponent`: a `line` rule above, `pt-4`, no box; the `text-h3` heading, the `text-small dim` cost and reason, the pending-lock hint and the trigger slot. A built-in group's note is `NoticeComponent :neutral`.
- **Q4, the auth pages.**
  - A `surface` panel at `shadow-2` and `rounded-rail`, `p-8` (`p-6` below 480px), in a 420px column.
  - The heading `text-h1` at 600, the alerts `NoticeComponent` `:compact`, and the secondary links tertiary small.
- **Q5, the AI assistant.**
  - Two step cards. "Create token" is the one primary.
  - The reveal is a warn notice holding the token's `CopyValueComponent`.
  - The status is `StateChipComponent` (ok "Active", off "Revoked" with a time). A revoked row's words are `meta`, with no opacity.
- **Q6, the group editor.**
  - Three `SettingsCardComponent` cards: "Group" (`groups`, `people`), "Content permissions" (`pages`, `structure`) and "Other permissions" (`settings`, `neutral`). The last is one card with area bands.
  - The scope editor is indented to the label column.
  - A scope chip is a `BadgeComponent`, with a `mark` for the type dot. A stale note is a warn notice.
- **Q7, the user editor.**
  - "Details" (`user`, `people`) and "Groups" (`groups`, `people`, with "Manage groups →" in `head_end`).
  - The group cards are `.admin-tile`: ticked takes the selected outline, a group the viewer can't grant is a `sunken` tile with no shadow.
  - The read-only reasons are `NoticeComponent :neutral`.
  - The shared invalid edge, never `!border-danger`.
- **Q8, Your account.**
  - "Profile" (`user`, `people`), "Notes" (`message_square`, `people`) and "Password" (`key_round`, a new icon, `neutral`).
  - Blocked is a warn notice and "Password changed." an ok notice, both compact. "Ask" keeps its accent-tint line with its button.
- **Q9, System status.** The summary line in `text-small meta`. The results are one card, rows divided inside it. The command is `CopyValueComponent`. There is no summary chip.
- **Q10, the 403 and 404.** Centred, with no card: the `circle_alert` neutral chip, the code in `text-label meta`, the `text-h1` heading, the sentence, the advice in `text-small meta`, and the secondary way back.
- **Q11, the mails.** `<meta name="color-scheme" content="light">` and `supported-color-schemes`. No dark rule.

The artifact's decisions, taken without a question (listed in the questions file's preamble):
- `NoticeComponent`'s tones and sizes, and its reach to the editor's boxes in this PR;
- the system check row's words as keys;
- PasswordField's invalid edge and its keys;
- the users table and its avatar;
- the group zone's keys;
- the disabled checkbox look;
- the tokens' empty keys;
- the mail's violet.

**Component mapping** (v `1794290753-3cf0`):

| Component | Card |
|---|---|
| `Admin::Ui::NoticeComponent` (new) | `Alerts` |
| `Admin::Ui::ActionZoneComponent` (new) | `ActionZone` (own name; `PatternDestructiveActions` describes its use) |
| `Admin::Ui::CopyValueComponent` (new) | `CopyValue` (own name) |
| `Admin::UsersScreen::*` | `StudioUsers`, `StudioListTable` |
| `Admin::GroupsScreen::*` | `StudioGroups`, `FormControls`, `PatternDestructiveActions` |
| `Admin::TokensScreen::*` | `StudioTokens`, `StudioListTable`, `StudioEmptyState` |
| Your account, system status, the 403 and 404 | `StudioAccount`, `StudioSystemStatus`, `StudioErrors` |
| the product layout and its pages | `StudioSignIn`, `PasswordField`, `Alerts` |
| `layouts/mailer.*`, `mails/_button` | `Mails` |

## Global Constraints

- **Design first.** An implementer who meets a look, a word or a state that neither this plan nor the answers settle stops and reports **NEEDS_CONTEXT**, naming the gap. A step marked "(per Qn, …)" whose answer has changed is not built on the recommendation.
- **The public site keeps its look.** No file under `app/assets/tailwind/themes/`, `app/components/blocks/`, `app/components/posts/`, `app/components/public/`, `app/views/layouts/public/` or `app/views/pages/` changes, and no `th-*` token does. `layouts/form_send` stays neutral (decision 6).
- **CLAUDE.md binds every task.** In particular:
  - The owner flag changes only through `PATCH users/:id/owner`, which the owner zone keeps.
  - A password changes only through `Users::UpdatePassword` or `Users::Save`.
  - A token is never rendered, logged or audited after its reveal, and `CopyValueComponent` must not copy it into a second attribute: the clipboard reads the source's text.
  - Configuration screens (Users, Groups, Your account) save explicitly through `Admin::Ui::SaveBarComponent`. A zone's trigger stays an `admin--saving--pending-lock` control.
  - "A form saved as rendered changes nothing" (`docs/reference/users-groups-tokens.md`): every hidden input the matrix and the group cards carry stays, by name and order.
  - Never define `Admin::<Domain>`. A screen's components stay in the screen's folder. A component used by more than one screen that a task touches moves to `ui/`.
- **No compatibility code.** A moved or renamed class, method, key, constant or CSS class keeps no alias. Every caller, test, preview and reference line is changed in the task that moves it. `git grep` for the old name prints nothing outside `docs/superpowers/` and `CHANGELOG.md`.
- **No admin string is a literal.**
  - A component's keys are `admin.components.<folder>.*` in `config/locales/admin/<folder>.en.yml`, and a `ui/` component's are in `ui.en.yml`.
  - A view's keys are `admin.<screen>.<view>.*` in `config/locales/admin/<screen>.en.yml`. New files: `users.en.yml` (`admin.users`, with `index` moved out of `users_screen.en.yml`), `groups.en.yml`, `groups_screen.en.yml`, `api_tokens.en.yml`, `tokens_screen.en.yml`, `system_status.en.yml` and `errors.en.yml`. `admin.accounts` moves out of `notes.en.yml` into a new `accounts.en.yml`, keeping only the keys notes owns there, with `test/lib/source_layout_test.rb`'s rule for `notes.en.yml` updated.
  - A controller's flash is a key of its own screen's file (`admin.users.saved`, `admin.groups.deleted`, `admin.api_tokens.revoked`, `admin.sessions.refused`, `admin.passwords.reset`).
  - A script's words come from `data-messages`, read with `messages(element).t`.
  - The English stays byte-identical unless this plan names new words. The tests that read the old words keep passing.
  - A file converted to keys joins `test/lib/admin_i18n_test.rb`'s `CONVERTED` in the task that converts it.
  - Left as English, as `docs/reference/i18n.md` names: `Setup::SystemCheck`'s sentences, `Audit::Sentence`, the denial message the 403 shows, and `_stale_banner`'s glued sentence. The banner's look changes in Task 2, and its words do not.
- **The component contract.**
  - A new `ui/` component declares `Admin::Ui::Contract` and has a component test, a preview example per state and a `COVERED_BY` entry in `test/support/design_system_entries.rb`.
  - It is not on `UiContract::MADE_BEFORE_CONTRACT`, which stays at 40 and only shrinks. It names its keyboard browser test in `keyboard:`. A test that arrives in a later task of this PR is listed in `KEYBOARD_NOT_YET` until then, which is empty when the PR merges.
- **Buttons are the shared button.** A link drawn as a button takes `Admin::Ui::ButtonComponent.classes(variant, size:)`. One primary per area: "New user", "New group", "Create token", the save bars' Save, a dialog's confirm, and the auth panel's submit. System status, the 403 and the 404 draw none.
- **Status in words, never red.** `danger` appears only on `danger_text` triggers, destructive confirms, a refused field's edge and message, the error summary, and `NoticeComponent :danger` (a refusal or a broken link). A token's state, a check's state and a group's lock are ok, warn or off, each with its word.
- **No new border for depth.** A card or tile is an elevation. A zone is a `line` rule. The warn notice keeps its edge, and so does a pressable thing's `field-line` frame. Radius, shadow and colour are tokens.
- **Contrast is measured** (`test/lib/admin_contrast_test.rb`) in both schemes, at the figures this plan gives, rounded down to one decimal.
- **Layers.** No raw z-index. The invite row's menu stays at `--cs-z-raised` over the stretched link.
- **Comment rule (#117).** A comment states a current invariant, a hazard or a reason. It never states a plan step, a review round, a handoff, "spec §", "round 3 Task 12", "design answer M4", "C37", "B28", "fix round 1" or what used to be there. These files are full of them. Every task rewrites the comments of the files it changes. Its last step before its commit runs this grep over the lines it added (`git diff -U0 main... -- <files> | grep '^+'`), and the grep prints nothing:

  ```
  grep -n "spec §\|handoff\|Task [0-9]\|round [0-9]\|fix round\|final review\|[Rr]uling [A-Z]\?[0-9]\|decision D\?[0-9]\|design answer\|design pass\|bug [0-9]\|\bB[0-9][0-9]\?\b\|\bC[0-9][0-9]\b\|\bM[0-9]\b\|Q[0-9][0-9]\?\b\|old name\|used to\|no longer"
  ```

- **Tests and the machine.**
  - Every test command is prefixed with `PGGSSENCMODE=disable`. The worktree runs `bin/rails db:test:prepare` once, before its first test.
  - Browser tests run only after `bin/rails tailwindcss:build`, never during a build or beside a running `bin/dev`. They run one file per command, and only while the first figure of `sysctl -n vm.loadavg` is under 6 and `pgrep -f "rails test"` prints nothing.
  - A browser test begins on `visit_screen` or `visit_editor`. The product layout's pages have no shell, so a test there begins on `visit` followed by the page's own wait, as `password_reset_test.rb` does. A rewritten test moves a bare `visit … await_admin_controllers` onto the helpers (#133).
  - Cuprite 0.20: after a redraw, read a node through a retrying selector.
  - No new browser file. A moved component's test moves with `git mv`.
  - No test run is left in the background when a task ends.
- Commits follow conventional commits and end with:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT`
  A task that carries a finding says so in its body ("Advances #117").

## Review Focus

1. **A form saved as rendered still changes nothing.** The group cards become tiles, the matrix's rows move into a frame, and the locked ticks lose their opacity class. Through all of that, every carried hidden input stays: a locked group, a locked grant's scope, a removed type, a kept branch and the blank sentinels. A Save with nothing touched writes no audit event. Task 7:
   - `test "a group saved as rendered by a viewer with a locked grant, a removed type and a kept branch writes nothing and audits nothing"` (integration, `test/integration/admin/groups_editor_states_test.rb`).

   Task 6:
   - `test "a user saved as rendered with a group the viewer can't grant keeps the membership"` (integration, `users_editor_test.rb`).
2. **The token's one-time reveal under the new copy script.** The token must reach the clipboard from the source's text alone, appear in no `data-*` attribute, be blanked at `pagehide` (text and any copy value), and not come back on Back or a reload. A failed clipboard selects the text. Task 4:
   - `test "the revealed token is in no attribute, Copy writes it from the text, and pagehide blanks it"` (component, `copy_value_component_test.rb`, rendered with `source_data:`);
   - the existing `tokens_related_posts_and_starter_pages_test.rb` "creating a token reveals it once, and back/reload don't show it again" stays green.
3. **The stretched row link and the invite menu.** The users table puts a link stretched over its row beside an invitation's ⋯ menu. A press on the menu opens the menu, never an editor. Tab reaches the name, then the menu. A Withdraw confirm stays outside the row's link. Task 5:
   - `test "an invitation's menu opens over its row, Resend and Withdraw work, and a press on the menu never opens an editor"` (browser, `invites_test.rb`, folded into "resend and withdraw from the row menu").
4. **A notice's role after the move.** Many boxes change markup at once, and a screen reader must not lose one or hear one twice:
   - the shell's insecure notice, the mail-failed notice, the stale banner (`role="alert"`, still the leave guard's Reload way out, `data-save-bar-cancel`), Changed elsewhere and the live region's line (whose `aria-live` region is the live region's own, not the notice's);
   - the error summary is not migrated: it stays its own component, focused on arrival.

   Task 2:
   - `test "a notice inside a live region adds no role of its own, and the stale banner keeps its Reload way out"` (component, `notice_component_test.rb`, with `role: nil` passed by the live region);
   - the browser tests `changed_elsewhere_test`, `editing_live_test` and `publish_dialog_steady_test`.
5. **The auth panel on a phone and with a long German site name.** At 360px wide, the panel keeps a 16px gutter, the full-width button stays inside it, the "Forgot your password?" aside wraps under the label instead of overflowing, and a 60-character site name wraps. Task 9:
   - `test "at 360px the sign-in panel keeps its gutter, the button fits and a long site name wraps"` (browser, `password_reset_test.rb`, which holds the product layout's pages).

---

## Decisions the spec left open (not looks)

| Question | Decision | Why |
|---|---|---|
| The notice's interface | `Admin::Ui::NoticeComponent.new(tone:, size: :regular, role: :default, **html)`, with the content as its block. `TONES = { warn: "border border-warn bg-warn-tint text-warn-ink", ok: "bg-ok-tint text-ok-ink", danger: "bg-danger-tint text-danger-ink", neutral: "bg-sunken text-dim" }`. `SIZES = { regular: "px-3 py-2 text-sm", compact: "px-3 py-2.5 text-small leading-normal" }`. Always `rounded-card`. `ROLES = { warn: "alert", danger: "alert", ok: "status", neutral: "note" }`. `role: :default` takes the tone's role, and `role: nil` writes none (a notice inside a live region). An unknown tone or size raises `ArgumentError`. A `class:` in `html` is appended. | Alerts Gap 2's interface. `role: nil` covers Review Focus 4. |
| The two named notices | `InsecureNoticeComponent` and `MailFailedNoticeComponent` keep their names, ids, keys and `render?`. Each renders `NoticeComponent.new(tone: :warn, size: :compact, id: …)` in place of its own `BASE_CLASS`, which goes. | They decide when to speak, and the notice draws how. |
| The zone's interface | `Admin::Ui::ActionZoneComponent.new(heading_id:, heading:, body:, reason: nil, pending_lock: false, **html)`, with `renders_one :trigger`. It draws `section.admin-action-zone.mt-6.flex.flex-wrap.items-center.justify-between.gap-3.border-t.border-line.pt-4[aria-labelledby]`: the `h2` at `text-h3` (an `h2`, since it is a section of the page), the `body` in `text-small text-dim`, the `reason` (when given) with `data-action-zone-reason`, and, with `pending_lock: true`, `data-controller="admin--saving--pending-lock"` and the hint `p` (`data-admin--saving--pending-lock-target="hint"`, hidden). The trigger is the caller's (its button keeps `pending-lock-target: "control"`). The dialogs stay the caller's, after the zone. | One frame and four callers (Q3). The `admin-delete-zone` / `admin-owner-zone` test hooks become `data-zone="delete"` / `"owner"` / `"trash"` on the section, passed in `html`. |
| The copy box's interface | `Admin::Ui::CopyValueComponent.new(id:, value:, copy_label:, layout: :inline, source_data: {}, **html)`, with `layout` either `:inline` (one-line `code`) or `:block` (`pre`). The root is `div.flex.flex-wrap.items-start.gap-2[data-controller=admin--ui--clipboard][data-messages]`. The value is `code`/`pre#id.min-w-0.flex-1.overflow-x-auto.rounded-field.bg-sunken.px-3.py-2.font-cs-mono.text-small.text-ink[data-admin--ui--clipboard-target=source]`, with `source_data` merged (the reveal's `secret` target). The button is `ButtonComponent` secondary small "Copy" (`aria-label: copy_label`, target `button`). The status is an `sr-only` `role=status` `aria-live=polite` target. No text value is written: the script copies the source's text. | One box, one script (Q5). Review Focus 2. |
| The one copy script | `admin--ui--clipboard#copy` writes `this.textValue \|\| this.urlValue \|\| this.sourceTarget.textContent.trim()`. Its words come from the element's `data-messages`, or else the document's: `ui.copy_value.copied` ("Copied"), `failed` ("Copy failed") and `selected` ("Couldn't copy automatically — the text is selected, press Ctrl+C (⌘C on a Mac)."). `admin--tokens--reveal` keeps `connect`/`disconnect` and `forget` (the `secret` targets blanked at `pagehide`), and loses `copy`, `select`, `say` and its `status` target. | The header's URL copy (`EditorScreen::HeaderComponent`) keeps its `url` value. |
| A row's link | In `content-spiel.tailwind.css`: `tr:has(.admin-row-link), li:has(> * .admin-row-link) { position: relative; }`, `.admin-row-link::after { content: ""; position: absolute; inset: 0; }`, and `.admin-row-link:focus-visible { outline: none } .admin-row-link:focus-visible::after { outline: 2px solid var(--cs-accent); outline-offset: -2px; }`. Anything else pressable in the row is `relative z-(--cs-z-raised)`. The users, groups and audit rows draw it, and the hand `after:absolute after:inset-0 …` strings go. | Three rows draw the same stretched link. |
| The badge's mark | `BadgeComponent` gains `renders_one :mark`, drawn before the label inside the badge, `aria-hidden` (its caller's dot is decoration beside the name). The contract's `slots:` gains `mark`, and `states:` gains `marked`. | A scope chip is a badge with a type dot (Q6). |
| The disabled checkbox | `.cs-checkbox:disabled { cursor: not-allowed; opacity: 1; }` and `.cs-checkbox:disabled + label, label:has(> .cs-checkbox:disabled) { color: var(--cs-meta); }`. The matrix's `opacity-60` and the toggle list's `opacity-60` go. | FormControls Gap 1. The browser's own disabled box is 3:1 on surface (`admin_contrast_test` cannot measure a native box; the test reads the rule). |
| The guard list's name | `CONTENT_SIDE_SCREENS` becomes `TYPE_SCALE_SCREENS`, the same glob list grown by each 7b screen task, with the same `OFF_SCALE` pattern and `HAND_BOX_ALLOWED`. | It now holds more than the content side. No alias. |
| The mail's one colour | `MAIL_SOURCES = %w[app/views/layouts/mailer.html.erb app/views/mails app/views/forms_mailer app/views/invites_mailer app/views/passwords_mailer app/views/system_mailer]` and `MAIL_ACCENT = "#6236d9"`. The raw-colour test reads `ADMIN_SOURCES` plus every `*.erb` under `MAIL_SOURCES`, and in a mail source it first removes `MAIL_ACCENT` (exact, lower case) from the line. A second test holds that `MAIL_ACCENT` is `--cs-accent`'s light value in `content-spiel.css`, and that it appears only in `mails/_button.html.erb`. | Decision 5: a named exception that admits that value and no other. Today `mails/` and the mailers' views are not scanned at all. |
| The system check list's frame | `setup/_system_check_results` takes `list_class:`. Its default is the wizard's `mt-6 divide-y divide-line border-y border-line`. System status passes `divide-y divide-line px-4`, inside its card. | One partial, two frames (Q9). |

---

## File map

| File | Responsibility | Tasks |
|---|---|---|
| `ui/notice_component.*` (new) with test and preview, `ui/badge_component.*`, `content-spiel.tailwind.css` (`.admin-row-link`, `.cs-checkbox:disabled`), `audit_screen/row_component.html.erb`, `test/support/{design_system_entries,ui_contract}.rb`, `test/lib/{admin_design_rules,admin_contrast}_test.rb`, `ui.en.yml` | the shared parts | 1 |
| `ui/{insecure_notice,mail_failed_notice}_component.rb`, `admin/shared/_stale_banner.html.erb`, the editor's, Settings', the forms list's and the setup flash's boxes (Task 2's list) | every other notice | 2 |
| `ui/action_zone_component.*` (new), `users_screen/{delete,owner}_zone_component.*`, `groups_screen/delete_zone_component.*`, `forms_screen/trash_zone_component.*`, `users_screen.en.yml`, `groups_screen.en.yml` (new) | the zones | 3 |
| `ui/copy_value_component.*` (new), `controllers/admin/ui/clipboard_controller.js`, `controllers/admin/tokens/reveal_controller.js`, `ui/system_check_row_component.*`, `tokens_screen/{create,connect}_step_component.*` | copying | 4 |
| `users_screen/{list,invite_dialog}_component.*`, `app/views/admin/users/index.html.erb`, `users.en.yml` (new), `users_screen.en.yml`, `admin/users_controller.rb` (flashes) | Users and invites | 5 |
| `app/views/admin/users/{_form,edit,new}.html.erb`, `users_screen/group_cards_component.*`, `users.en.yml`, `users_screen.en.yml` | the user editor | 6 |
| `groups_screen/*`, `app/views/admin/groups/*`, `admin/groups_controller.rb` (flashes), `groups.en.yml` (new), `groups_screen.en.yml` | Groups | 7 |
| `tokens_screen/*`, `app/views/admin/api_tokens/*`, `admin/api_tokens_controller.rb`, `api_tokens.en.yml`, `tokens_screen.en.yml` (new) | the AI assistant | 8 |
| `layouts/product.html.erb`, `admin/shared/_auth_heading.html.erb`, `admin/sessions/new`, `admin/passwords/{new,edit}`, `invitations/show`, `ui/password_field_component.*`, `controllers/password_field_controller.js`, `admin/{sessions,passwords}_controller.rb`, `sessions.en.yml`, `passwords.en.yml`, `invitations.en.yml` | the sign-in pages and the password field | 9 |
| `app/views/admin/accounts/edit.html.erb`, `admin/shared/_icon.html.erb` (`key_round`), `accounts.en.yml` (new), `notes.en.yml` | Your account | 10 |
| `app/views/admin/system_status/show.html.erb`, `setup/_system_check_results.html.erb`, `app/views/admin/errors/*`, `system_status.en.yml` (new), `errors.en.yml` (new) | System status, 403, 404 | 11 |
| `layouts/mailer.html.erb`, `mails/_button.html.erb`, `forms_mailer/submission.html.erb`, `test/mailers/*`, `test/lib/admin_{design_rules,contrast}_test.rb` | the mails | 12 |
| `docs/reference/{design-system,users-groups-tokens,mail,hosting,i18n,forms}.md`, `CLAUDE.md`, `CHANGELOG.md` | the reference, the PR and the cards | 13 |

---

### Task 1: The shared parts, and the Design System's copy

**Files:**
- Modify `test/support/design_system_entries.rb`: `VERSION = "1794290753-3cf0"`, `COVERED_BY["Admin::Ui::NoticeComponent"] = "Alerts"`, and `ENTRIES` gains the nine new folders `ActionZone CopyValue StudioAccount StudioErrors StudioGroups StudioSignIn StudioSystemStatus StudioTokens StudioUsers` (kept in the list's order), and loses the four cards the owner's cleanup of 2026-11-10 removes: `StudioCalmColour StudioCalmDashboard StudioCalmEditorE StudioPageTree`. The controller supplies the cleanup's final index id for `VERSION` when it lands. `ActionZoneComponent` and `CopyValueComponent` match their cards by name, so they take no `COVERED_BY` entry.
- Create `app/components/admin/ui/notice_component.rb` (decisions table), a `call` with no template. Contract:
  - `accessibility:` "A box of the caller's words whose role follows its tone (alert, status or note), or none inside a live region; it takes no focus.";
  - `motion: :none`, `content_edges: %i[short long]`, `widths: :from_container`, `interface: %i[tone size role]`;
  - `limits:` "It says only what the caller hands it; a link inside is the caller's." and "It offers no dismissal: a notice stays until its cause is gone.";
  - `states: %i[warn ok danger neutral compact]`, `keys: []`, `slots: []`, `controller: nil`;
  - `keyboard: ["test/system/admin/users_test.rb", "a user the viewer can't change says why in a note, and the keyboard passes over it from the breadcrumb to Activity"]`, which Task 6 writes. Until then, `UiContract::KEYBOARD_NOT_YET["Admin::Ui::NoticeComponent"] = "Task 6 writes its keyboard test"`.
- Preview `test/components/previews/admin/ui/notice_component_preview.rb`: `warn`, `ok`, `danger`, `neutral`, `compact`, and `long` (a German sentence of 240 characters).
- Modify `app/components/admin/ui/badge_component.{rb,html.erb}`: the `mark` slot (decisions table). The preview gains `marked`.
- Modify `app/assets/tailwind/content-spiel.tailwind.css`: `.admin-row-link` and `.cs-checkbox:disabled` (decisions table), each with a comment saying what it draws and for whom.
- Modify `app/components/admin/audit_screen/row_component.html.erb`: its stretched link takes `.admin-row-link`.
- Modify `test/lib/admin_design_rules_test.rb`:
  - rename `CONTENT_SIDE_SCREENS` to `TYPE_SCALE_SCREENS`;
  - `CARD_BORDER_ALLOWED` gains `notice_component.rb` ("the warn notice keeps its edge");
  - `STATUS_FILL_FILES` gains `notice_component.rb` (it is the status component that takes the boxes' fills over; Tasks 2 and 5 to 11 remove the files whose fills it takes);
  - `test "a row's stretched link is .admin-row-link, written once"` refuses `after:absolute after:inset-0` in `ADMIN_SOURCES` and reads the four declarations.
- Modify `test/lib/admin_contrast_test.rb`:
  - `test "a notice's words read on its ground in every tone"`, with floors: warn-ink on warn-tint 4.5, ok-ink on ok-tint 4.5, danger-ink on danger-tint 4.5, dim on sunken 4.5, in both schemes;
  - `test "the warn notice's edge is 3:1 on surface and paper"` is **not** written. The edge groups, like the alerts' today, and the existing alert rule holds it.
- Test: `test/components/admin/ui/{notice,badge}_component_test.rb`, `test/components/admin/audit_screen/row_component_test.rb`, `test/components/previews_test.rb`, `test/lib/{component_parts,admin_design_rules,admin_contrast}_test.rb`, `test/components/admin/ui/contract_test.rb`.

**Interfaces:**
- Produces:
  - `Admin::Ui::NoticeComponent.new(tone:, size: :regular, role: :default, **html) { content }`;
  - `BadgeComponent`'s `with_mark`;
  - the classes `.admin-row-link` and the disabled checkbox rule;
  - `TYPE_SCALE_SCREENS`, for Tasks 5 to 11 to grow.

- [ ] **Step 1: Write the failing tests.**
  - `notice_component_test.rb`:
    - `test "each tone draws its ground, its words and its role: warn and danger an alert, ok a status, neutral a note"`;
    - `test "warn alone has an edge, every tone is rounded-card, and compact is 13px"`;
    - `test "role: nil writes no role, and an unknown tone or size is refused"`;
    - `test "a caller's class is added to the notice's own and its id and data reach the box"`.
  - `badge_component_test.rb`: `test "a mark stands before the label, hidden from a screen reader"`.
  - `row_component_test.rb` (audit): `test "the row's one link is .admin-row-link"`.
  - The guard and contrast tests above.
- [ ] **Step 2: Run them, and verify they fail.** `PGGSSENCMODE=disable bin/rails test test/components/admin/ui test/components/admin/audit_screen test/lib/admin_design_rules_test.rb test/lib/admin_contrast_test.rb test/lib/component_parts_test.rb`.
- [ ] **Step 3: Implement.** Then `git grep -n CONTENT_SIDE_SCREENS -- test docs/reference CLAUDE.md` prints nothing (Task 13 rewrites the reference line).
- [ ] **Step 4: Run.** `PGGSSENCMODE=disable bin/rails test test/components test/lib`. After a build: `admin/audit_log_test.rb`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Run the comment grep and check `pgrep`. Commit `feat: a shared notice, the stretched row link, a badge's mark and the disabled checkbox look` (body: `Advances #117`).

---

### Task 2: Every other alert box through the notice

**Files:**
- Modify `app/components/admin/ui/insecure_notice_component.rb` and `mail_failed_notice_component.{rb,html.erb}`: they render `NoticeComponent.new(tone: :warn, size: :compact, …)` (decisions table). `BASE_CLASS` goes. Their keys and ids stay.
- Modify `app/views/admin/shared/_stale_banner.html.erb`: `NoticeComponent :warn` (regular). Its words become `warn-ink`, the Alerts card's one warn look. Reload keeps `data-save-bar-cancel` and `data-turbo-frame="content"`.
- Read each of these, and move every **box of words** in them onto `NoticeComponent`, in the tone its words carry:
  - `editor_screen/changed_elsewhere_component.html.erb`;
  - `editor_screen/live_region_component.html.erb` (`role: nil`: the region is the live one);
  - `editor_screen/delete_block_dialog_component.rb` (the notes warning);
  - `editor_screen/publish_changes_dialog_component.html.erb` (the notes line; the "Addresses" warn box too, keeping its heading and its lists inside the notice);
  - `settings_screen/language_dialogs_component.html.erb`;
  - `settings_screen/mail_alert_component.rb` and `mail_test_outcome_component.rb`, where each draws a box rather than a `StateChipComponent`;
  - `forms_screen/list_component.rb` (the warnings);
  - `app/views/setup/_flash.html.erb` (regular: the wizard's 14px).

  A chip, a bar, a fill that is a state's own mark, or a dialog's danger confirm is not a box and stays: `badge`, `state_chip`, `translation_chip`, `language_tabs`, `language_progress`, `word_diff`, `button`, `chip_input`, `tree_state_mark`, `table_controls`, `no_address_chip`, `hold_strip`, `notes_screen/thread_component` and `setup/_steps`.
- Modify `test/lib/admin_design_rules_test.rb`:
  - `STATUS_FILL_FILES` and `CARD_BORDER_ALLOWED` lose every file that no longer draws a fill or an edge (the stale-entry tests name them);
  - `test "an alert box is NoticeComponent: no file outside it draws a box of bg-warn-tint, bg-ok-tint or bg-danger-tint beside rounded-cs or rounded-card"`, with a pattern test whose samples are today's stale banner and sign-in box (which match) and a `StateChipComponent` and the badge's warn tone (which do not).
- Test:
  - `test/components/admin/ui/{insecure_notice,mail_failed_notice}_component_test.rb` (their tests stay; "the caller's classes place it and never replace its own" now reads the notice's classes);
  - `test/components/admin/editor_screen/{changed_elsewhere,live_region,delete_block_dialog,publish_changes_dialog}_component_test.rb`;
  - `test/components/admin/settings_screen/*_test.rb`, `test/components/admin/forms_screen/list_component_test.rb`;
  - `test/integration/admin/insecure_notice_test.rb`, `test/integration/setup_*`.

**Interfaces:**
- Consumes: Task 1's `NoticeComponent`.

- [ ] **Step 1: Write the failing tests.**
  - Review Focus 4's test, in `notice_component_test.rb`.
  - `stale_banner` (an integration in `test/integration/admin/users_editor_test.rb`): `test "a stale save's banner is the warn notice, with Reload as its way out"`.
  - `live_region_component_test.rb`: `test "the missing line is a notice with no role of its own inside the polite region"`.
  - The guard above.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Search the tests for `bg-warn-tint`, `bg-danger-tint`, `bg-ok-tint` and `rounded-cs` near an alert, and fix each hit.
- [ ] **Step 4: Run.**
  - `PGGSSENCMODE=disable bin/rails test test/components test/lib test/integration`.
  - After a build, one file at a time: `admin/changed_elsewhere_test`, `admin/editing_live_test`, `admin/publish_dialog_steady_test`, `admin/languages_test`, `admin/settings_mail_test`, `setup_wizard_test`, `admin/view_only_test`, `admin/groups_editor_test` (the stale banner).
  - Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `ref: every alert box in CS Studio is the shared notice, one warn look` (body: `Advances #117`).

---

### Task 3: One action zone (per Q3, recommended answer assumed)

**Files:**
- Create `app/components/admin/ui/action_zone_component.{rb,html.erb}` (decisions table). Contract:
  - `accessibility:` "A section named by its heading, holding the caller's one trigger; with pending_lock the trigger is disabled while the form above has unsaved changes, with the hint in words.";
  - `motion: :none`, `content_edges: %i[short long]`, `widths: :from_container`, `interface: %i[heading_id heading body reason pending_lock trigger]`;
  - `limits:` "Its dialogs are the caller's, drawn after it, outside every form." and "It decides nothing of who may act: the caller draws it or not.";
  - `states: %i[rest reason locked]`, `keys: []`, `slots: %i[trigger]`, `controller: "admin--saving--pending-lock"`;
  - `keyboard: ["test/system/admin/users_test.rb", "with a typed change the owner and delete buttons are disabled with the hint, and come back when it is undone"]`.
- Preview `test/components/previews/admin/ui/action_zone_component_preview.rb`: `rest`, `reason`, `locked`.
- Modify `app/components/admin/users_screen/delete_zone_component.*`, `owner_zone_component.*`, `groups_screen/delete_zone_component.*` and `forms_screen/trash_zone_component.*` to render the zone with `data: { zone: "delete" | "owner" | "trash" }`.
  - The users' zones pass `pending_lock: true`.
  - The built-in group renders `NoticeComponent.new(tone: :neutral, data: { zone: "built_in" })` in the zone's place.
  - Every literal becomes a key:
    - `admin.components.users_screen.delete_zone.{heading,body,reason,trigger,dialog_title,dialog_body,dialog_body_own,confirm}`;
    - `owner_zone.{heading,body,reason,make,remove,make_title,remove_title,make_body,remove_body,remove_body_own,make_confirm,remove_confirm}`;
    - `admin.components.groups_screen.delete_zone.{heading,members(zero/one/other),tokens(zero/one/other),trigger,built_in,dialog_title,dialog_body,more(count),confirm}`, the artifact's `heading`, `built_in` and `more` among them.

    The dialog's body becomes whole sentences per count, not glued parts: `dialog_body.members_only(one/other)`, `members_and_tokens`, `no_members`.
- Modify `test/lib/admin_i18n_test.rb`: the three zone components join `CONVERTED`, and `groups_screen.en.yml` is created holding only `admin.components.groups_screen` (Task 7 fills the rest).
- Test: `test/components/admin/ui/action_zone_component_test.rb`, `test/components/admin/users_screen/{delete,owner}_zone_component_test.rb`, `test/components/admin/groups_screen/delete_zone_component_test.rb`, `test/components/admin/forms_screen/trash_zone_component_test.rb`, `test/lib/{component_parts,admin_i18n,source_layout,admin_design_rules}_test.rb`.

**Interfaces:**
- Consumes: Task 1's `NoticeComponent`.
- Produces: `Admin::Ui::ActionZoneComponent.new(heading_id:, heading:, body:, reason: nil, pending_lock: false, **html)` with `with_trigger`, and the `data-zone` hook that Tasks 6 and 7 test by.

- [ ] **Step 1: Write the failing tests.**
  - `action_zone_component_test.rb`:
    - `test "a section named by its heading, over a line rule, with no box of its own"`;
    - `test "pending_lock wires the hint and the controller, and a reason is drawn when given"`.
  - The zones' tests:
    - `test "the delete zone is the shared zone with the danger_text trigger, and its dialog stands after it"`;
    - `test "the owner zone's trigger is secondary and its confirm primary"`;
    - `test "a built-in group says so in a neutral note in the zone's place"`;
    - `test "a group with 1 member and 12 tokens names 10 tokens and says 2 more, in whole sentences"`.
  - The forms zone's existing tests read `data-zone="trash"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Search the tests for `admin-delete-zone` and `admin-owner-zone` and move each to the `data-zone` hook. `git grep -n "admin-delete-zone\|admin-owner-zone" -- app test` prints nothing.
- [ ] **Step 4: Run.** `PGGSSENCMODE=disable bin/rails test test/components test/lib test/integration/admin/{users_editor,groups,forms}_test.rb`. After a build: `admin/users_test`, `admin/groups_members_test`, `admin/form_builder_test`, `admin/pending_lock_test`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: one action zone for the delete, owner and trash zones after a form` (body: `Advances #117`).

---

### Task 4: One copy box and one copy script (per Q5, recommended answer assumed)

**Files:**
- Create `app/components/admin/ui/copy_value_component.{rb,html.erb}` (decisions table). Contract:
  - `accessibility:` "The value is selectable text; Copy is named for its value, and a polite status says Copied, or that the text was selected when the clipboard refused.";
  - `motion: :none`, `content_edges: %i[short long]`, `widths: :from_container`, `interface: %i[id value copy_label layout source_data]`;
  - `limits:` "It copies the value's text and writes it into no attribute." and "A value too long for its box scrolls inside the box, never the page.";
  - `states: %i[inline block]`, `script_states: { copied: ["test/system/admin/system_status_and_preview_test.rb", "Copy writes the command, says Copied, and announces it politely"], selected: ["test/system/admin/system_status_and_preview_test.rb", "without a Clipboard API the command is selected instead and nothing raises"] }`;
  - `keys: %w[copy]`, `slots: []`, `controller: "admin--ui--clipboard"`;
  - `keyboard: ["test/system/admin/system_status_and_preview_test.rb", "Copy writes the command, says Copied, and announces it politely"]`.
- Preview: `inline`, `block`, and `long` (a 400-character configuration).
- Modify `app/javascript/controllers/admin/ui/clipboard_controller.js` and `controllers/admin/tokens/reveal_controller.js` (decisions table). The words come from `ui.copy_value.{copy,copied,failed,selected}`. Add them to `SCRIPT_MESSAGES`, so the document's `data-messages` holds them for every screen, the editor header's copy included.
- Modify `app/components/admin/ui/system_check_row_component.{rb,html.erb}`:
  - the command is `CopyValueComponent.new(id: "check-command-#{index}", value: result.command, copy_label: t(".copy_label", label: result.label), layout: :inline)` when `copyable?`, and plain `code` otherwise;
  - "Learn more →" becomes `t(".learn_more")`;
  - the links are tertiary small;
  - `limits:` drops "Its words … are English, not keys.";
  - it joins `CONVERTED` (Alerts Gap 1).
- Modify `tokens_screen/create_step_component.html.erb` and `connect_step_component.html.erb`:
  - the token, the MCP URL and the client configuration are `CopyValueComponent`s, the token with `source_data: { "admin--tokens--reveal-target": "secret" }`, and the configuration with that target too while it holds the token;
  - their `status` paragraphs go.
- Modify `test/lib/admin_design_rules_test.rb`: `MONO_ALLOWED` gains `app/components/admin/ui/copy_value_component.html.erb` ("a value a person copies exactly: a token, an address, a command") and loses `tokens_screen/create_step_component.html.erb`, whose mono moves into the box; its stale-entry check names any other file that stops drawing `<code>`/`<pre>`.
- Test: `test/components/admin/ui/{copy_value,system_check_row}_component_test.rb`, `test/components/admin/tokens_screen/{create,connect}_step_component_test.rb`, `test/components/admin/editor_screen/header_component_test.rb`, `test/integration/admin/{system_status,api_tokens}_test.rb`, `test/lib/{script_messages,admin_i18n,component_parts}_test.rb`.

**Interfaces:**
- Produces: `Admin::Ui::CopyValueComponent.new(id:, value:, copy_label:, layout: :inline, source_data: {}, **html)`. Tasks 8 and 11 lay it out.

- [ ] **Step 1: Write the failing tests.**
  - `copy_value_component_test.rb`:
    - `test "the value is escaped text in its source target, the button is named for it, and no text value is written"`;
    - Review Focus 2's test.
  - `system_check_row_component_test.rb`: `test "the command's Copy is the copy box, named for its check, and Learn more is a key"`.
  - `create_step_component_test.rb`: `test "the reveal is a warn notice holding the token's copy box, a secret target, and nothing else holds the token"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** Then `git grep -n "admin--tokens--reveal#copy\|reveal-source-param" -- app test` prints nothing.
- [ ] **Step 4: Run.** `PGGSSENCMODE=disable bin/rails test test/components test/lib test/integration/admin`. After a build: `admin/system_status_and_preview_test`, `admin/tokens_related_posts_and_starter_pages_test`, `admin/editor_header_test`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `ref: one copy box and one copy script for tokens, system checks and the editor's address` (body: `Advances #117`).

---

### Task 5: Users and invites (per Q1, Q2, recommended answers assumed)

**Files:**
- Modify `app/components/admin/users_screen/list_component.{rb,html.erb}`:
  - a `table.admin-users-list.admin-card-table.w-full` in `div.rounded-card.bg-surface.shadow-1 > div.admin-table-scroll--x`;
  - `thead th scope=col` reading `.user`, `.groups`, `.last_sign_in`, and an `sr-only` `.actions`; the name cell is a `th scope=row`;
  - the avatar: `AvatarComponent.new(initials: PersonName.initials(row.name_or_email), size: :md, tone: …)`, with tones as in Q2 (an invitation is `:other`);
  - a user's name: `link_to … class: "admin-row-link font-medium text-ink"`, then "(you)" and the badges;
  - the groups: one `BadgeComponent` each;
  - the row ends in `span.admin-row-verb` `t(".edit")`, or, for an invitation, the menu in `relative z-(--cs-z-raised)`.

  `COLUMNS` and `initial` go. The users list leaves `HAND_BUILT_AVATAR_ALLOWED`, which leaves it holding only `avatar.js`.
- Modify `invite_dialog_component.html.erb`:
  - the general refusal is `NoticeComponent :danger, size: :compact`;
  - each field sits in `div.admin-field` with its errors through `admin/shared/_field_errors` (`id: "invite_email_address-errors"`), so the shared invalid edge draws it and `!border-danger` goes;
  - the Resend button stays inside the error slot, `ButtonComponent.classes(:tertiary, size: :small)`.
- Modify `app/views/admin/users/index.html.erb`:
  - the heading row (Q1): "Users", the invites-need-mail line in `text-small meta`, "Invite person" (secondary) and "New user" (primary);
  - every literal a key in `admin.users.index` (a new `users.en.yml`: the `index` scope moves there from `users_screen.en.yml`);
  - `delete_hint` stays under the card in `text-small meta`.
- Modify `app/controllers/admin/users_controller.rb`: the flashes are `t("admin.users.created")`, `.saved`, `.deleted` and `.deleted_own`. `STALE_LEAD` and `STALE_MESSAGE` stay (the banner's named debt).
- Modify `test/lib/admin_design_rules_test.rb`: `TYPE_SCALE_SCREENS` gains `app/components/admin/users_screen/*` and `app/views/admin/users/*`.
- Test: `test/components/admin/users_screen/{list,invite_dialog}_component_test.rb`, `test/integration/admin/{users,invites}_test.rb`, `test/lib/{admin_design_rules,admin_i18n,source_layout}_test.rb`.

**Interfaces:**
- Consumes: Tasks 1 and 2 (`.admin-row-link`, `NoticeComponent`).

- [ ] **Step 1: Write the failing tests.** In `list_component_test.rb`, rewrite "a row is one stretched link…" as:
  - `test "the list is a table with scoped headers, and a user's row is one stretched link ending in Edit"`;
  - `test "a user's circle is the shared avatar, your own in the own tone and an invitation's dashed"`;
  - `test "groups are badges, and none reads No groups"`.

  In `invite_dialog_component_test.rb`: `test "a refused address draws the shared invalid edge and its message, with Resend inside it"`. Review Focus 3's browser test.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** `PGGSSENCMODE=disable bin/rails test test/components/admin/users_screen test/integration/admin test/lib`. After a build: `admin/users_test`, `admin/invites_test`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: the Users list is a table of shared avatars, badges and row links` (body: `Advances #117`).

---

### Task 6: The user editor and New user (per Q7, recommended answer assumed)

**Files:**
- Modify `app/views/admin/users/_form.html.erb`:
  - the first card is `Admin::Ui::SettingsCardComponent.new(heading_id: "user-details", heading: t(".details"), icon: :user, family: :people)`, holding Name and Email (each an `.admin-field` with a `_field_errors` slot), and the password fields or "Set a new password…";
  - the disclosure's summary is `ButtonComponent.classes(:tertiary, size: :small)` on a `<summary>` with `admin-disclosure`;
  - every literal is a key in `admin.users.form` (Name, the placeholder and help, Email address, Password, Confirm password, the disclosure and its help, Create user, Save user).
- Modify `users_screen/group_cards_component.{rb,html.erb}`:
  - it renders inside a second `SettingsCardComponent` ("Groups", `icon: :groups`, `family: :people`), with "Manage groups →" as `head_end`, tertiary small;
  - each card is `label.admin-tile.grid…`; `.admin-tile:has(> input:checked)` joins the selected rule in `content-spiel.tailwind.css`, and the locked look is `.admin-tile[data-locked] { background: var(--cs-sunken); box-shadow: none; color: var(--cs-meta) }`;
  - `CARD`, `OPEN_CARD` and `LOCKED_CARD` go;
  - its words are keys (`admin.components.users_screen.group_cards.{title,manage,locked}`);
  - the invite dialog renders it with `frame: false` (no card in a dialog): `initialize` gains `frame: true`.
- Modify `app/views/admin/users/{edit,new}.html.erb`:
  - the breadcrumb is `text-label meta`;
  - "Activity" is a secondary small link;
  - "Last signed in …" is `text-small dim`;
  - the two reasons are `NoticeComponent :neutral` with keys `admin.users.edit.{owner_protected,outranked}`;
  - the title and heading literals are keys.
- Write the keyboard test Task 1 named, and remove `NoticeComponent` from `KEYBOARD_NOT_YET`.
- Modify `test/lib/admin_i18n_test.rb`: `_form`, `edit`, `new` and `group_cards_component.*` join `CONVERTED`.
- Test: `test/components/admin/users_screen/group_cards_component_test.rb`, `test/integration/admin/users_editor_test.rb`, `test/lib/*`.

**Interfaces:**
- Consumes: `SettingsCardComponent` (7a), `NoticeComponent`, Task 3's zones (drawn after the form, unchanged here).

- [ ] **Step 1: Write the failing tests.**
  - `group_cards_component_test.rb`:
    - `test "a group is a tile whose checkbox is its label's, ticked drawn by the tile's selected rule"`;
    - `test "a group the viewer can't grant is a sunken tile with its reason, and a ticked one is carried by a hidden input"`;
    - `test "in a dialog it draws no card frame"`.
  - Review Focus 1's user test.
  - The keyboard test, browser, in `users_test.rb`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** `PGGSSENCMODE=disable bin/rails test test/components test/integration/admin test/lib`. After a build: `admin/users_test`, `admin/invites_test`, `admin/pending_lock_test`, `password_field_test`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: the user editor in the card frame, its groups as tiles` (body: `Advances #117`).

---

### Task 7: Groups and the permission matrix (per Q1, Q6, recommended answers assumed)

**Files:**
- Modify `app/components/admin/groups_screen/list_component.{rb,html.erb}`: Q1's table (Group, Members, Tokens, `sr-only` Actions). The name is `.admin-row-link`, then the Built-in badge, the description in `text-small dim`, the counts in `text-small` (`meta` at zero), and the row ends in "Edit". `COLUMNS` goes. Every literal is a key, the counts' `sr-only` words with `count:` (`.members`, `.tokens`).
- Modify `app/views/admin/groups/{index,_form,edit,new}.html.erb`:
  - the heading row;
  - the form's first card is `SettingsCardComponent` "Group" (`:groups`, `:people`) holding Name, Description and Members (each `.admin-field`, the shared invalid edge);
  - the view-only reason is `NoticeComponent :neutral`;
  - every literal is a key (`admin.groups.{index,form,edit,new}`, a new `groups.en.yml`).
- Modify `permission_matrix_component.{rb,html.erb}`:
  - "Content permissions" is `SettingsCardComponent` (`heading_id: "group-content-permissions"`, `icon: :pages`, `family: :structure`, `intro:` the scope sentence), and its area bands stay `paper` `text-label meta`;
  - "Other permissions" is a second frame (`:settings`, `:neutral`) holding `ToggleListComponent`;
  - the stale-grant notes are `NoticeComponent :warn` (the unregistered ones regular at the top; the per-row ones compact under the row, indented like the scope editor);
  - the locked hint is `text-small meta`.
- Modify `toggle_list_component.{rb,html.erb}`: one list of area bands and rows (the bands `paper`, `text-label meta`; the rows `px-4 py-2`, divided by `line`), in place of a grid of cards. `opacity-60` goes. Its words are keys.
- Modify `permission_row_component.{rb,html.erb}`:
  - `chips` draws `BadgeComponent`s: `:neutral` (with a `mark` holding the content-type dot where there is one), `:warn` for a removed type, and plain `text-small dim` words for All pages and All content types;
  - `chip_class` goes;
  - `opacity-60` goes;
  - "Edit scope", "Done", "View scope" and "Hide scope" are `ButtonComponent.classes(:tertiary, size: :small)` with their words as keys, the script's `data-open-label` / `data-closed-label` read from those keys;
  - `SHORT_LABELS` become keys `admin.components.groups_screen.permission_row.short.{read,create,edit,publish,move,delete}`;
  - `accessible_label` reads them.
- Modify `scope_editor_component.{rb,html.erb}`:
  - the panel is `paper`, indented by `pl-[calc(1.25rem+0.75rem+1rem)]` (the tick column, the gap and the row's padding);
  - the removed type's chip is `BadgeComponent :warn` with "Remove" as a tertiary small button beside it, its hidden input unchanged;
  - `NOTE_INCLUDED` and `NOTE_PARTIAL` and every literal become keys;
  - the branch picker card stays `rounded-card bg-surface shadow-1`.
- Modify `members_component.rb`: `HELP`, the label, the placeholder and "Owner" become keys.
- Modify `app/controllers/admin/groups_controller.rb`: the flashes become keys.
- Modify `test/lib/admin_design_rules_test.rb`: `TYPE_SCALE_SCREENS` gains `app/components/admin/groups_screen/*` and `app/views/admin/groups/*`. `STATUS_FILL_FILES` loses the matrix and the scope editor once they draw no fill.
- Test: `test/components/admin/groups_screen/*_test.rb`, `test/integration/admin/{groups,groups_editor_states}_test.rb`, `test/lib/*`.

**Interfaces:**
- Consumes: Task 1's `BadgeComponent#with_mark`, the disabled checkbox look, `NoticeComponent`, `SettingsCardComponent`, Task 3's group zone.

- [ ] **Step 1: Write the failing tests.**
  - `list_component_test.rb`: `test "the list is a table: a group's row is one stretched link ending in Edit, Built-in a badge, a zero count in meta"`.
  - `permission_row_component_test.rb`:
    - `test "a scope chip is a badge, a type's with its dot as the mark, a removed type's warn"`;
    - `test "a locked tick has no opacity class and its note is meta"`.
  - `permission_matrix_component_test.rb`:
    - `test "content permissions and other permissions are two card frames, each area a band"`;
    - `test "a stale grant's note is the warn notice under its row"`.
  - `toggle_list_component_test.rb`: `test "the unscoped keys are one list of area bands with a switch per row, Forms after Oversight"`.
  - Review Focus 1's group test.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** The `admin--groups--permission-matrix` controller reads its labels from the button's data, which now come from keys. Its own logic is unchanged.
- [ ] **Step 4: Run.** `PGGSSENCMODE=disable bin/rails test test/components/admin/groups_screen test/integration/admin test/lib`. After a build: `admin/groups_editor_test`, `admin/groups_members_test`, `admin/users_test` (the "Manage groups →" link). Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: Groups as a table and the permission matrix in two card frames` (body: `Advances #117`).

---

### Task 8: The AI assistant (per Q1, Q5, recommended answers assumed)

**Files:**
- Modify `app/views/admin/api_tokens/{_screen,index,create}.html.erb`:
  - the heading row: "Connect an AI assistant" `text-h1`, its sentence in `text-small dim`;
  - the comment in `create` keeps the reason for `no-cache` and drops the history;
  - the words are keys in `admin.api_tokens.{index,create,screen}` (a new `api_tokens.en.yml`).
- Modify `tokens_screen/create_step_component.*`:
  - the card's heading is `text-h2` `t(".title")` ("1 · Create a token");
  - the reveal is `NoticeComponent.new(tone: :warn)` holding "Copy this token now. It won't be shown again." (`role: :default`, alert) and the copy box (Task 4);
  - Name and Group are `.admin-field`s with `_field_errors` slots (`NAME_ERROR_ID` and `GROUP_ERROR_ID` become the slots' ids);
  - every literal is a key.
- Modify `connect_step_component.*`: `t(".title")`, `t(".intro")`, the `with_token` aside as its own key, and the two labels.
- Modify `table_component.{rb,html.erb}` (Q1, Q5):
  - the card's `h2` stays at `text-h2`, then `.admin-table-scroll--x` holding the table, its first column sticky;
  - the empty state reads `t(".empty.title")` and `.empty.description` (StudioEmptyState);
  - Last used: "Never" is a key, the IP in `text-small meta`;
  - Status: `StateChipComponent.new(tone: :ok, label: t(".active"))`, or `tone: :off, label: t(".revoked"), detail:` the `TimeAgoComponent`;
  - `row_class` loses `opacity-60`, and a revoked row's cells are `text-meta`;
  - "Revoke…" is `danger_text` small;
  - the dialog's title, body and confirm are keys.
- Modify `app/controllers/admin/api_tokens_controller.rb`: the two flashes are keys.
- Modify `test/lib/admin_design_rules_test.rb`: `TYPE_SCALE_SCREENS` gains `app/components/admin/tokens_screen/*` and `app/views/admin/api_tokens/*`. `STATUS_FILL_FILES` loses `create_step_component.html.erb`.
- Test: `test/components/admin/tokens_screen/*_test.rb`, `test/integration/admin/api_tokens_test.rb`, `test/lib/*`.

**Interfaces:**
- Consumes: Task 4's `CopyValueComponent`, Task 1's `NoticeComponent`.

- [ ] **Step 1: Write the failing tests.**
  - `table_component_test.rb`:
    - `test "a token's state is a state chip: Active ok, Revoked off with its time, and a revoked row has no opacity"`;
    - `test "the table scrolls inside its card, its Name column sticky, and the empty line is a key"`.
  - `create_step_component_test.rb`: `test "a refused name draws the shared invalid edge and its message"`.
  - `test/integration/admin/api_tokens_test.rb`: `test "Create token is the page's one primary button"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** `PGGSSENCMODE=disable bin/rails test test/components/admin/tokens_screen test/integration/admin/api_tokens_test.rb test/lib`. After a build: `admin/tokens_related_posts_and_starter_pages_test`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: the AI assistant page in E4, a token's state as a chip` (body: `Advances #117`).

---

### Task 9: Sign-in, the reset, the invitation, and the password field (per Q4, recommended answer assumed)

**Files:**
- Modify `app/views/layouts/product.html.erb`:
  - the column is `mx-auto w-full max-w-[420px]`;
  - the insecure notice is above the panel;
  - `yield` is inside `div.rounded-rail.bg-surface.p-6.shadow-2.sm:p-8`;
  - the `<title>` default is `t("admin.layout.product.title")`;
  - the header is unchanged. The wordmark stays `i18n-ok`, and `RAIL_WIDTH_ALLOWED` keeps its entry, which still matches nothing at 420.

  Drop the entry if its test says it now matches nothing.
- Modify `app/views/admin/shared/_auth_heading.html.erb`: `p.admin-site-name.text-small.text-dim` and `h1.text-h1.font-semibold.text-ink.break-words`.
- Modify `app/views/admin/sessions/new.html.erb`, `admin/passwords/{new,edit}.html.erb` and `invitations/show.html.erb`:
  - every flash, the `noscript`, `expired`, `incomplete` and `used` boxes are `NoticeComponent` `:compact`, in the tone their words carry (alert and expired `:danger`, notice `:ok`, used `:neutral`), and keep their ids and their `data-*-target`s on the notice;
  - "Forgot your password?", "← Back to sign in" and Back are `ButtonComponent.classes(:tertiary, size: :small)`;
  - "Send a new link", "Request a new link" and "Sign in" are `setup_primary_button_class` with `w-full justify-center`;
  - the fields are `.admin-field`s;
  - every literal is a key in `admin.sessions.new`, `admin.passwords.{new,edit}` and `invitations.show`.
- Modify `app/controllers/admin/sessions_controller.rb` and `passwords_controller.rb`: "Try again later.", "Try another email address or password." and "Password has been reset." become keys.
- Modify `app/components/admin/ui/password_field_component.{rb,html.erb}` (PasswordField Gaps 1 and 2):
  - while `errors.any?` the input carries `aria-invalid="true"` and the root `.admin-password-field--invalid`, a rule that sets `--cs-field-invalid-border: var(--cs-danger)` on the well's bottom edge;
  - each message reads "! message" through `admin/shared/_field_errors`;
  - "Show", "Hide" and the rest hint are keys (`admin.components.ui.password_field.{show,hide,minimum}`);
  - the root carries `data-messages` of `password_field.{show,hide,strength.too_short,strength.fair,strength.good,strength.strong}`;
  - `keys:` in its contract lists them.
- Modify `app/javascript/controllers/password_field_controller.js`: `LEVELS` keeps `bars` and `colour`, and the hint and the toggle's words come from `messages(this.element).t(...)`, with `minimum` interpolated.
- Modify `test/lib/admin_design_rules_test.rb`: `TYPE_SCALE_SCREENS` gains the five views, the layout and the partial. `STATUS_FILL_FILES` loses `sessions/new`, `passwords/{new,edit}` and `invitations/show`.
- Test:
  - `test/components/admin/ui/password_field_component_test.rb`;
  - `test/integration/admin/{sessions,passwords}*`, `test/integration/invitations_test.rb`;
  - `test/lib/{admin_i18n,script_messages,admin_design_rules}_test.rb`.

**Interfaces:**
- Consumes: Task 1's `NoticeComponent`.

- [ ] **Step 1: Write the failing tests.**
  - `password_field_component_test.rb`:
    - `test "a refused password draws the danger edge and the error mark"` (the artifact's planned name);
    - `test "Show, Hide, the hint and the meter's words are keys the script reads"`.
  - An integration: `test "the sign-in page is one panel with one primary, its alerts the compact notice"`.
  - Review Focus 5's browser test, in `password_reset_test.rb`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.** The `application` entry's controllers import `i18n/messages` as the admin ones do. Confirm that `config/importmap.rb` pins the `i18n` folder for the `application` entry, and that `test/integration/public_javascript_test.rb` still says public pages load nothing of the admin's.
- [ ] **Step 4: Run.** `PGGSSENCMODE=disable bin/rails test test/components test/integration test/lib`. After a build: `admin/password_reset_test`, `admin/invites_test`, `password_field_test`, `setup_wizard_test`, `theme_toggle_test`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: the sign-in pages on one panel, a refused password drawn refused, and the password field's words as keys` (body: `Advances #117`).

---

### Task 10: Your account (per Q8, recommended answer assumed)

**Files:**
- Modify `app/views/admin/shared/_icon.html.erb`: add `key_round` (Lucide's path, 24-box, stroke 1.5 as the others).
- Modify `app/views/admin/accounts/edit.html.erb`:
  - the three cards are `SettingsCardComponent`s: Profile (`:user`, `:people`), Notes (`:message_square`, `:people`, its description as `intro`) and Password (`:key_round`, `:neutral`, the sessions sentence as `intro`, `id: "password"` with `scroll-mt-6` and the answer controller's data in `html`);
  - the permission line's `blocked` is `NoticeComponent :warn, size: :compact` with its target;
  - `ask` keeps its line in `rounded-card bg-accent-tint px-3 py-2.5 text-small text-ink`;
  - "Password changed." is `NoticeComponent :ok, size: :compact` with `tabindex="-1"` and `data-password-saved`;
  - "Forgot your current password?" is tertiary small;
  - the password form's literals ("Current password", "New password", "Confirm new password", "Change password") become keys.

  Every key is in `admin.accounts`, moved into a new `accounts.en.yml`. The file joins `CONVERTED`, and its header comment loses "which is why this file is not in the i18n test's `CONVERTED` list".
- Modify `config/locales/admin/notes.en.yml`: `admin.accounts` leaves it, except the notes keys that `notes.en.yml`'s rule says notes owns on another screen. Update `test/lib/source_layout_test.rb`'s rule if it names `accounts`.
- Modify `test/lib/admin_design_rules_test.rb`: `TYPE_SCALE_SCREENS` gains `app/views/admin/accounts/*`. `STATUS_FILL_FILES` loses `accounts/edit.html.erb`.
- Test: `test/integration/admin/accounts_test.rb`, `test/lib/{source_layout,admin_i18n}_test.rb`, `test/components/previews_test.rb` (the icon in `FoundationIcons`' list, if a test lists icons).

**Interfaces:**
- Consumes: `SettingsCardComponent`, `NoticeComponent`, Task 9's password field.

- [ ] **Step 1: Write the failing tests.** In `accounts_test.rb`:
  - `test "the three cards are card frames, the password card anchored at #password"`;
  - `test "a saved password is the compact ok notice and a blocked permission the warn notice"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** `PGGSSENCMODE=disable bin/rails test test/integration/admin/accounts_test.rb test/lib`. After a build: `admin/account_password_answer_test`, `admin/notes_alert_test`, `password_field_test`. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: Your account in the card frame` (body: `Advances #117`).

---

### Task 11: System status, the 403 and the 404 (per Q9, Q10, recommended answers assumed)

**Files:**
- Modify `app/views/admin/system_status/show.html.erb`:
  - the heading row: "System status";
  - under it `t(".summary", passed:, total:, time: I18n.l(Time.zone.now, format: :"admin.time"))` in `text-small meta`;
  - "Run checks again" stays secondary;
  - the results are drawn in `div.rounded-card.bg-surface.shadow-1` with `list_class: "divide-y divide-line px-4"`.

  The words go in a new `system_status.en.yml`.
- Modify `app/views/setup/_system_check_results.html.erb`: `list_class:` (decisions table).
- Modify `app/views/admin/errors/{forbidden,not_found}.html.erb` (Q10):
  - `IconChipComponent.new(icon: :circle_alert, family: :neutral)` over the code;
  - the code in `text-label meta`, `h1.text-h1`, the sentence `text-ink`, and the advice `text-small meta`;
  - the way back is `ButtonComponent.classes(:secondary)`;
  - every literal, the titles included, is a key in `admin.errors.{forbidden,not_found}` (a new `errors.en.yml`).

  The denial `message` stays the service's English.
- Modify `test/lib/admin_design_rules_test.rb`: `TYPE_SCALE_SCREENS` gains `app/views/admin/system_status/*` and `app/views/admin/errors/*`. The centred test is unchanged.
- Test: `test/integration/admin/system_status_test.rb`, `test/integration/admin/access_control_test.rb` (the 403 and 404 words), `test/integration/setup_*` (the wizard's frame), `test/lib/*`.

**Interfaces:**
- Consumes: Task 4's row.

- [ ] **Step 1: Write the failing tests.**
  - `system_status_test.rb`: `test "the checks are one card, warnings first, and the summary names the count and the site's time"` (the time through `I18n.l(…, format: :"admin.time")`, which `config/locales/en.yml` already holds).
  - `access_control_test.rb`: `test "the 403 and the 404 are centred messages with a neutral chip and one secondary way back, in keys"`.
  - A setup integration: `test "the wizard's check list keeps its own frame"`.
- [ ] **Step 2: Run them, and verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** `PGGSSENCMODE=disable bin/rails test test/integration test/lib`. After a build: `admin/system_status_and_preview_test`, `setup_wizard_test`, `admin/media_library_test` (the 404's nearer way back). Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: System status in one card, and the 403 and 404 in E4` (body: `Advances #117`).

---

### Task 12: The mails, a reduced E4 (decision 5; Q11, recommended answer assumed)

**Files:**
- Modify `app/views/mails/_button.html.erb`: the link's style is `display:inline-block;padding:12px 20px;background:#6236d9;color:white;text-decoration:none;border-radius:8px;font-weight:600;`. Nothing else changes, and the address line under it stays `dimgray`.
- Modify `app/views/layouts/mailer.html.erb`:
  - the head gains `<meta name="color-scheme" content="light">` and `<meta name="supported-color-schemes" content="light">`;
  - the colours stay named (`whitesmoke`, `white`, `black`, `dimgray`);
  - the comment says: the violet is the button's alone, the one literal the design rules admit in a mail, and it is `--cs-accent`'s light value.
- Modify `app/views/forms_mailer/submission.html.erb`: only its comment, which names the layout's colours (it has no button).
- Modify `test/lib/admin_design_rules_test.rb` (decisions table):
  - `test "a mail's one colour literal is the accent's violet, on the button alone"`;
  - `test "no colour literal in CS Studio's sources or a mail's, but the mail's violet"`, extending the raw-colour scan to `MAIL_SOURCES`, with a pattern test whose samples are `#6236d9` (admitted in a mail source, refused in an admin source) and `#6236DA` and `#000` (refused in a mail source).
- Modify `test/lib/admin_contrast_test.rb`: `test "a mail button's white words on the violet are 4.5:1"`, with a floor of 6.9 (white on `#6236d9`).
- Modify `test/mailers/{passwords,invites}_mailer_test.rb`: `test "the button is the violet with white words and an 8px radius, and the address follows it as text"`. Modify `test/mailers/application_mailer_test.rb` (or the layout's test): `test "the layout says the mail is light only and names its colours"`.
- Test: `test/mailers`, `test/lib/{admin_design_rules,admin_contrast,mail_guards}_test.rb`.

**Interfaces:** none.

- [ ] **Step 1: Write the failing tests** above.
- [ ] **Step 2: Run them, and verify they fail.** `PGGSSENCMODE=disable bin/rails test test/mailers test/lib/admin_design_rules_test.rb test/lib/admin_contrast_test.rb`.
- [ ] **Step 3: Implement.** Open each mail's preview (`test/mailers/previews`) with `bin/rails runner` rendering `PasswordsMailer` and `InvitesMailer` in the preview's way, and check that the HTML holds `#6236d9` once.
- [ ] **Step 4: Run** the same command. Expected: PASS.
- [ ] **Step 5: Comments and commit.** Commit `feat: the mails' one button is CS Studio's violet` (body: `Advances #117`).

---

### Task 13: The reference, CLAUDE.md, the pull request and the Design System cards

**Files:**
- Modify `docs/reference/design-system.md`:
  - a new part "E4: people and system", after "E4: the content-side screens":
    - the lists as tables with `.admin-row-link` and "Edit";
    - the users' avatars and badges;
    - the user and group editors in the card frame, the group tiles, the matrix's two frames and bands, and the badge chips;
    - the action zone;
    - the AI assistant and the copy box;
    - Your account;
    - System status in one card;
    - the auth panel;
    - the 403 and 404;
    - the mails' violet.
  - "Shared components" gains `NoticeComponent`, `ActionZoneComponent`, `CopyValueComponent`, `BadgeComponent`'s `mark`, and the disabled checkbox look. `CheckboxComponent`'s line loses "50% opacity". The paragraph "The type scale on these screens" names `TYPE_SCALE_SCREENS`.
  - "Rules a change can break silently" gains:
    - a notice's role is its tone's, and inside a live region none (`role: nil`), with **no guard** for a notice dropped into another `aria-live` region with its role;
    - a copy box never writes its value into an attribute, with **no guard** for a caller that passes the value in `source_data` or `html`;
    - `.admin-row-link` makes one link cover its row, so anything else pressable in the row stands at `--cs-z-raised`, with **no guard** for a second control left under the stretched link.
- Modify `docs/reference/users-groups-tokens.md`: the Users, Groups and AI assistant paragraphs (the tables, the tiles, the frames, the zone, the badge chips, the state chips, the copy script).
- Modify `docs/reference/mail.md`, "The mails": replace "a design question left open" with the decision (the violet, `MAIL_ACCENT`, the guard, `color-scheme: light`).
- Modify `docs/reference/hosting.md`, "What a person is told": the plain-HTTP notice draws through `NoticeComponent`. System status's frame.
- Modify `docs/reference/i18n.md`:
  - "Files" gains the seven new locale files and `accounts.en.yml`;
  - "Left over" gains nothing new, and loses nothing but what this stage converted;
  - "Out of scope" keeps `Setup::SystemCheck`, adding that the row's own words are keys now.
- Modify `docs/reference/forms.md` ("CS Studio"): the trash zone is the shared action zone.
- Modify `CLAUDE.md`:
  - the design-system index line names `NoticeComponent`, `ActionZoneComponent`, `CopyValueComponent` and `.admin-row-link`;
  - the users, groups and tokens index line names `ActionZoneComponent`;
  - the mail index line names `MAIL_ACCENT`;
  - "Rules a change can break silently" gains the three no-guard rules above under `docs/reference/design-system.md`.
- Modify `CHANGELOG.md`, `## Unreleased`, **Changed**:
  - Users, Groups and the AI assistant's tokens are tables in one card. A row opens its editor from anywhere on it. People are shown by their circles, and groups and badges by their words.
  - The user and group editors, and Your account, are drawn in the Settings card frame. A group the person holds is a tile with an outline. The permission matrix is two cards.
  - Every notice in CS Studio is one look: the warn ones bordered in amber, the stale banner and the insecure notice among them.
  - Sign-in, the password reset and the invitation stand on a panel. A refused password shows its edge and its message.
  - System status is one card. A token's state is a chip.
  - The mails' button is CS Studio's violet.
- Modify `CHANGELOG.md`, **For a gem or an outside caller**:
  - `Admin::Ui::NoticeComponent`, `ActionZoneComponent` and `CopyValueComponent` exist.
  - `BadgeComponent` takes a `mark`.
  - `admin--ui--clipboard` copies its source's text and reads its words from `ui.copy_value.*`.
  - `admin--tokens--reveal` has no `copy` action.
  - `setup/_system_check_results` takes `list_class:`.

  List under **Removed**:
  - `InsecureNoticeComponent::BASE_CLASS`;
  - `UsersScreen::ListComponent::COLUMNS`;
  - `GroupsScreen::ListComponent::COLUMNS`;
  - `PermissionRowComponent::SHORT_LABELS`;
  - `GroupCardsComponent::CARD`, `OPEN_CARD` and `LOCKED_CARD`;
  - the CSS hooks `admin-delete-zone` and `admin-owner-zone`.
- Test: `PGGSSENCMODE=disable bin/rails test test/lib`, `bin/rubocop`, `bin/rails zeitwerk:check`, `bin/brakeman`, `bin/changelog-guard main`.

- [ ] **Step 1: Write the reference, CLAUDE.md and CHANGELOG changes.** Then run `gh issue list --label architecture-review --state open` again. If a new issue's code was rewritten by a task, take that issue into the task that owns the code.
- [ ] **Step 2: Run** the five checks. Expected: all pass, and `KEYBOARD_NOT_YET` is empty.
- [ ] **Step 3: Write the PR body.**
  - Findings: Advances #117 (every task). The architecture-review check (below).
  - "For the owner to check": Q1–Q11 as built, and the rulings C1–C6 (below).
  - Documentation, in `/Users/dknafelj/src/contentspiel-docs`, for all three readers:
    - **Editors:**
      - `docs/editors/getting-started/sign-in.md` (the panel, the reset and its states);
      - the account page, `docs/editors/getting-started/your-account.md` or wherever it is (`git grep -l "Your account"` there): the cards, the password's answer, the notes switches.
    - **Administrators:**
      - `docs/administrators/people/users.md` (the table, the circles, invites, the editor's cards and group tiles, the owner and delete zones);
      - `docs/administrators/people/groups.md` (the table, the two permission cards, the chips);
      - `docs/administrators/people/the-audit-log.md` (only if it describes the row's link);
      - `docs/administrators/site/system-status.md`;
      - the AI assistant page (`git grep -l "AI assistant"`);
      - `docs/administrators/site/mail.md` (the mails' button).

      Retake each one's screenshots in both themes.
    - **Integrators:**
      - `docs/integrators/theming/extending-cs-studio.md` (`NoticeComponent`, `ActionZoneComponent`, `CopyValueComponent`, the badge's `mark`, the clipboard's words);
      - `docs/integrators/how-it-works/how-the-cms-is-put-together.md` if it names a removed constant.
- [ ] **Step 4: List the Design System cards to redraw**, for the design agent after merge:
  - `Alerts`:
    - Gap 1 closed;
    - Gap 2 built as `NoticeComponent` (tones, sizes, `role: nil`), with every box it took and the files that kept their fills;
    - `CopyValueComponent` as the row's command;
    - InsecureNotice's and MailFailedNotice's previews still to make (Gap 3 stays).
  - `PatternDestructiveActions`: the delete zone is `ActionZoneComponent` (a `line` rule, no box), with its keys, the owner zone and the forms' trash zone (C2).
  - `StudioListTable`: the users list's gaps closed; Users, Groups and Tokens as tables with `.admin-row-link` and "Edit".
  - `Badge`: the `mark` slot and the scope chips.
  - `FormControls`: Gap 1 built.
  - `PasswordField`: Gaps 1 and 2 built.
  - `StudioEmptyState`: the tokens' keys.
  - `StudioSettings`: `SettingsCardComponent`'s new users (the user and group editors, the matrix, Your account).
  - `Mails`: the violet button at 8px, `MAIL_ACCENT`, `color-scheme: light`, and its open question closed by decision 5 (C3).
  - `StateChip`: a token's Active and Revoked.
  - `FoundationIcons`: `key_round`.
  - The new cards, from Decided to built: StudioUsers, StudioGroups, StudioTokens, StudioAccount, StudioSystemStatus, StudioSignIn, StudioErrors, ActionZone and CopyValue.
- [ ] **Step 5: Check no test run is left**: `pgrep -f "rails test"` prints nothing.
- [ ] **Step 6: Commit** `docs: E4 stage 7b in the reference, CLAUDE.md and the changelog` (body: `Advances #117`).

---

## Architecture-review findings

Checked on 2026-11-10 against every open issue labelled `architecture-review`. Task 13 runs the check again.

| Issue | Taken | Why |
|---|---|---|
| #117 comments about invariants | advances, every task | the users, groups, tokens and auth files carry "round 3 Task 12", "handoff §4.9", "§10 B28", "design answer M4/M5/M7", "C37", "fix round 1" and "spec §6.1"; each task rewrites the comments of the files it touches |
| #133 entry cost of a system test | not taken beyond the rule | its remainder (shorter names) is not in these files. The rewritten tests begin on `visit_screen`, and the product layout's on its own wait |
| #127 slots fit one shape | not taken | no slot changes; the sidebar's modules are unchanged |
| #132 split the largest scripts | not taken | `reveal_controller.js` shrinks, `clipboard_controller.js` gains one fallback, and `password_field_controller.js` gains its messages; none is a file the finding names |
| #124 admin scripts on demand | not taken | `password_field_controller.js` imports `i18n/messages` in the `application` entry; Task 9 checks that the public map is unchanged |
| #130 audit events as an extension point | not taken | the audit row gains a class, not a way to register |
| #139 compatibility code before the first release | closed, nothing left | the old reset route the spec names is already gone (`git grep legacy config/routes.rb` prints nothing) |
| #112, #114, #116, #119, #121, #122, #128, #129, #131, #135–#138, #141–#143, #185 | not taken | no task changes their code |

## Browser tests

Run locally after `bin/rails tailwindcss:build`, one file per command, only while the one-minute load is under 6 and no `rails test` runs, each prefixed with `PGGSSENCMODE=disable`. The spec's files for 7b are all run:
- `users_test`, `groups_test`, `groups_editor_test`, `groups_members_test`, `invites_test`;
- `password_reset_test`, `account_password_answer_test`, `system_status_and_preview_test`, `view_only_test`.

**The implementer must run:**
- Task 1: `admin/audit_log_test`.
- Task 2: `admin/changed_elsewhere_test`, `admin/editing_live_test`, `admin/publish_dialog_steady_test`, `admin/languages_test`, `admin/settings_mail_test`, `setup_wizard_test`, `admin/view_only_test`, `admin/groups_editor_test`.
- Task 3: `admin/users_test`, `admin/groups_members_test`, `admin/form_builder_test`, `admin/pending_lock_test`.
- Task 4: `admin/system_status_and_preview_test`, `admin/tokens_related_posts_and_starter_pages_test`, `admin/editor_header_test`.
- Task 5: `admin/users_test`, `admin/invites_test`.
- Task 6: `admin/users_test`, `admin/invites_test`, `admin/pending_lock_test`, `password_field_test`.
- Task 7: `admin/groups_editor_test`, `admin/groups_members_test`, `admin/users_test`, `admin/groups_test`.
- Task 8: `admin/tokens_related_posts_and_starter_pages_test`.
- Task 9: `admin/password_reset_test`, `admin/invites_test`, `password_field_test`, `setup_wizard_test`, `theme_toggle_test`.
- Task 10: `admin/account_password_answer_test`, `admin/notes_alert_test`, `password_field_test`.
- Task 11: `admin/system_status_and_preview_test`, `setup_wizard_test`, `admin/media_library_test`.

**Likely to change, left to CI** (the whole browser suite runs per PR):
- `admin/settings_test`, `admin/ai_settings_test` (Task 2's Settings boxes);
- `admin/editing_take_over_test`, `admin/editing_merge_test` (the live region's line);
- `admin/dialogs_hang_test` (the zones' dialogs);
- `admin/form_width_test`, `admin/field_error_border_test` (the auth panel, the shared invalid edge);
- `shell_test` (the insecure notice in the shell).

A CI failure is fixed in the task that owns the file.

## Pre-flight

Done while writing this plan, against `main` at d99b0dc1 and the artifact at `1794289718-612a`. No test database exists in this worktree, so nothing was run.

- **Red mid-stack.**
  - Task 1 renames a guard list that 7a's files sit in.
  - Task 2 changes the markup of boxes that editor browser tests read.
  - Task 3 moves the forms zone (7a's) onto the shared zone.
  - Task 4 changes a script the editor's header uses.
  - Task 9 changes the password field, which six screens render.

  Each fixes the tests it breaks.
- **A file changed in two tasks.**
  - `content-spiel.tailwind.css`: Tasks 1, 6 and 9, each in its own rules.
  - `admin_design_rules_test.rb`: Tasks 1, 2, 5 to 12.
  - `users_screen.en.yml`: Tasks 3, 5 and 6.
  - `groups_screen.en.yml`: made in Task 3, grown in Task 7.
  - `create_step_component.*`: Tasks 4 and 8.
  - `system_check_row_component.*`: Task 4 alone.
  - `design_system_entries.rb`: Tasks 1, 3 and 4.
  - `ui_contract.rb`: Task 1 adds to `KEYBOARD_NOT_YET`, and Task 6 empties it.
- **Keys before their reader.** Each key arrives in the task that reads it. `ui.copy_value.*` arrives in Task 4, before Tasks 8 and 11 lay the box out.
- **Guard lists.**
  - `MADE_BEFORE_CONTRACT` is unchanged at 40, and the three new components are not on it.
  - `HAND_BUILT_AVATAR_ALLOWED` loses the users list (Task 5).
  - `CARD_BORDER_ALLOWED` gains the notice and loses the two named notices (Tasks 1 and 2).
  - `STATUS_FILL_FILES` shrinks in Tasks 2, 5, 7, 8, 9 and 10, and gains only `notice_component.rb`.
  - `CONVERTED` grows in Tasks 3 to 11.
  - `TYPE_SCALE_SCREENS` grows in Tasks 5 to 11.
- **Tests a mutation would not fail.**
  - The mail colour guard's samples are admitted and refused in both kinds of source.
  - The alert-box guard's samples are today's real boxes.
  - The stretched-link guard refuses the hand string anywhere.
- **Not reproduced while planning.**
  - Whether `position: relative` on a `<tr>` holds a stretched `::after` in Chrome inside an `overflow-x: auto` box. Task 5 tries it first. If it fails, the users and groups tables keep their `<ul>` with `role="table"` (Q1's alternative), and the plan's Q1 says so before Task 7.
  - Whether the `application` import-map entry already pins `i18n/messages`. Task 9 checks first.

### Conflicts found, and rulings

| C | Conflict | Ruling | Why |
|---|---|---|---|
| C1 | The spec's 7b browser list names `groups_test`, but that file tests a `groups` *field* (speakers), not the Groups screen. The Groups screen's browser tests are `groups_editor_test` and `groups_members_test`. | Run all three. Only the latter two exercise this stage's code. | The spec's list is a filename match. |
| C2 | The artifact's PatternDestructiveActions keeps the group delete zone "unchanged (a `cs-line` frame, `cs-radius`)", against the spec's rule 3 (no new border for depth) and 7a's forms zone (a `line` rule). | **For the owner (Q3).** One `ActionZoneComponent` on a `line` rule, with no box. | The spec is the approved document, and 7a built the rule. |
| C3 | The artifact's Mails card still says "named colours only", "the button is black" and an open question, while the spec's decision 5 settles a violet `#6236d9` button. | The spec wins, and the card is redrawn (Task 13). | The decision is later and approved. |
| C4 | The spec's 7b names only the people and system screens, and says no behaviour beyond layout. The artifact's Alerts Gap 2 (decided by the owner) puts `NoticeComponent` and the editor's boxes "in the same PR" as 7b. | Task 2 does the sweep, as the artifact decided. It changes looks and roles, never behaviour. | An owner's decision. Review Focus 4 holds the roles. |
| C5 | The spec's #139 row: "7b restyles the reset views but not the legacy route". The route is gone and #139 is closed. | Nothing to do. | Already done. |
| C6 | The spec says the mail views' violet is "a named exception in `admin_design_rules_test`", but `app/views/mails/` and the mailers' views are not scanned by the colour guard today. Only `layouts/mailer.html.erb` is. | Task 12 extends the scan to every mail view first, and then admits `#6236d9` in mails alone. | An exception to a rule that does not read the file guards nothing. |
| C7 | The spec's rule 6 gives list and system screens "a filter bar". Users, Groups, Tokens and System status have nothing to filter. | None of them gets a filter bar (Q1). | A bar with nothing in it is dead space, which the spec's "Why" names. |
| C8 | `view_only_test` is in the spec's 7b list, but it tests the editors' read-only views, which 7b does not redraw. | It is run after Task 2, whose notices reach the editors' view-only lines. | The only 7b code it meets. |
