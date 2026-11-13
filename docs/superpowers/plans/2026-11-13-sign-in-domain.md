# The sign-in domain under `SignIn::` — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every sign-in class lives under one domain namespace, `SignIn::`, at most two levels deep, with two guard tests holding its shape: no sub-namespace shadows a top-level constant, and code outside the domain reaches it only through named entry points.

**Architecture:** A mechanical rename. The layer folders stay (`app/models`, `app/services`, `app/jobs`); Zeitwerk maps the one namespace across them (`app/models/sign_in/passkeys/policy.rb` and `app/services/sign_in/passkeys/add.rb` are both `SignIn::Passkeys::`). One commit per sub-namespace, the suite green at each. No behaviour changes, no logic edits, no stored string changes.

**Tech Stack:** Rails 8.1, Zeitwerk, Minitest with fixtures, Solid Queue recurring jobs.

**Spec:** none. The owner-agreed decisions below are the spec.

**Base:** `main` at `31807a81`, the SSO pull request (#251) merged. The worktree is `/Users/dknafelj/src/ContentSpiel-sign-in-domain`, branch `sign-in-domain`. The plan was first written against `sso` at `0c1b4878` and brought up to date with `31807a81`: every file, call site, grep and allow-list entry below is as it stands there. The SSO fixes after `0c1b4878` that it takes in are `Sso::LinkedEvent` (the one writer of `sso.linked`), the public `Sso::Admit.refuse`, `Sso::Admit::Answer`, `Sso::Unlink#mailed?`, `Sso::Link` without `via:`, the span reason constants on `SignIn::Oidc` (`DISCOVERY_REASONS`, `DISCOVERY_HTTP_REASON`, `RECHECK_REASONS`, `.discovery_reason?`), the `age_limit:` keyword of `IdToken.verify`, the `filter_parameters` lambda, and the user form's linked-account line (`app/views/admin/users/_form.html.erb`). Task 1 Step 1 still takes the inventory again before anything moves.

---

## Decisions (owner-agreed)

1. **The target tree.** Layer folders stay: app/models, app/services, app/jobs. Zeitwerk maps one namespace across them.
   - `SignIn::Protection`: throttle, bot_check, known_device, and the lockout mail job.
   - `SignIn::Password`: password_attempt, leaked_password, and the leaked-password rule now in app/services/users.
   - `SignIn::Passkeys`: relying_party, passkey_registration, passkey_check, passkey_credential, `Passkeys::Policy`, and the services `Passkeys::Add`, `Remove` and `Rename`.
   - `SignIn::RecoveryCodes`: `RecoveryCodes::Generate`, plus the recovery-code part of proof if it separates cleanly. If not, leave it and say why.
   - `SignIn::Sso`: everything in `SignIn::Oidc` and the `oidc/` folder, folded flat (`SignIn::Sso::IdToken`, not `SignIn::Sso::Oidc::IdToken`); the services `Sso::Admit`, `Link` and `Unlink`, and the mixin `Sso::LinkedEvent`; and `Sso::RecheckJob`. Keep `Invitations::AcceptWithSso` under Invitations unless it is clearly sign-in's, and state the call.
   - `SignIn::Sessions`: `Sessions::End`, `EndAll` and `EndOthers`, and `Sessions::SweepJob`.
   - The `SignIn::` root keeps the shared core: `SignInRules` becomes `SignIn::Rules`, `SignInMethods` becomes `SignIn::Methods`, plus proof, spent_challenge, outside_call and **outcome**. Owner's correction (2026-11-13): `SignIn::Outcome` stays in the root, not in `Protection`. It is shared: both `Password::Attempt` and the root's `Proof` answer one, and its statuses are the root's `SignIn::OUTCOMES`. It keeps its name and file (`app/models/sign_in/outcome.rb`) and is not renamed.
2. **Nothing goes deeper than two levels,** and no sub-namespace exists for a single file unless the decision above gives it one.
3. **The models stay top-level:** `User`, `Session`, `Passkey`, `RecoveryCode`, `Invitation`. No `table_name` or fixture churn. No sub-namespace is named like a top-level model (`Sessions` and `Passkeys` are plural for this reason), and a shadow guard holds it.
4. **The screens stay `Admin::`:** controllers, their concerns (`app/controllers/concerns/admin/`, `passkey_challenges.rb`, `sso_starts.rb`) and components. Spec §9 draws this line: only screens, routes and session handling are CS Studio's own.
5. **`AccessControl` stays separate.**
6. **The gem hook keeps its name,** `ContentSpiel::Plugins.sign_in_methods`; only the registry constant moves. Gem-facing docs are updated.
7. **The public-surface guard** is a new test in the style of `dependency_direction_test`:
   - Code outside `SignIn::` (controllers, components, other domains, jobs, MCP) may reference only a named allow-list of `SignIn::` entry points, each with a one-line reason. Derive the list from the call sites as they stand.
   - `SignIn::` references nothing in `Admin::`, no component, no controller and no url_helpers.
   - The guard fails on an allow-list entry that matches nothing.
8. **The shadow guard:** no `SignIn::` sub-namespace shares a name with a top-level constant from `TopLevelNames`, or the guard explains why it is safe.
9. **The refactor is mechanical.** No behaviour change, and no logic edits beyond the renames. Use one commit per sub-namespace, with the full suite green at each. Tests move to mirror the new paths (`test/models/sign_in/passkeys/…`).
10. **Every other place a name is written changes with it:**
    - config/recurring.yml job class names;
    - any serialized job class name;
    - audit `subject` or type strings, if a class name is stored. Check the audit schema and say whether any stored string holds a class name. If one does, that rename needs a data migration; prefer not renaming what is stored, and say so.
    - i18n scopes keyed by class name (`Admin::AdminComponent`-style lookups), `filter_parameters`, Telemetry attribute lists, the CLAUDE.md reference index, docs/reference/*.md, the brakeman ignore (it is keyed by file path), and the CHANGELOG.
11. **CHANGELOG, the unreleased names.** The SSO PR added `Sso`, `SignInRules` and `SignInMethods` under "Breaking" as new top-level names (three lines at `31807a81`). None was ever released, so their Breaking "new top-level name" lines are **deleted**, not mapped to the new names and not rewritten: `SignIn` was already top-level in 0.3.0, so `SignIn::Rules`, `SignIn::Methods` and `SignIn::Sso` add no name a gem's owner is refused by, and a Breaking line naming them would say something false. Likewise the passkeys line drops `Passkeys` and `RecoveryCodes` (never released either). The unreleased section ends up describing the final state. Check that the passkeys and backend-path PRs' unreleased lines are also accurate after the move.
12. **Released names are renamed, with no alias** (owner's ruling, 2026-11-13). CLAUDE.md allows no compatibility code ("No compatibility code before it is needed"), so a constant released in 0.3.0 is renamed outright, with no alias, `const_missing` or deprecation shim, and **one** Breaking line in the unreleased section maps each old name to its new one. The 0.3.0 (`v0.3.0`) names this plan renames are `SignIn::Throttle`, `BotCheck`, `KnownDevice`, `LockoutMailJob` (→ `SignIn::Protection::…`), `SignIn::PasswordAttempt` (→ `SignIn::Password::Attempt`), `SignIn::LeakedPassword` (→ `SignIn::Password::Leaked`), `Users::LeakedPasswordRule` (→ `SignIn::Password::LeakedRule`) and `Sessions::End`, `EndAll`, `EndOthers`, `SweepJob` (→ `SignIn::Sessions::…`). `SignIn::Outcome`, `SignIn::OutsideCall` and `SignIn.store`, also released, keep their names.

## Calls this plan makes where the decisions leave a choice

- **Names drop the word the namespace already says:** `PasswordAttempt` becomes `Password::Attempt`, `LeakedPassword` becomes `Password::Leaked`, `Users::LeakedPasswordRule` becomes `Password::LeakedRule`, and `PasskeyRegistration`, `PasskeyCheck` and `PasskeyCredential` become `Passkeys::Registration`, `Check` and `Credential`. Every other class keeps its own name. This follows the `Oidc::IdToken` to `Sso::IdToken` fold.
- **`SignIn::Proof` stays whole at the root.** `#recovery_code` is one of three methods that share the private `prove`/`decide`, the reservation, the rule check and the span. Splitting it out would be a logic edit. `SignIn::RecoveryCodes` holds only `Generate`.
- **`Invitations::AcceptWithSso` stays under Invitations.** It is an invitation acceptance: it includes `Invitations::Acceptance`, mirrors `Invitations::Accept` and makes the account. Sign-in's `SignIn::Sso::Admit` only calls it.
- **These stay outside `SignIn::`**, because no decision names them and each belongs to another kind: `SignInMailer` (a mailer, whose view folder is its name), `PasswordResetRequestJob`, `Users::LastSignIn` (a query of the Users screen), and the test helpers `OidcHelper`, `PasskeyHelper` and `SignInHelper`. `OidcHelper` names the protocol its fake provider speaks, not a class.
- **The sub-namespaces other than `Sso` are implicit** (directories only, no `.rb` file). The root `app/models/sign_in.rb` comment lists the six. `SignIn::Sso` is explicit because `oidc.rb` already holds its constants and methods.
- **`config/initializers/sign_in_methods.rb` keeps its file name.** It is named after the hook (decision 6), and `lib/content_spiel/plugins.rb` cites it by path.
- **"Full suite green at each" means** `bin/rails test`, `bin/rails zeitwerk:check`, `bin/rubocop`, `bin/brakeman` and the browser tests of the area each task moves. The whole browser suite and `bin/ci` run once, in Task 10.
- **Two levels is guarded too.** The shadow guard also fails on a directory three levels down (`app/*/sign_in/*/*/`), so decision 2 has a test.
- **The hook's line under "For a gem"** names `SignIn::Methods` (decision 11 deletes only the Breaking "new top-level name" lines).
- **`Sso::LinkedEvent` moves with Sso** (`app/services/sign_in/sso/linked_event.rb`), as a mixin of the services that link an account. `Invitations::AcceptWithSso` includes it from outside the domain, so it is an entry point of the public-surface guard.
- **`Admin::Ui::OrDividerComponent` and `Admin::Ui::WayInButtonComponent` stay `Admin::Ui::`** (decision 4). `OrDividerComponent` names nothing of sign-in; `WayInButtonComponent` names `SignInMethods` in a comment only, renamed in Task 2.

## Where the code contradicts the decisions

- **Decision 11 as first written ("rewrite those lines, nothing released is renamed")** is replaced by decisions 11 and 12 above. 0.3.0 shipped `SignIn::Throttle`, `BotCheck`, `KnownDevice`, `Outcome`, `PasswordAttempt`, `LeakedPassword`, `OutsideCall`, `LockoutMailJob`, `Users::LeakedPasswordRule`, `Sessions::End`, `EndAll`, `EndOthers` and `Sessions::SweepJob`, and its CHANGELOG names `Sessions::SweepJob`, `Sessions::EndAll` and `SignIn.store`. Decision 1 renames all but `Outcome`, `OutsideCall` and `SignIn.store`; Task 10 adds the one Breaking line decision 12 asks for.
- **Decision 11, the `Sso` Breaking line:** at `31807a81` the unreleased section has all three lines, `SignInMethods`, `SignInRules` and `Sso` (`app/services/sso/`, `app/jobs/sso/`). Task 10 deletes the three. The passkeys line names `Passkeys` and `RecoveryCodes` as new top-level names; after the move they are not top-level, so Task 10 drops them from it.
- **Decision 4 and spec §9:** §9 makes "session handling" CS Studio's own. `SignIn::Sessions` ends CS Studio's `Session` rows, and `SignIn::Sso::Admit/Link/Unlink` and `SignIn::Passkeys::Add/Remove/Rename` write CS Studio's `User`. So `SignIn::` holds both the shared layer §9 describes and CS Studio's account services. The root comment in `app/models/sign_in.rb` ("Nothing here knows a session, a cookie, a route, a controller or a mail") stops being true. Task 10 rewrites it to say which sub-namespaces are the shared plain objects (Protection, Password, the ceremonies in Passkeys, Sso's protocol objects, the root) and which act on CS Studio's accounts.
- **Decision 1, `Outcome`:** resolved by the owner's correction. `SignIn::Outcome` stays at the root, so `Proof` and `Password::Attempt` keep reaching it by the bare name `Outcome` through `module SignIn`, and no line that names it changes.
- **Decision 10, audit and stored names:** nothing stored holds a moved class name, so no data migration is needed. Details:
  - `audit_events.subject_type` and `actor_type` hold `polymorphic_name`, and only of the models, which stay.
  - `SignIn::SpentChallenge` stays and sets `table_name = "sign_in_spent_challenges"` itself.
  - `sessions.authenticated_with` holds words (`sso`), not class names.
  - The only serialized class names are Solid Queue's: a job row's `class_name` and the payload's `job_class`. See Review Focus 1.
- **Decision 10, other places:**
  - No i18n scope is keyed by a moved class. The service locale comments name classes in prose only.
  - `filter_parameters` names `SignIn::BotCheck` in a comment only. The single sign-on lambda added after `0c1b4878` (`code`, `state`, `nonce`, request logs only) names no class, and no substitution may touch it.
  - No Telemetry list holds a class name, but the `error.type` *value* is `error.class.name` (Review Focus 2).
  - `brakeman.ignore` is keyed by file *and* by the code text. Its file (`sso_starts.rb`) does not move, but the code names `SignIn::Oidc::Authorization`, so the fingerprint changes (Task 8).

## Global Constraints

- Every moved file keeps the nested form, one `module` per line: `module SignIn` / `module Passkeys` / `class Add`. Never the compact `class SignIn::Passkeys::Add`. Bare references (`OutsideCall`, `Policy`, `Link`, `Credential`) resolve through that lexical nesting.
- Move with `git mv`, so history follows the file.
- Change no string literal, cache key, HMAC purpose, span name, i18n key, cookie name or table name, even when it spells an old name:
  - `"content_spiel/oidc/…"`
  - `KEY_PURPOSE`, `SPENT_PURPOSE`
  - `auth.sso.*`
  - `sign_in_spent_challenges`
  - The exceptions are strings that are class names by design: test assertions on `error.type`, job class lists, `service_calls.rb` keys, `recurring.yml`, `brakeman.ignore`.
- Comments are renamed with their code. A comment's sense is not rewritten until Task 10.
- No alias, no `const_missing`, no deprecation shim.
- Commit messages: `ref: …` (conventional commits, as the history uses). End each with the session's attribution lines.
- Never define `Admin::<Domain>`. Nothing new goes under `Admin`.

## Review Focus

1. **A class name stored or serialized.** A `SignIn::LockoutMailJob`, `Sessions::SweepJob` or `Sso::RecheckJob` row queued before the upgrade fails to deserialize afterwards (NameError, a failed execution). `solid_queue_recurring_tasks` is rewritten from `config/recurring.yml` at the scheduler's start. Expected: recurring.yml names the new classes in all three environments, and the CHANGELOG's Breaking line warns that a lockout mail queued at the moment of upgrade is not sent. Pinned by `sweep_job_test` and `recheck_job_test`, which assert the schedule's `class` string (Tasks 7 and 8).
2. **A class name inside a string.**
   - `OutsideCall` puts `error.class.name` into a span's `error.type` and a log line: `SignIn::LeakedPassword::Unavailable` becomes `SignIn::Password::Leaked::Unavailable`, and a Honeycomb query on the old value goes quiet.
   - `test/support/service_calls.rb` keys services by name string, with `callers:` file paths. `service_behaviour_contract_test` holds a name list, and `mail_guards_test` keys by file path.
   - `brakeman.ignore` holds the code text and a fingerprint.
   - `Sso::RecheckJob` reports a raised re-check as `Sso::RecheckJob::RecheckFailed` (`Rails.error.report`): an error tracker that groups by class sees `SignIn::Sso::RecheckJob::RecheckFailed` as a new error; `recheck_job_test` asserts the class (`assert_error_reported`).
   - Expected: each changes in the task that moves its class, and `leaked_test` asserts the new `error.type` (Task 4).
3. **A bare constant that resolved by lexical scope.** Examples: `BotCheck` in `PasswordAttempt`, `PasskeyCredential` in the ceremonies, `Oidc.error_type` and `Oidc.discovery_reason?`, `Policy` in `Passkeys::Remove`, `Link` in `Sso::Admit`, `include LinkedEvent` in `Sso::Link`, `include Sso::LinkedEvent` in `Invitations::AcceptWithSso`, `include LeakedPasswordRule` in `Users`. (`Outcome` in `PasswordAttempt` and `Proof` stays at the root and keeps resolving.) Each breaks when its target moves to a sibling namespace or a file loses its nesting, and silently resolves to the wrong constant when a sub-namespace shadows a top-level one. Expected: `zeitwerk:check` and an eager load pass at every commit; the shadow guard (Task 1) and each task's bare-name grep hold it.
4. **A gem's documented constant or route.**
   - `ContentSpiel::Plugins.sign_in_methods` keeps its name, and `register_sign_in_methods(SignIn::Methods)` replays into the moved registry.
   - The gem docs (`lib/content_spiel/plugins.rb`, `docs/reference/content-blocks-and-types.md`) name `SignIn::Methods`.
   - No route `controller:`/`to:` string names a moved class (the controllers stay `Admin::`); `config/routes.rb` names them in comments only.
   - Expected: `plugins_test` passes on the new registry (Task 2), and a route grep stays empty (Task 10).
5. **A literal that only looks like a name.** A careless `sed s/oidc/sso/` or `s/Sessions/SignIn::Sessions/` would rewrite stored or derived values:
   - the provider's discovery cache key `content_spiel/oidc/…`, which would orphan the cache;
   - `KEY_PURPOSE`/`SPENT_PURPOSE`, which would forget every known device and throttle bucket;
   - span names (`auth.sso.callback`);
   - `Session::METHODS`' `"sso"`;
   - the table `sign_in_spent_challenges`;
   - `Admin::SessionsController`;
   - the `OidcHelper` module.
   Expected: none of them changes. Each task's diff check (`git diff HEAD~1 | grep -E '^-.*(content_spiel/oidc|_PURPOSE|auth\.sso|sign_in_spent_challenges)'`) comes back empty except for lines that only moved.

---

## File structure after the move

```
app/models/sign_in.rb                      SignIn (OUTCOMES, SECOND_STEP_LIFETIME, .store)
app/models/sign_in/{rules,methods,proof,spent_challenge,outside_call,outcome}.rb
app/models/sign_in/protection/{throttle,bot_check,known_device}.rb
app/jobs/sign_in/protection/lockout_mail_job.rb
app/models/sign_in/password/{attempt,leaked}.rb
app/services/sign_in/password/leaked_rule.rb
app/models/sign_in/passkeys/{relying_party,registration,check,credential,policy}.rb
app/services/sign_in/passkeys/{add,remove,rename}.rb
app/services/sign_in/recovery_codes/generate.rb
app/services/sign_in/sessions/{end,end_all,end_others}.rb
app/jobs/sign_in/sessions/sweep_job.rb
app/models/sign_in/sso.rb                  SignIn::Sso (the constants and methods of SignIn::Oidc)
app/models/sign_in/sso/{authorization,callback,configuration,id_token,identity,provider,refresh}.rb
app/services/sign_in/sso/{admit,link,linked_event,unlink}.rb
app/jobs/sign_in/sso/recheck_job.rb
test/lib/sign_in_namespace_shadow_test.rb  (Task 1)
test/lib/sign_in_boundary_test.rb          (Task 9)
```

Tests mirror it: `test/{models,services,jobs}/sign_in/<sub>/<file>_test.rb`. Test classes take the new name in compact form, as today (`class SignIn::Passkeys::AddTest`).

**The rewrite recipe each move task uses** (the implementer runs it over the files `git grep -l` returns in `app lib config test db`):
- `perl -pi -e '<substitutions>'`, longest name first.
- Each substitution is guarded by `(?<![\w:])` so a rerun never doubles a prefix.
- Test class names (`class Passkeys::AddTest`) take their own substitution, since `\b` does not end inside `AddTest`.
- After the substitutions, a moved file's wrapping is rewritten by hand into the nested form and re-indented. `bin/rubocop -a` on the moved files fixes indentation only; review its diff.

---

### Task 1: The shadow guard

**Files:**
- Create: `test/lib/sign_in_namespace_shadow_test.rb`

**Interfaces:**
- Consumes: `TopLevelNames.all` and `TopLevelNames.owners` (`app/values/top_level_names.rb`); `Rails.autoloaders.main.inflector`.
- Produces: `SignInNamespaceShadowTest.children`, the names directly under `SignIn` derived from disk. Task 9 extends its sanity assertion.

- [ ] **Step 1: Prepare the worktree and take the inventory again**

  The worktree exists: `/Users/dknafelj/src/ContentSpiel-sign-in-domain`, branch `sign-in-domain`, from `main` at `31807a81`. Check `git log -1` is still `31807a81` (or that `main` has moved, and what moved), then run `bin/rails db:test:prepare`. Run `bin/rails test` and record that it is green.

  Run the inventory and compare it with this plan's lists in Tasks 2–9: `git grep -nP 'SignIn::|(?<![\w:])(Sso|Sessions|Passkeys|RecoveryCodes)::|SignInRules|SignInMethods|LeakedPasswordRule' -- app lib config test db` (`-P`: macOS `git grep -E` does not honour `\b`). The lists are taken at `31807a81`. If a later commit on `main` added a file or call site, add it to the task that moves its constant and say so in the report.

- [ ] **Step 2: Write the guard**

  `SignInNamespaceShadowTest < ActiveSupport::TestCase`, with the header comment written in the style of `admin_namespace_shadow_test.rb`. The comment explains the trap: inside `module SignIn`, a bare `Session` finds `SignIn::Session` before the model.

  - `ROOTS = %w[app/models app/services app/jobs]`.
  - `self.children`: the entries of every `<root>/sign_in/`, a directory or a `.rb` file, camelized by `Rails.autoloaders.main.inflector.camelize(base, path)`, `uniq.sort`.
  - `ALLOWED = {}.freeze`: a name with the reason it is safe. Empty, with the same "should stay empty" comment as the Admin guard.
  - `self.top_level = TopLevelNames.all | TopLevelNames.owners`.

  Tests:
  - `"the list is derived from the directories"`: assert `children` includes `Proof`, `OutsideCall`, `SpentChallenge` and `Outcome` (the names that never move), and `children.size >= 5`.
  - `"no name under SignIn is a top-level constant's"`: `offenders = children & top_level - ALLOWED.keys`, `assert_empty`. The message names the offender and says that every bare `Name` inside `module SignIn` would now mean `SignIn::Name`; pluralise it as `Sessions` and `Passkeys` are. The `ALLOWED` loop asserts that each entry exists under `SignIn` and that its reason is longer than 20 characters.
  - `"a bare reference from inside SignIn reaches the top-level constant"`: `setup { Rails.application.eager_load! }`. For each `TopLevelNames.all` name with `Object.const_defined?(name, false)`, `assert_same Object.const_get(name), SignIn.module_eval(name)`.
  - `"nothing is deeper than two levels"`: `ROOTS.flat_map { Dir[Rails.root.join(_1, "sign_in/*/*/")] }` is empty. The message cites decision 2. A class nested inside a file (`Throttle::Trip`, `Admit::Answer`) is not a level.

- [ ] **Step 3: Check that the guard bites, then that it passes**

  Write `app/models/sign_in/session.rb` with `module SignIn; class Session; end; end`. Run `bin/rails test test/lib/sign_in_namespace_shadow_test.rb`. Expected: FAIL naming `Session` in both the shadow test and the bare-reference test.

  Then write `app/models/sign_in/oidc/x/y.rb`. Expected: the depth test FAILS.

  Delete both files and run again. Expected: PASS.

- [ ] **Step 4: Commit.** `git add test/lib/sign_in_namespace_shadow_test.rb && git commit -m "test: no name under SignIn shadows a top-level constant, and nothing is deeper than two levels"`

---

### Task 2: The root: `SignIn::Rules` and `SignIn::Methods`

**Files (moves):**
- `app/models/sign_in_rules.rb` → `app/models/sign_in/rules.rb`
- `app/models/sign_in_methods.rb` → `app/models/sign_in/methods.rb`
- `test/models/sign_in_rules_test.rb` → `test/models/sign_in/rules_test.rb`
- `test/models/sign_in_methods_test.rb` → `test/models/sign_in/methods_test.rb`

**Modify:**
- Every file in the Step 1 inventory that names `SignInRules` or `SignInMethods`. At `31807a81` these are:
  - the controllers `admin/sessions`, `second_factors`, `accounts`, `sso_links`;
  - the concern `admin/sign_in_completion.rb`;
  - the components `account_screen/sso_card_component.rb` and `users_screen/sso_zone_component.rb` (comments), and `ui/way_in_button_component.rb` (a comment; `ui/or_divider_component.rb` names neither);
  - `app/jobs/password_reset_request_job.rb`, `app/mailers/passwords_mailer.rb` (a comment), `app/models/session.rb`;
  - `app/services/users/{owner_protection,save}.rb`;
  - the views `admin/sessions/new.html.erb`, `admin/users/edit.html.erb` and `admin/users/_form.html.erb` (the linked account's line, new since `0c1b4878`);
  - `config/initializers/sign_in_methods.rb`;
  - `lib/content_spiel/plugins.rb` (comments);
  - inside the domain, comments of `app/models/sign_in/{password_attempt,proof}.rb`, `app/models/passkeys/policy.rb` (`SignInMethods.exempt?`, code), `app/services/passkeys/add.rb`, `app/services/recovery_codes/generate.rb`, `app/jobs/sso/recheck_job.rb`;
  - the tests `test/lib/content_spiel/plugins_test.rb`, `test/models/session_test.rb`, `test/models/passkeys/policy_test.rb`, `test/models/sign_in/password_attempt_test.rb`, `test/jobs/sso/recheck_job_test.rb`, `test/integration/{sign_in_throttles,sso_sign_in_page,sso_sign_in}_test.rb`.

**Renames:** `SignInRules` → `SignIn::Rules`; `SignInMethods` → `SignIn::Methods`. Test classes: `SignInRulesTest` → `SignIn::RulesTest`, `SignInMethodsTest` → `SignIn::MethodsTest`.

**Interfaces — Produces:**
- `SignIn::Rules.password_allowed?(user)`, `.passkey_allowed?(user)`, `.reminder_instead_of_reset?(user)`, `.provider_name(user, issuer:)`;
- `SignIn::Methods.register/entries/find/names/exempt?/rechecked?/reset!`;
- `SignIn::Methods::Entry`, `PASSKEY_POLICIES`, `BUILT_IN_EXEMPT`.

- [ ] **Step 1: Move and rewrite.** Use `git mv` for the four files. Run perl with `s/(?<![\w:])SignInRulesTest\b/SignIn::RulesTest/g; s/(?<![\w:])SignInMethodsTest\b/SignIn::MethodsTest/g; s/(?<![\w:])SignInRules\b/SignIn::Rules/g; s/(?<![\w:])SignInMethods\b/SignIn::Methods/g`. Wrap both moved files in `module SignIn` and rename the inner `module SignInRules` to `module Rules` (likewise `Methods`).
- [ ] **Step 2: The grep must come back empty.** `git grep -nP '\bSignIn(Rules|Methods)\b' -- app lib config test db` → no output.
- [ ] **Step 3: Run.**

  ```sh
  bin/rails zeitwerk:check
  bin/rails test
  bin/rails test test/system/admin/sso_sign_in_test.rb test/system/admin/user_sso_test.rb test/system/admin/passkey_sign_in_test.rb
  bin/rubocop
  ```

  Expected: all green. `plugins_test` replays the hook into `SignIn::Methods`, and the shadow guard passes.
- [ ] **Step 4: Commit.** `ref: the sign-in rules and the methods registry are SignIn::Rules and SignIn::Methods`

---

### Task 3: `SignIn::Protection`

**Files (moves):**
- `app/models/sign_in/throttle.rb` → `app/models/sign_in/protection/throttle.rb`
- `app/models/sign_in/bot_check.rb` → `app/models/sign_in/protection/bot_check.rb`
- `app/models/sign_in/known_device.rb` → `app/models/sign_in/protection/known_device.rb`
- `app/jobs/sign_in/lockout_mail_job.rb` → `app/jobs/sign_in/protection/lockout_mail_job.rb`
- `test/models/sign_in/{throttle,bot_check,known_device}_test.rb` → `test/models/sign_in/protection/`
- `test/jobs/sign_in/lockout_mail_job_test.rb` → `test/jobs/sign_in/protection/lockout_mail_job_test.rb`

**Stays:** `app/models/sign_in/outcome.rb` (`SignIn::Outcome`, the shared root's: decision 1, owner's correction). It has no test file of its own; `password_attempt_test` and `proof_test` assert on `SignIn::Outcome.new(…)` and those lines do not change.

**Renames:** `SignIn::{Throttle,BotCheck,KnownDevice,LockoutMailJob}` → `SignIn::Protection::…`. Test classes `SignIn::{Throttle,BotCheck,KnownDevice}Test` and `SignIn::LockoutMailJobTest` → under `SignIn::Protection::`.

**Bare references to qualify** (they stop resolving once their target leaves the root):
- `app/models/sign_in/password_attempt.rb`: `BotCheck.usable_token?` → `Protection::BotCheck.usable_token?`.
- `Outcome.new` in `password_attempt.rb` and `proof.rb` stays bare: `Outcome` does not move.
- Inside the moved files, `OutsideCall` keeps resolving through `module SignIn`; leave it bare. In `outcome.rb`'s comment, the bare `Throttle::Trip` becomes `Protection::Throttle::Trip` (by hand; Step 2's second grep finds it otherwise).

**Strings that are class names:** `test/integration/sign_in_throttles_test.rb` `[ "SignIn::LockoutMailJob" ]` and `test/jobs/…/lockout_mail_job_test.rb` `"SignIn::LockoutMailJob"` → `"SignIn::Protection::LockoutMailJob"`.

**Also:** `config/initializers/sign_in.rb`, `filter_parameter_logging.rb` (comment), `app/javascript/controllers/bot_check_controller.js` (comments), `app/views/admin/sessions/new.html.erb` (`SignIn::BotCheck::ACTION`), `app/mailers/sign_in_mailer.rb`, `app/controllers/concerns/admin/sign_in_locks.rb`, `admin/sessions_controller.rb`, `confirmations_controller.rb`, `concerns/admin/sign_in_completion.rb`, `app/services/users/{save,update_password}.rb`, `app/models/sign_in.rb`, `app/models/sign_in/{outside_call,password_attempt,proof}.rb`, `test/support/sign_in_helper.rb`, and the tests `test/controllers/admin/{confirmations,sessions}_controller_test.rb`, `test/integration/{passkey_sign_in,second_factor,sign_in_known_device,sign_in_throttles,sso_sign_in}_test.rb`, `test/models/sign_in/{password_attempt,proof}_test.rb`, `test/services/users/update_password_test.rb`, `test/system/admin/sign_in_bot_check_test.rb`.

**Interfaces — Produces:** `SignIn::Protection::Throttle` (with `::Trip`), `SignIn::Protection::BotCheck` (`ACTION`, `.current`, `.missing_variable`, `.siteverify`, `.usable_token?`, `::Unavailable`), `SignIn::Protection::KnownDevice`, `SignIn::Protection::LockoutMailJob`. `SignIn::Outcome` is unchanged.

- [ ] **Step 1: Move and rewrite.** Use `git mv`. Run perl with `s/(?<![\w:])SignIn::(Throttle|BotCheck|KnownDevice|LockoutMailJob)(?=\b|Test)/SignIn::Protection::$1/g`, plus the string forms. Add `module Protection` inside `module SignIn` in each moved file, then qualify the bare references above.
- [ ] **Step 2: The greps must come back empty.**

  `git grep -nP 'SignIn::(Throttle|BotCheck|KnownDevice|LockoutMailJob)\b' -- app lib config test db` → none.

  `git grep -nP '(?<![\w:])(Throttle|BotCheck|KnownDevice)(\.|::)' -- app/models/sign_in app/jobs/sign_in ':!app/models/sign_in/protection' ':!app/jobs/sign_in/protection'` → none.

  `git grep -nP 'SignIn::Protection::Outcome' -- .` → none (it stays `SignIn::Outcome`).
- [ ] **Step 3: Run.**

  ```sh
  bin/rails zeitwerk:check
  bin/rails test
  bin/rails test test/system/admin/sign_in_bot_check_test.rb test/system/admin/passkey_sign_in_test.rb
  bin/rubocop
  ```

  Then run the Review Focus 5 diff check (`git diff --cached | grep -E '^-.*_PURPOSE'` shows only moved lines that reappear unchanged with `+`).
- [ ] **Step 4: Commit.** `ref: throttle, bot check, known device and the lockout mail are SignIn::Protection`

---

### Task 4: `SignIn::Password`

**Files (moves):**
- `app/models/sign_in/password_attempt.rb` → `app/models/sign_in/password/attempt.rb`
- `app/models/sign_in/leaked_password.rb` → `app/models/sign_in/password/leaked.rb`
- `app/services/users/leaked_password_rule.rb` → `app/services/sign_in/password/leaked_rule.rb`
- `test/models/sign_in/password_attempt_test.rb` → `test/models/sign_in/password/attempt_test.rb`
- `test/models/sign_in/leaked_password_test.rb` → `test/models/sign_in/password/leaked_test.rb`

**Renames:** `SignIn::PasswordAttempt` → `SignIn::Password::Attempt`; `SignIn::LeakedPassword` → `SignIn::Password::Leaked`; `Users::LeakedPasswordRule` → `SignIn::Password::LeakedRule`. Test classes `SignIn::PasswordAttemptTest` → `SignIn::Password::AttemptTest`, `SignIn::LeakedPasswordTest` → `SignIn::Password::LeakedTest`.

**Bare references:**
- `app/services/users/save.rb` and `update_password.rb`: `include LeakedPasswordRule` → `include SignIn::Password::LeakedRule`.
- `app/services/invitations/accept.rb`: `include Users::LeakedPasswordRule` → `include SignIn::Password::LeakedRule`.
- In the moved `leaked_rule.rb`, its reference to `SignIn::LeakedPassword` takes the new name. Its `private` and its module body are otherwise untouched.
- `Outcome.new` in the moved `attempt.rb` stays bare and resolves to the root's `SignIn::Outcome`.
- Comments that name the class bare: `PasswordAttempt` in `app/models/sign_in/known_device.rb` (by then `protection/known_device.rb`) and `proof.rb` → `Password::Attempt`.

**Also:** `admin/sessions_controller.rb`, `app/models/sign_in/{outcome,outside_call}.rb`, `app/models/sign_in_rules.rb` (by then `sign_in/rules.rb`), `config/locales/en.yml` (a comment naming `Users::LeakedPasswordRule`), and the tests `test/models/sign_in/proof_test.rb`, `test/services/invitations/accept_test.rb`, `test/services/users/{save,update_password}_test.rb`.

**Strings:** `leaked_test.rb` asserts the log line and `error.type` `"SignIn::LeakedPassword::Unavailable"` → `"SignIn::Password::Leaked::Unavailable"` (Review Focus 2: this is the span value a host's query sees). `test/support/sign_in_helper.rb` takes the new constant names.

**Interfaces — Produces:** `SignIn::Password::Attempt.new(email:, password:, address:, hostname:, bot_check_token:, …)`, `SignIn::Password::Leaked` (`.check`, `.range`, `::Unavailable`), `SignIn::Password::LeakedRule` (a mixin of private methods).

- [ ] **Step 1: Move and rewrite.** Use `git mv`. Run perl: `s/(?<![\w:])SignIn::PasswordAttempt(?=\b|Test)/SignIn::Password::Attempt/g; s/(?<![\w:])SignIn::LeakedPassword(?=\b|Test)/SignIn::Password::Leaked/g; s/(?<![\w:])(Users::)?LeakedPasswordRule\b/SignIn::Password::LeakedRule/g`, then, for the bare comment names, `s/(?<![\w:])PasswordAttempt\b/Password::Attempt/g` over `app/models/sign_in` only. Wrap the files: `module SignIn` / `module Password` / `class Attempt` (`module Leaked`, `module LeakedRule`).
- [ ] **Step 2: The grep must come back empty.** `git grep -nP '\b(PasswordAttempt|LeakedPassword|LeakedPasswordRule)\b' -- app lib config test db` → none. The locale key `password.leaked` is not matched.
- [ ] **Step 3: Run.**

  ```sh
  bin/rails zeitwerk:check
  bin/rails test
  bin/rails test test/system/admin/sign_in_bot_check_test.rb test/system/admin/account_password_answer_test.rb
  bin/rubocop
  ```
- [ ] **Step 4: Commit.** `ref: the password attempt and the leaked-password check and rule are SignIn::Password`

---

### Task 5: `SignIn::Passkeys`

**Files (moves):**
- `app/models/sign_in/relying_party.rb` → `app/models/sign_in/passkeys/relying_party.rb`
- `app/models/sign_in/passkey_registration.rb` → `app/models/sign_in/passkeys/registration.rb`
- `app/models/sign_in/passkey_check.rb` → `app/models/sign_in/passkeys/check.rb`
- `app/models/sign_in/passkey_credential.rb` → `app/models/sign_in/passkeys/credential.rb`
- `app/models/passkeys/policy.rb` → `app/models/sign_in/passkeys/policy.rb` (the empty `app/models/passkeys/` goes)
- `app/services/passkeys/{add,remove,rename}.rb` → `app/services/sign_in/passkeys/`
- `test/models/sign_in/relying_party_test.rb` → `test/models/sign_in/passkeys/relying_party_test.rb`
- `test/models/sign_in/passkey_registration_test.rb` → `test/models/sign_in/passkeys/registration_test.rb`
- `test/models/sign_in/passkey_check_test.rb` → `test/models/sign_in/passkeys/check_test.rb`
- `test/models/passkeys/policy_test.rb` → `test/models/sign_in/passkeys/policy_test.rb`
- `test/services/passkeys/{add,remove,rename}_test.rb` → `test/services/sign_in/passkeys/`

**Renames:**
- `SignIn::RelyingParty` → `SignIn::Passkeys::RelyingParty`
- `SignIn::PasskeyRegistration` → `SignIn::Passkeys::Registration`
- `SignIn::PasskeyCheck` → `SignIn::Passkeys::Check`
- `SignIn::PasskeyCredential` → `SignIn::Passkeys::Credential`
- `Passkeys::{Policy,Add,Remove,Rename}` → `SignIn::Passkeys::…`
- Test classes follow.

**Bare references:** in `registration.rb` and `check.rb`, `PasskeyCredential` (`::MAX_CREDENTIAL_BYTES`, `.parse`, `::MALFORMED`) → `Credential`. `Policy.current` in `remove.rb` keeps resolving inside `module SignIn; module Passkeys`. `RecoveryCodes::Generate` in `add.rb` resolves to the top-level module until Task 6 rewrites it. In comments, `proof.rb`'s bare ``PasskeyCheck#verify`` → `Passkeys::Check#verify`.

**Strings:**
- `test/support/service_calls.rb`: the keys `"Passkeys::Add"`, `"Passkeys::Rename"`, `"Passkeys::Remove"` in `SELF_SERVICE` and `FACTORIES` → `"SignIn::Passkeys::…"`, and the calls inside the lambdas.
- `test/services/service_behaviour_contract_test.rb`: the expected list's three names, keeping its sort.

**Also:**
- the controllers `admin/passkeys`, `admin/enrolments`, `admin/confirmations`, `admin/second_factors`, `admin/sessions`, `setup`;
- the concerns `authentication.rb`, `admin/passkey_enrolment.rb`, `passkey_challenges.rb`;
- the components `account_screen/passkeys_card_component.rb`, `account_screen/sso_card_component.rb` (comment) and `settings_screen/sign_in_card_component.rb` (comment);
- `app/models/site_setting.rb` (comment), `app/views/admin/settings/show.html.erb`;
- inside the domain, `app/models/sign_in.rb`, `app/models/sign_in/{oidc,proof}.rb`, `app/models/sign_in/{rules,methods}.rb`, `app/services/recovery_codes/generate.rb` (comments);
- the locale comments `config/locales/admin/passkeys.en.yml` and `config/locales/setup.en.yml`;
- `test/support/passkey_helper.rb`, `test/integration/{passkey_telemetry,setup_passkey_step}_test.rb`, `test/models/sign_in/proof_test.rb`.

**Interfaces — Produces:** `SignIn::Passkeys::RelyingParty.for(address:, request_origin:, name:)`, `SignIn::Passkeys::Registration.new(relying_party:)`, `SignIn::Passkeys::Check.new(relying_party:)`, `SignIn::Passkeys::Credential`, `SignIn::Passkeys::Policy.current(site:)` (`ADMIN_PERMISSIONS`, `#covers?`), `SignIn::Passkeys::Add/Remove/Rename.call(…)`.

- [ ] **Step 1: Move and rewrite.** Use `git mv`. Run perl (longest first):

  ```
  s/(?<![\w:])SignIn::PasskeyRegistration(?=\b|Test)/SignIn::Passkeys::Registration/g;
  s/(?<![\w:])SignIn::PasskeyCheck(?=\b|Test)/SignIn::Passkeys::Check/g;
  s/(?<![\w:])SignIn::PasskeyCredential\b/SignIn::Passkeys::Credential/g;
  s/(?<![\w:])SignIn::RelyingParty(?=\b|Test)/SignIn::Passkeys::RelyingParty/g;
  s/(?<![\w:])Passkeys::(Policy|Add|Remove|Rename)(?=\b|Test)/SignIn::Passkeys::$1/g;
  s/(?<![\w:])PasskeyCheck#/Passkeys::Check#/g
  ```

  Wrap the files.
- [ ] **Step 2: The greps must come back empty.**

  `git grep -nP '\bSignIn::(RelyingParty|Passkey(Registration|Check|Credential))\b|(?<![\w:])Passkeys::' -- app lib config test db` → none.

  `git grep -nP '\bPasskey(Credential|Check|Registration)\b' -- app test` → none.

  `ls app/models/passkeys app/services/passkeys` → both missing.
- [ ] **Step 3: Run.**

  ```sh
  bin/rails zeitwerk:check
  bin/rails test
  bin/rails test test/system/admin/account_passkeys_test.rb test/system/admin/passkey_enrolment_test.rb test/system/admin/passkey_sign_in_test.rb
  bin/rubocop
  ```

  The shadow guard and the Admin shadow guard pass now that top-level `Passkeys` is gone. `TopLevelNames.all.size` stays at 40 or more.
- [ ] **Step 4: Commit.** `ref: the passkey ceremonies, the policy and the passkey services are SignIn::Passkeys`

---

### Task 6: `SignIn::RecoveryCodes`

**Files (moves):**
- `app/services/recovery_codes/generate.rb` → `app/services/sign_in/recovery_codes/generate.rb`
- `test/services/recovery_codes/generate_test.rb` → `test/services/sign_in/recovery_codes/generate_test.rb`

**Renames:** `RecoveryCodes::Generate` → `SignIn::RecoveryCodes::Generate`, and its test class.

`SignIn::Proof` stays at the root (see "Calls this plan makes").

**Also:**
- `admin/recovery_codes_controller.rb`;
- the components `account_screen/{recovery_card,sso_card}_component.rb`;
- `config/locales/admin/passkeys.en.yml` (comment);
- inside the domain, `app/services/sign_in/passkeys/add.rb` (the call `RecoveryCodes::Generate.new(…).write_codes`) and `app/models/sign_in/rules.rb` (comment);
- `service_calls.rb` (key `"RecoveryCodes::Generate"` and its lambda);
- `service_behaviour_contract_test.rb`;
- the tests `test/components/admin/account_screen/recovery_card_component_test.rb`, `test/controllers/admin/{passkeys,recovery_codes}_controller_test.rb`, `test/services/sign_in/passkeys/remove_test.rb`, `test/services/users/update_password_test.rb`.

**Interfaces — Produces:** `SignIn::RecoveryCodes::Generate.call(user, actor:)`.

- [ ] **Step 1: Move and rewrite.** Use `git mv`. Run perl: `s/(?<![\w:])RecoveryCodes::Generate(?=\b|Test)/SignIn::RecoveryCodes::Generate/g`. Wrap the file.
- [ ] **Step 2: The grep must come back empty.** `git grep -nP '(?<![\w:])RecoveryCodes::' -- app lib config test db` → none. (`Admin::RecoveryCodesController` and `recovery_codes_controller` do not match.)
- [ ] **Step 3: Run.**

  ```sh
  bin/rails zeitwerk:check
  bin/rails test
  bin/rails test test/system/admin/account_passkeys_test.rb
  bin/rubocop
  ```
- [ ] **Step 4: Commit.** `ref: making recovery codes is SignIn::RecoveryCodes::Generate`

---

### Task 7: `SignIn::Sessions`

**Files (moves):**
- `app/services/sessions/{end,end_all,end_others}.rb` → `app/services/sign_in/sessions/`
- `app/jobs/sessions/sweep_job.rb` → `app/jobs/sign_in/sessions/sweep_job.rb`
- `test/services/sessions/{end,end_all,end_others}_test.rb` → `test/services/sign_in/sessions/`
- `test/jobs/sessions/sweep_job_test.rb` → `test/jobs/sign_in/sessions/sweep_job_test.rb`

**Renames:** `Sessions::{End,EndAll,EndOthers,SweepJob}` → `SignIn::Sessions::…`, and their test classes.

**Strings:**
- `config/recurring.yml`: all three `class: Sessions::SweepJob` → `class: SignIn::Sessions::SweepJob`.
- `sweep_job_test.rb`: `assert_equal "Sessions::SweepJob", schedule["class"]` → the new name. This is the Review Focus 1 pin.
- `service_calls.rb`: the keys `"Sessions::EndOthers"`, `"Sessions::End"`, `"Sessions::EndAll"`, the prose naming them, and the lambdas.
- `service_behaviour_contract_test.rb`.

**Also:** `app/models/session.rb` (the `Sessions::End.call` that ends an expired session, and comments), `admin/users_controller.rb`, `admin/account_sessions_controller.rb`, `users_screen/sessions_zone_component.rb`, `config/routes.rb` (comment), `config/locales/admin/users.en.yml` (comment), `app/services/sso/unlink.rb` (its `authorize:` comment names `Sessions::EndAll`), and the SSO recheck job's call to `Sessions::End` and its comments (still at `app/jobs/sso/recheck_job.rb` until Task 8, so `service_calls.rb`'s `callers:` path for `"SignIn::Sessions::End"` stays `app/jobs/sso/recheck_job.rb` here). Tests: `test/jobs/sso/recheck_job_test.rb`.

**Interfaces — Produces:** `SignIn::Sessions::End.call(…)`, `EndAll`, `EndOthers`, `SignIn::Sessions::SweepJob`.

- [ ] **Step 1: Move and rewrite.** Use `git mv`. Run perl: `s/(?<![\w:])Sessions::(EndAll|EndOthers|End|SweepJob)(?=\b|Test)/SignIn::Sessions::$1/g`. Wrap the files.
- [ ] **Step 2: The grep must come back empty.** `git grep -nP '(?<![\w:])Sessions::' -- app lib config test db` → none. `Admin::SessionsController` is preceded by `::` and so does not match.
- [ ] **Step 3: Run.**

  ```sh
  bin/rails zeitwerk:check
  bin/rails test
  bin/rails test test/system/admin/account_sessions_test.rb test/system/admin/session_ended_test.rb test/system/admin/users_test.rb
  bin/rubocop
  ```

  Then run `grep -hoE 'class: \S+' config/recurring.yml | sort -u | cut -d' ' -f2 | xargs -I{} bin/rails runner 'puts "{}".constantize'`. Every class in the schedule must resolve, with no NameError. Task 8 runs this again.
- [ ] **Step 4: Commit.** `ref: ending sessions and the session sweep are SignIn::Sessions`

---

### Task 8: `SignIn::Sso`

**Files (moves):**
- `app/models/sign_in/oidc.rb` → `app/models/sign_in/sso.rb`
- `app/models/sign_in/oidc/{authorization,callback,configuration,id_token,identity,provider,refresh}.rb` → `app/models/sign_in/sso/`
- `app/services/sso/{admit,link,linked_event,unlink}.rb` → `app/services/sign_in/sso/`
- `app/jobs/sso/recheck_job.rb` → `app/jobs/sign_in/sso/recheck_job.rb`
- `test/models/sign_in/oidc/{authorization,callback,provider,refresh}_test.rb` → `test/models/sign_in/sso/` (there is no `id_token_test.rb`; the ID token is tested through `callback_test` and `refresh_test`)
- `test/services/sso/{admit,link,unlink}_test.rb` → `test/services/sign_in/sso/` (`LinkedEvent` has no test file of its own)
- `test/jobs/sso/recheck_job_test.rb` → `test/jobs/sign_in/sso/recheck_job_test.rb`

**Renames:**
- `SignIn::Oidc` → `SignIn::Sso`, everywhere (`::Provider`, `::Authorization`, `::Callback`, `::Configuration`, `::IdToken`, `::Identity`, `::Refresh`, `::Unavailable`, `::Misconfigured` and the constants `VARIABLES`, `STATE_LIFETIME`, `UNFINISHED_REASONS`, `ACCOUNT_REASONS`, `MISMATCH_REASON`, `SPAN_REASONS`, `DISCOVERY_REASONS`, `DISCOVERY_HTTP_REASON`, `RECHECK_REASONS`, and the methods `.discovery_reason?`, `.error_type`, `.issuer_host`, `.required?`, `.callback_origin`).
- `Sso::{Admit,Link,LinkedEvent,Unlink,RecheckJob}` → `SignIn::Sso::…` (with what is nested: `Admit::Answer`, `Admit::OWNER`/`MISMATCH`/`EMAIL_LIMIT`, `LinkedEvent::VIA`, `RecheckJob::RecheckFailed`).
- Test classes `SignIn::Oidc::*Test` → `SignIn::Sso::*Test`, and `Sso::*Test` → `SignIn::Sso::*Test`.
- Before writing any file, list `ls app/models/sign_in/oidc app/services/sso app/jobs/sso`. At `31807a81` they are `authorization callback configuration id_token identity provider refresh`, `admit link linked_event unlink` and `recheck_job`: no two share a basename. If a later commit adds one that does, stop and report.

**Bare references:** `Oidc.error_type(…)` in `callback.rb`, `refresh.rb` and `provider.rb`, and `Oidc.discovery_reason?(…)` in `provider.rb` → `Sso.error_type(…)`, `Sso.discovery_reason?(…)`. `RECHECK_REASONS` in `refresh.rb` stays bare. `module Oidc` → `module Sso` in all eight model files. `Link`, `Link::OWNER` etc. in `admit.rb`, and `include LinkedEvent` in `link.rb`, keep resolving inside `module SignIn; module Sso`. Outside the domain, `include Sso::LinkedEvent` in `app/services/invitations/accept_with_sso.rb` → `include SignIn::Sso::LinkedEvent` (the perl line below does it).

**Strings:**
- `config/recurring.yml`: all three `class: Sso::RecheckJob`.
- `recheck_job_test.rb`: `{ "class" => "Sso::RecheckJob", …}`, and `assert_error_reported(Sso::RecheckJob::RecheckFailed)` (three places).
- `service_calls.rb`: the keys `"Sso::Admit"`, `"Sso::Link"`, `"Sso::Unlink"` (in the authorize-none list and the factories), their prose and lambdas (`Sso::Link.call(target, identity:)`, with no `via:` since `31807a81`), and the `callers:` paths `app/jobs/sso/recheck_job.rb` → `app/jobs/sign_in/sso/recheck_job.rb` and `app/services/sso/admit.rb` → `app/services/sign_in/sso/admit.rb`.
- `service_behaviour_contract_test.rb`: `Sso::Admit Sso::Link Sso::Unlink` (`LinkedEvent` is a module, not a service, and is not in the list).
- `test/services/sso/admit_test.rb`: the test name `"Sso::Admit.refuse, the callback's owner defence, …"` takes the new name.
- `test/lib/mail_guards_test.rb`: the key `"app/services/sso/admit.rb"` → `"app/services/sign_in/sso/admit.rb"`.
- Test names (`test "… SignIn::Oidc.required? agrees"`) take the new name.
- **Unchanged:** `"content_spiel/oidc/…"` (`provider.rb`, `provider_test.rb`), `OidcHelper`.

**`config/brakeman.ignore`:** the entry's `code`, `user_input` and `note` name `SignIn::Oidc::Authorization` / `::Provider#configuration` → `SignIn::Sso::…`. The fingerprint is derived from the code, so run `bin/brakeman --no-pager -f json -q | jq '.warnings[] | {fingerprint, code}'` and copy the new fingerprint into the entry. `file` stays `app/controllers/concerns/sso_starts.rb`. `bin/brakeman` must exit 0.

**Also:**
- `config/initializers/sign_in.rb`, `config/routes.rb` (comments);
- `admin/sessions_controller.rb`, `admin/sso_sessions_controller.rb` (`Sso::Admit.call`, `Sso::Admit.refuse(identity, Sso::Admit::OWNER)`, `Sso::Admit::MISMATCH`, `SignIn::Oidc::ACCOUNT_REASONS`, `MISMATCH_REASON`, `Callback`), `admin/sso_links_controller.rb` (`Sso::Unlink.new(…)`, `#call`, `#mailed?`), `concerns/sso_starts.rb`;
- `app/models/setup/system_check.rb`, `app/models/session.rb`, `app/models/audit/sentence.rb` (comment), `app/models/sign_in.rb` (comment), `app/models/sign_in/rules.rb` (`SignIn::Oidc.required?`, `::Provider`, `.issuer_host`), `app/models/sign_in/passkeys/policy.rb` (`SignIn::Oidc.required?`);
- `app/services/invitations/{accept,accept_with_sso}.rb` (`accept_with_sso.rb`: `include Sso::LinkedEvent` and its comment), `app/services/users/{owner_protection,save,update_password}.rb` (comments), `app/services/sign_in/passkeys/add.rb` and `app/services/sign_in/recovery_codes/generate.rb` (comments);
- `app/jobs/password_reset_request_job.rb`, `app/views/invitations/show.html.erb`;
- the components `account_screen/sso_card_component.rb` and `users_screen/sso_zone_component.rb` (comments; the latter's new `mail_ready` comment names `Sso::Unlink`);
- `config/locales/admin/users.en.yml` (comment);
- `test/support/oidc_helper.rb`, and the tests `test/integration/{sso_sign_in,sso_telemetry}_test.rb` (`sso_telemetry_test`, new since `0c1b4878`, reads `SignIn::Oidc::SPAN_REASONS`, `SignIn::Oidc.method(:discovery_reason?)` and `SignIn::Oidc::RECHECK_REASONS`), `test/controllers/admin/sso_links_controller_test.rb`, `test/models/{session,sign_in/methods}_test.rb`, `test/models/audit/sentence_test.rb`, `test/models/setup/system_check_test.rb`, `test/services/invitations/accept_with_sso_test.rb`, `test/services/users/{save,update_password}_test.rb`, `test/system/admin/sso_sign_in_test.rb`.

**Interfaces — Produces:**
- `SignIn::Sso` (`.required?`, `.callback_origin(request_origin:)`, `.issuer_host`, `.error_type`, `.discovery_reason?(word)`, the constants above, `::Unavailable`, `::Misconfigured`);
- `SignIn::Sso::{Provider,Authorization,Callback,Configuration,Identity,Refresh}`, and `SignIn::Sso::IdToken.verify(token, provider:, nonce:, age_limit: MAX_AGE)` (`Refresh` passes `age_limit: nil`);
- `SignIn::Sso::Admit.call(identity, invitation: nil)` answering an `Admit::Answer` (`#accepted_invitation?`), and `SignIn::Sso::Admit.refuse(identity, reason)`, the one writer of `sso.refused`;
- `SignIn::Sso::Link.call(user, identity:, actor: user)` (no `via:`);
- `SignIn::Sso::LinkedEvent` (`VIA`, private `#record_linked(user, identity:, via:, passkeys_removed: 0, recovery_codes_removed: 0)`), the one writer of `sso.linked`, included by `Link` and `Invitations::AcceptWithSso`;
- `SignIn::Sso::Unlink.new(user, actor: Current.actor, origin: nil)` with `#call` and `#mailed?`, and `Unlink.not_linked(user)`;
- `SignIn::Sso::RecheckJob` (with `::RecheckFailed`).

- [ ] **Step 1: Move and rewrite.** Use `git mv`. Run perl:

  ```
  s/(?<![\w:])SignIn::Oidc(?=\b|::)/SignIn::Sso/g;
  s/(?<![\w:])Sso::(Admit|LinkedEvent|Link|Unlink|RecheckJob)(?=\b|Test)/SignIn::Sso::$1/g;
  s/(?<![\w:])Sso::(\w+Test)\b/SignIn::Sso::$1/g
  ```

  Then hand-edit: `module Oidc` → `module Sso` in the eight model files; wrap the services, the `LinkedEvent` module and the job as `module SignIn` / `module Sso`; `Oidc.error_type` → `Sso.error_type`, `Oidc.discovery_reason?` → `Sso.discovery_reason?`.
- [ ] **Step 2: The greps must come back empty.**

  `git grep -nP '\bOidc\b(?!Helper)' -- app lib config test db` → none.

  `git grep -nP '(?<![\w:])Sso::' -- app lib config test db` → none.

  `ls app/models/sign_in/oidc app/services/sso app/jobs/sso` → all missing.

  `git grep -n 'content_spiel/oidc/' -- app test` → the same two lines as before the task (Review Focus 5).
- [ ] **Step 3: Run.**

  ```sh
  bin/rails zeitwerk:check
  bin/rails test
  bin/rails test test/system/admin/sso_sign_in_test.rb test/system/admin/user_sso_test.rb test/system/invitation_sso_test.rb
  bin/brakeman
  bin/rubocop
  ```

  `bin/brakeman` must exit 0 with the entry still ignored. Then run the recurring.yml constantize check from Task 7 Step 3 again.
- [ ] **Step 4: Commit.** `ref: single sign-on is SignIn::Sso, the OIDC objects folded flat with its services and re-check`

---

### Task 9: The public-surface guard

**Files:**
- Create: `test/lib/sign_in_boundary_test.rb`
- Modify: `test/lib/sign_in_namespace_shadow_test.rb` (the sanity assertion now also requires `Protection Password Passkeys RecoveryCodes Sso Sessions Rules Methods`)

**Interfaces:**
- Consumes: `SourceCode.without_ruby_comments` (`test/support/source_code.rb`); the names Tasks 2–8 produced.
- Produces: `SignInBoundaryTest::ENTRY_POINTS`, the documented public surface. Task 10's docs cite it.

The style is that of `dependency_direction_test.rb` and `notes_boundary_test.rb`. The header comment says:
- what the guard holds;
- that tests are left out on purpose (a test may reach any part it pins);
- how a reference is read: `SignIn` followed by `::Camel` segments, with trailing `ALL_CAPS` segments (a value of the entry) dropped. So `SignIn::Sso::ACCOUNT_REASONS` and `SignIn.store` count against `SignIn::Sso` and `SignIn`, and `SignIn::Protection::BotCheck::ACTION` against `SignIn::Protection::BotCheck`;
- that an entry admits that constant exactly, never what is nested under it.

- [ ] **Step 1: Write the guard.**

  - `OWN = %w[app/models/sign_in.rb app/models/sign_in/**/*.rb app/services/sign_in/**/*.rb app/jobs/sign_in/**/*.rb]`
  - `OUTSIDE = "{app,lib,config}/**/*.{rb,erb,yml}"` minus `OWN`
  - `REFERENCE = /(?<![\w:])(?:::)?SignIn(?:::[A-Z]\w*)*/`, normalised by stripping `/(::[A-Z][A-Z0-9_]*)+\z/`
  - Code extraction:
    - `.rb`: `SourceCode.without_ruby_comments`;
    - `.erb`: the inside of every `<%`/`<%=` tag, never `<%#`, with Ruby comments stripped;
    - `.yml`: every line not starting with `#` after `lstrip`.

  `ENTRY_POINTS` (constant path → reason, each over 20 characters). This is the list of code call sites at `31807a81` (comments excluded), mapped to the new names:

  | Entry | Reached by | Why |
  |---|---|---|
  | `SignIn` | sessions, second-factor, confirmations, SSO-sessions and invitations controllers | `.store` is the counter store their `rate_limit` shares with the throttle; `SECOND_STEP_LIFETIME` bounds the second-step cookie |
  | `SignIn::Rules` | sessions and second-factor controllers, account and SSO-link controllers, `PasswordResetRequestJob`, `Users::Save`/`OwnerProtection`, the user editor and the user form (`admin/users/edit.html.erb`, `_form.html.erb`) | who may sign in how, asked by every door and every password writer, and the provider's name a linked account's screens show |
  | `SignIn::Methods` | the initializer, `Session`, the sign-in page, `Admin::SignInCompletion` | the gem hook's registry: filled at boot, read when a session starts and when the page lists the ways in |
  | `SignIn::Proof` | second-factor and confirmations controllers | the second proof and Confirm it's you |
  | `SignIn::SpentChallenge` | `PasskeyChallenges`, `SsoStarts` | a challenge or state is spent once, whichever screen issued it |
  | `SignIn::Protection::Throttle` | sessions controller, `Admin::SignInLocks`, `Users::Save`, `Users::UpdatePassword` | buckets are reserved by the door and cleared when a password is set |
  | `SignIn::Protection::BotCheck` | sessions controller, the sign-in page, `config/initializers/sign_in.rb` | the widget's action, the server's verify, the boot's warning |
  | `SignIn::Protection::KnownDevice` | confirmations controller, `Admin::SignInCompletion` | the controller keeps the device's cookie |
  | `SignIn::Protection::LockoutMailJob` | `Admin::SignInLocks` | the lock's mail is queued where the lock is answered |
  | `SignIn::Password::Attempt` | sessions controller | the password door |
  | `SignIn::Password::LeakedRule` | `Users::Save`, `Users::UpdatePassword`, `Invitations::Accept` | the three services that set a password include it |
  | `SignIn::Passkeys::RelyingParty` | `PasskeyChallenges`, `Admin::PasskeyEnrolment` | the one place a passkey's site is decided |
  | `SignIn::Passkeys::Registration` | passkeys and setup controllers | the add ceremony |
  | `SignIn::Passkeys::Check` | sessions, second-factor, confirmations controllers | the sign-in and confirm ceremonies |
  | `SignIn::Passkeys::Policy` | `Authentication`, enrolments and setup controllers, the Passkeys card component, the Settings view | who must hold a passkey |
  | `SignIn::Passkeys::Add` / `Remove` / `Rename` | passkeys controller (Add also setup; Remove's `.last_required` too) | the account screen's writes |
  | `SignIn::RecoveryCodes::Generate` | recovery-codes controller | the one writer of a set |
  | `SignIn::Sessions::End` | `Session` | an expired session meets its end |
  | `SignIn::Sessions::EndAll` | users controller | an owner ends another's sessions |
  | `SignIn::Sessions::EndOthers` | account-sessions controller | sign out everywhere else |
  | `SignIn::Sessions::SweepJob` | `config/recurring.yml` | hourly |
  | `SignIn::Sso` | sessions and SSO-sessions controllers, `SsoStarts`, `Setup::SystemCheck`, `Invitations::Accept`, the invitation page | `required?`, the callback origin and the reasons a screen words |
  | `SignIn::Sso::Provider` | sessions controller, `SsoStarts`, `PasswordResetRequestJob`, `Setup::SystemCheck`, the initializer | the provider from the environment |
  | `SignIn::Sso::Authorization` | `SsoStarts` | the redirect to the provider |
  | `SignIn::Sso::Callback` | SSO-sessions controller | the code exchanged on the way back |
  | `SignIn::Sso::Unavailable` | `SsoStarts`, `Setup::SystemCheck` | rescued and worded by the screens |
  | `SignIn::Sso::Admit` | SSO-sessions controller (`.call`, `.refuse`, `OWNER`, `MISMATCH`) | an identity to an account, its answer's words, and `.refuse`, the one writer of `sso.refused`, which the callback's owner defence calls too |
  | `SignIn::Sso::LinkedEvent` | `Invitations::AcceptWithSso` (`include`) | the one writer of `sso.linked`, shared by `Link` and the invitation that makes a linked account |
  | `SignIn::Sso::Unlink` | SSO-links controller (`.new`, `#call`, `#mailed?`) | an owner unlinks, and the toast promises the mail only when it was queued |
  | `SignIn::Sso::RecheckJob` | `config/recurring.yml` | hourly |

  Not entries, because no code outside `SignIn::` names them at `31807a81`: `SignIn::Outcome` (a comment in `Admin::SignInLocks` only; outside code reads an outcome's fields, never the constant), `SignIn::Methods::Entry`, `SignIn::Sso::Admit::Answer` (read through `#accepted_invitation?`), `SignIn::Sso::Link`, `IdToken`, `Refresh`, `Identity`, `Configuration`, `SignIn::Password::Leaked`, `SignIn::Passkeys::Credential` and `SignIn::OutsideCall`. `Admin::Ui::OrDividerComponent` and `WayInButtonComponent` reach nothing of `SignIn::`.

  If Step 1's scan finds a reference this list lacks, check it is a real call site in code, not a comment the stripper missed. Add it with its reason, and name it in the task report. Never widen an entry to a prefix.

  Tests:
  - `"the guard is looking at the code"`: more than 100 outside sources, including `app/controllers/admin/sessions_controller.rb` and `config/recurring.yml`; more than 30 own sources.
  - `"code outside SignIn names only its entry points"`: the message lists `path:line: Name`.
  - `"every entry point is still reached"`: a stale entry fails, naming it.
  - `"every entry point says why"`.
  - `"SignIn names nothing of CS Studio's screens"`: over `OWN`, comments stripped, fail on `/(?<![\w:])(?:::)?Admin::/`, `DependencyDirectionTest::COMPONENT`, `/\b\w*Controller\b/`, `/\burl_helpers\b/` and `/Rails\.application\.routes/`. Report `path:line: pattern: text`. `app/jobs/sign_in/` is in `OWN`, which `dependency_direction_test` does not read.
  - `"the reference pattern reads what it should"`: `SignIn::Sso::Admit::OWNER` → `SignIn::Sso::Admit`; `SignIn.store` → `SignIn`; `::SignIn::Rules.x` → `SignIn::Rules`; `MySignIn::X` → nothing; `SignInMailer` → nothing; an ERB `<%# SignIn::Proof %>` → nothing; a YAML `# class: SignIn::X` → nothing.
- [ ] **Step 2: Check that the guard bites.** Add `SignIn::Outcome` to a line of `app/controllers/admin/sessions_controller.rb` (`_ = SignIn::Outcome`; the root's, and no entry). Expected: FAIL naming it. Then add `Admin::Ui` to `app/models/sign_in/proof.rb`. Expected: FAIL. Then add a bogus entry `"SignIn::Nothing"`. Expected: the stale test FAILS. Revert all three.
- [ ] **Step 3: Run.** `bin/rails test test/lib/sign_in_boundary_test.rb test/lib/sign_in_namespace_shadow_test.rb test/lib/dependency_direction_test.rb test/lib/admin_namespace_shadow_test.rb`, then `bin/rails test`. Expected: PASS.
- [ ] **Step 4: Commit.** `test: code outside SignIn reaches it only through named entry points, and SignIn names no screen`

---

### Task 10: Docs, CLAUDE.md, CHANGELOG, and the whole suite

**Files:**
- Modify: `app/models/sign_in.rb` (the module comment), `CLAUDE.md`, `docs/reference/{access-control-and-audit,hosting,users-groups-tokens,mail,content-blocks-and-types,settings-languages-ai,design-system}.md`, `CHANGELOG.md`, `lib/content_spiel/plugins.rb` (comments, if any old name is left).

- [ ] **Step 1: The root comment.** Rewrite the head comment of `app/models/sign_in.rb` to list the six sub-namespaces and the root's core (`Rules`, `Methods`, `Proof`, `Outcome`, `SpentChallenge`, `OutsideCall`), one line each. Say that Protection, Password, the Passkeys ceremonies, Sso's protocol objects and the root are the plain objects spec §9 makes shareable with a later members' sign-in, and that the services and jobs (`Passkeys::Add…`, `RecoveryCodes`, `Sessions`, `Sso::Admit/Link/Unlink/RecheckJob`) act on CS Studio's `User` and `Session`. Name the two guards. Comment only: `git diff app/models/sign_in.rb` touches no line outside the comment.
- [ ] **Step 2: CLAUDE.md.**
  - In the access-control index entry, replace the old paths with `app/models/sign_in.rb` and `app/{models,services,jobs}/sign_in/` (naming the passkey files at their new paths), and drop `app/models/passkeys/`, `app/services/{passkeys,recovery_codes,sso}/`, `app/jobs/sso/`, `app/models/sign_in_{rules,methods}.rb`, `app/models/sign_in/oidc.rb` and `app/models/sign_in/oidc/` (the paths it names at `31807a81`).
  - In "Rules a change can break silently", rename `Passkeys::Policy`, `SignIn::RelyingParty`, `SignInRules` and `Sso::RecheckJob`.
  - Under "Where a class goes", add one sentence: a domain spans the layer folders under one namespace (`SignIn::` across `app/models`, `app/services`, `app/jobs`), no deeper than two levels, held by `test/lib/sign_in_namespace_shadow_test.rb` and `test/lib/sign_in_boundary_test.rb`.
- [ ] **Step 3: docs/reference.** Rename every old name and path in the seven files. At `31807a81`, Step 5's pattern matches 46 lines in access-control-and-audit.md, 28 in hosting.md, 8 in users-groups-tokens.md, 5 in mail.md, 4 in content-blocks-and-types.md, 2 in settings-languages-ai.md and 1 in design-system.md. In `access-control-and-audit.md`, add the two guards to "Rules a change can break silently" with their test names. In `hosting.md`, note that a span's `error.type` for the leaked check is `SignIn::Password::Leaked::Unavailable`; its telemetry table's `SignIn::Oidc::SPAN_REASONS`, `DISCOVERY_REASONS` and `RECHECK_REASONS` become `SignIn::Sso::…`. In `content-blocks-and-types.md`, the gem docs say the hook replays into `SignIn::Methods`.
- [ ] **Step 4: CHANGELOG.md, `## Unreleased` only.**
  - In the passkeys Breaking line, keep `Passkey`, `RecoveryCode` and `PasskeyChallenges` and drop `Passkeys`/`RecoveryCodes` with their owner words.
  - Delete the three Breaking lines "A new top-level name, `SignInMethods`…", "…`SignInRules`…" and "…`Sso` (`app/services/sso/`, `app/jobs/sso/`)…" (decision 11: never released, so deleted, not mapped). No new top-level name remains.
  - Under "For a gem or an outside caller":
    - `SignIn::PasswordAttempt` → `SignIn::Password::Attempt`;
    - `SignIn::Throttle#…` → `SignIn::Protection::Throttle#…`;
    - the passkey objects → `SignIn::Passkeys::{RelyingParty,Registration,Check}`;
    - the hook's line → `SignIn::Methods`;
    - any `SignIn::Oidc`/`Sso::` → `SignIn::Sso`.
  - Add one Breaking line (decision 12): "Sign-in's classes are one namespace, `SignIn::`, with no alias for the old names." Map each name released in 0.3.0 to its new one, and nothing unreleased:
    - `SignIn::Throttle`, `BotCheck`, `KnownDevice`, `LockoutMailJob` → `SignIn::Protection::…` (`SignIn::Outcome` keeps its name);
    - `SignIn::PasswordAttempt` → `SignIn::Password::Attempt`;
    - `SignIn::LeakedPassword` → `SignIn::Password::Leaked`;
    - `Users::LeakedPasswordRule` → `SignIn::Password::LeakedRule`;
    - `Sessions::End`, `EndAll`, `EndOthers`, `SweepJob` → `SignIn::Sessions::…`.

    The line also says three things. The top-level name `Sessions` is gone, so a gem's owner `sessions` is no longer refused. A lockout mail or session sweep queued but not yet run when a site upgrades fails once (the sweep runs again within the hour). A query on the leaked check's `error.type` reads the new class name.
  - Elsewhere in the unreleased section, the moved names take their new ones in place: under "Added", the sign-in page's line (`SignInMethods` → `SignIn::Methods`) and the daily re-check's (`Sso::RecheckJob` → `SignIn::Sso::RecheckJob`); under "For a gem", also `Passkeys::Policy#enrolment_due?` → `SignIn::Passkeys::Policy#enrolment_due?` and the second `SignIn::PasswordAttempt` line. At `31807a81` that is lines 20, 25, 78–80, 83, 84, 86 and 89 of the section (`awk '/^## Unreleased/,/^## [0-9]/' CHANGELOG.md | grep -n …`).
  - Released sections are not edited.
- [ ] **Step 5: The greps must come back empty.**

  ```sh
  git grep -nP 'SignInRules|SignInMethods|LeakedPasswordRule|SignIn::(Throttle|BotCheck|KnownDevice|LockoutMailJob|PasswordAttempt|LeakedPassword|RelyingParty|Passkey(Registration|Check|Credential)|Oidc)\b|SignIn::Protection::Outcome|(?<![\w:])(Passkeys|RecoveryCodes|Sessions|Sso)::|models/sign_in/oidc|services/(passkeys|recovery_codes|sessions|sso)/|jobs/(sessions|sso)/|models/passkeys/|models/sign_in_(rules|methods)' -- . ':!docs/superpowers' ':!CHANGELOG.md'
  ```

  This must print nothing. Then run `awk '/^## Unreleased/,/^## [0-9]/' CHANGELOG.md` through the same `grep -P` pattern; the only hits allowed are the 0.3.0 names inside the new Breaking line's mapping (no `SignInRules`, `SignInMethods`, `Sso::` or `Passkeys::` at all: those were never released).

  `git grep -nE "(controller|to):\s*['\"][^'\"]*(sign_in|sso|passkey|session)" config/routes.rb` names only `admin/…` controllers, which did not move (Review Focus 4).
- [ ] **Step 6: The whole suite.** Check the machine is quiet (`sysctl -n vm.loadavg`). Then run `bin/rails tailwindcss:build`, `PARALLEL_WORKERS=6 bin/rails test:system`, and `bin/ci`. Expected: all green. `bin/changelog-guard main` exits 0 (`plugins.rb` changed and the unreleased section did too).
- [ ] **Step 7: Commit.** `docs: the sign-in domain under SignIn:: in CLAUDE.md, the references and the changelog`

The pull request's "Documentation" section names the guide's integrator pages that cite `SignInMethods` (the sign-in method hook) and the `error.type` value, or "none" if the guide names neither.
