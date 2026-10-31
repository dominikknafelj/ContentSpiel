# Theme choices Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A theme declares named choices in `theme.yml` (section styles, page templates, card icons), an editor picks one, and the name is stored on the section, the page or the card, so the look follows the content and never its position.

**Architecture:** One data file per theme, read by `Theme::Declarations` with YAML's safe loader and checked by `Theme::Check` at the plain depth; the default theme's declarations are a file of the same format (`config/theme/default.yml`). `Theme#choices(list)` is the one reader, reached from `ContentModel` only through a callable assigned in `config/initializers/types.rb`. Block-side choices are a new field type, `:theme_choice`, written on a field-type registry (`ContentModel::FieldTypes`) onto which all ten existing scalar types move first; a page's template lives in a new `pages.settings` jsonb carried in the published copy, replacing the `page_type` enum by a migration that rewrites rows and copies. The Card block is a built-in made with the generator; its tokens and the default icon set wait for the Design System.

**Tech Stack:** Rails 8.1, ViewComponent, Psych (`YAML.safe_load`), Nokogiri (strict XML), Stimulus (none new), Tailwind, Minitest, Capybara on Cuprite.

**Spec:** `docs/superpowers/specs/2026-10-31-theme-choices-design.md` (decisions 1–11, "The owner's answers", "Testing"; read it whole). The recipe: `docs/reference/content-blocks-and-types.md`, "Adding a block type" (steps 0–11). The theme: `docs/reference/theming.md` ("Checking a folder", "The contract", "In tests").

## Global Constraints

- Work only in `/Users/dknafelj/src/ContentSpiel-theme-choices` on branch `theme-choices`. Never push. Commit email `12701622+dominikknafelj@users.noreply.github.com`. Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT`.
- Every test command is prefixed `PGGSSENCMODE=disable`. Never run a build while tests run. System tests: `bin/rails tailwindcss:build` first, then `PARALLEL_WORKERS=6`, one file at a time, only when `sysctl -n vm.loadavg` (one-minute) is well under the core count. Implementers run their own files and the directories named in their task, not the whole suite.
- The three lists, exactly: `section_styles`, `page_templates`, `icons`. Entry keys: `name` and `label` always; `fields` for a page template; `file` for an icon. Page fields: the closed set `hero`.
- A name: `/\A[a-z][a-z0-9_]{0,39}\z/` (lowercase letters, digits, underscores, a letter first, at most 40 characters), unique in its list.
- A label: a String, or a mapping of locale codes to Strings; shown in CS Studio's interface language, then `en`, then the first given. Always escaped text.
- Exact sentences: an unknown list `` `<key>` is not a list a theme may declare: section_styles, page_templates, icons ``; `settings:` gets "Appearance settings are not built yet." Every check sentence starts with the file and ends with what to do.
- An icon file: an SVG under the theme's `assets/images`, at most 32 KB (32,768 bytes), well-formed XML with an `svg` root, no `script`, `foreignObject` or `style` element, no `on…` attribute, no `href`/`xlink:href` that is not `#…`, no `DOCTYPE` or entity.
- The default: no style for a section; the theme's first page template for a page; no icon for a card. A stored name the theme does not know is drawn as the default and nothing stored changes.
- A select appears for a section's style or a card's icon when the list has one entry or more, for a page's template when it has two or more, and always when the stored name is not in the theme (shown first, selected, by its name, marked "not in this theme").
- Admin keys (never literals): "Style", "Template", "Icon", "Default", "No icon", "not in this theme".
- Contract names (promises; each with a `CHANGELOG.md` line): `theme.yml` and its three lists; `views/pages/templates/_<name>.html.erb`; the helper `page_template`; the template locals `page`, `post`, `list_block`; the Section's `style` (ledger line `block page columns layout background width style`) and the class `content-section--style-<name>`; the Card's line `block page title text link icon icon_name`; the Card's tokens (design question A); the default icon names (design question B).
- `:link` accepts `http`, `https`, `mailto` and a site-relative address starting with exactly one `/`; `:url` is not changed.
- `Page#page_type` and `Page#landing?` go without an alias; no reader of old copies is written.
- Comments on lines this work writes or moves state invariants, never "Task N", rounds or spec steps.
- Every task that changes a table `test/lib/theming_reference_test.rb` holds updates that table in `docs/reference/theming.md` in the same task; the prose is the last task's.

## Review Focus

1. **A site-relative link a browser reads as another host** (`/\evil.example`, `/ /evil`, a tab or a line break inside, `\\evil`): browsers treat a backslash after the first slash as `//`. `:link` accepts only a `/` followed by no `/` or `\` and no white space or control character anywhere; `HTTP://X` (uppercase scheme) is accepted as http. → Task 2, test "a link that a browser would send to another host is refused: a backslash, white space and control characters, wherever they stand".
2. **An SVG fence spelled another way** (`<svg:script>` under a prefix, `ONLOAD=`, `<use href="data:…">`, `xlink:href="javascript:…"` under another prefix bound to the xlink namespace, a `<SCRIPT>` in a non-SVG namespace): the fence compares local names case-insensitively and namespaces by URI, not by prefix. → Task 4, test "the fence is not fooled by a prefix, a case or a namespace: a prefixed script, ONLOAD, a use with a data address, an xlink bound to another prefix".
3. **A record carried with a name the theme no longer declares**: a duplicated section, and "Discard changes…" writing back a template or a style from the copy, must save (the name is not chosen, it is carried). → Task 5, test "duplicating a section whose style the theme no longer declares copies the style and saves"; Task 7, test "discard writes back a template the theme no longer declares".
4. **YAML scalars that are not strings** (`name: yes`, `name: 2`, `label: null`, `label: { en: 3 }`, `fields: hero` instead of a list, an entry that is a String): each is one problem naming the list, the entry's place and the key, never a `NoMethodError` out of a reload. → Task 3, test "values of the wrong kind are one problem each, named by list, place and key, and nothing raises".
5. **The migration on every copy of a page, not only the current one**: a scheduled page's pending copy, a superseded copy and a copy the first-copies migration took all lose `page_type` and gain `settings`. → Task 7, test "every copy of a page is rewritten: current, pending and superseded, and a copy with no page_type is left as it is".

---

## File Structure

- `app/models/content_model.rb` (new) — the namespace's `theme_choices` callable (Task 5).
- `app/models/content_model/field_type.rb`, `field_types.rb` (new) — the field-type value and registry with the twelve types (Tasks 1, 2, 5).
- `app/models/content_model/definition.rb`, `field_set.rb`, `content_type_definition.rb`, `field_group_definition.rb`, `block_type_definition.rb` — ask the registry (Tasks 1, 5).
- `app/components/admin/fields/*_field.rb` — each input answers `self.display` (Task 1); `link_field.*`, `theme_choice_field.*` (new, Tasks 2, 5).
- `app/components/admin/ui/field_component.rb`, `app/components/admin/editor_screen/shared_fields_component.rb`, `app/models/audit/snapshot.rb` — ask the registry (Task 1).
- `app/values/theme/declarations.rb`, `app/values/theme/choice.rb` (new), `config/theme/default.yml` (new), `app/values/theme.rb`, `app/values/theme/check.rb`, `app/values/theme/contract.rb`, `app/values/theme/scaffold.rb`, `lib/theme_folder.rb` (Tasks 3, 4, 9).
- `app/values/theme/icon_file.rb` (new) — the SVG fence and the inline form (Task 4).
- `app/models/block_types/section.rb`, `app/components/blocks/section_component.{rb,html.erb}`, `app/components/admin/editor_screen/section_card_component.*` (Task 6).
- `db/migrate/20261031120000_replace_page_type_with_page_settings.rb` (new), `app/models/page.rb`, `app/models/publishing.rb`, `app/services/pages/save.rb`, `app/services/publishing/discard_changes.rb`, `app/helpers/theme_helper.rb`, `app/views/pages/show.html.erb`, `app/views/pages/templates/_standard.html.erb`, `_landing.html.erb` (new), `app/models/public_site/urls.rb`, `db/seeds.rb` (Task 7).
- `app/controllers/admin/pages_controller.rb`, `app/components/admin/editor_screen/page_settings_form_component.*`, `new_page_form_component.*` (Task 8).
- `app/models/block_types/card.rb`, `app/components/blocks/card_component.{rb,html.erb}`, `app/assets/tailwind/themes/default/card.css` (generated, Task 10; tokens Task 11).
- `test/fixtures/themes/choices/`, `test/fixtures/themes/section_grid/`, `test/fixtures/themes/card/` (new fixture themes, Tasks 4–6, 9, 13), `test/support/theme_test_helper.rb`, `config/environments/test.rb`.
- `CHANGELOG.md` (new, Task 3), `docs/reference/theme-choices.md` (new, Task 14).

---

### Task 1: The field-type registry, with the ten existing types on it

**Files:**
- Create: `app/models/content_model/field_type.rb`, `app/models/content_model/field_types.rb`
- Modify: `app/models/content_model/definition.rb`, `app/models/content_model/field_set.rb`, `app/components/admin/ui/field_component.rb`, `app/components/admin/editor_screen/shared_fields_component.rb`, every `app/components/admin/fields/<type>_field.rb` of the ten scalar types, `app/models/audit/snapshot.rb`, `config/initializers/types.rb`
- Test (new): `test/models/content_model/field_types_test.rb`, `test/components/admin/fields/field_types_studio_test.rb`, `test/lib/field_type_branches_test.rb`

**Interfaces:**
- Produces:
  - `ContentModel::FieldType = Data.define(:name, :cast, :options, :validate, :translatable, :audit)`: `cast` `->(value) { stored or nil }` (handed a value that is not blank); `options` `->(options, earlier_fields) { raise ArgumentError, … }` (the type's refusals at registration, the existing messages word for word); `validate` `->(field:, value:, raw:, errors:, stored:, translations:) { … }` (adds to `errors` under `field.name`; `stored` is the value already stored for the field, or nil; `translations` the object's `{ locale => values }`, which the string type reads for its limit in every language); `translatable` Boolean (offered to AI translation when translated); `audit` `:value` or `:digest`.
  - `ContentModel::FieldTypes.register(type)`, `.fetch(name)` (raises `KeyError` naming the known types), `.find(name)`, `.names`, `.all`, `.reset!`, `.register_built_ins`. `register_built_ins` registers `string text code integer boolean date url select content_type tag` in that order (later tasks append `link`, `theme_choice`).
  - `ContentModel::Definition::SCALAR_TYPES` goes: its readers ask `ContentModel::FieldTypes.names` (`Definition#field` refuses a type that is neither registered nor a group type, with the same message).
  - `ContentModel::FieldSet::Base.new(values, translations, locale:, fallback:, stored: {})`: `stored` is the hash of untranslated values already stored, handed to each `validate` (used from Task 5; today every caller passes nothing).
  - Every `Admin::Fields::<Type>Field` answers `self.display(field, value)` → `String`, `nil` or `Admin::EditorScreen::SharedFieldsComponent::Code`, moved out of `SharedFieldsComponent.display`'s `case`, which becomes `"Admin::Fields::#{field.type.to_s.camelize}Field".constantize.display(field, value)` for a scalar and keeps its two group branches.

- [ ] **Step 0 (worktree setup, once):** `PGGSSENCMODE=disable bin/rails db:test:prepare`, then `bin/rails tailwindcss:build`.

- [ ] **Step 1: Write the failing tests**

`field_types_test.rb`:
- "the registry holds the ten built-in scalar types in their order, and fetch names the known types for an unknown one".
- "every registered type answers every question: a cast, its option rules, a validation, whether it is translatable, its audit form" (iterate `FieldTypes.all`; `cast`, `options`, `validate` respond to `call`; `translatable` is `true`/`false`; `audit` in `%i[value digest]`).
- "string and text are translatable, code is audited as a digest, the rest as their value".

`field_types_studio_test.rb`: "every registered type has its input in Admin::Fields and a read-only display" (`"Admin::Fields::#{name.camelize}Field".safe_constantize` responds to `display`).

`field_type_branches_test.rb`: "no file outside the field-type registry branches on a scalar field type's name" — source grep of `app/` and `lib/` (comments stripped) for `type == :<name>`, `type != :<name>`, `when :<name>` inside a `case field.type`/`case type`, `include?(field.type)` and the constants `SCALAR_TYPES`/`TRANSLATABLE_TYPES`, for every name in `FieldTypes.names`; allowed: `app/models/content_model/field_types.rb`. Group types (`group`, `groups`) are not scalar and are not in the grep.

- [ ] **Step 2: Run them to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/models/content_model/field_types_test.rb test/components/admin/fields/field_types_studio_test.rb test/lib/field_type_branches_test.rb`
Expected: FAIL (uninitialized constant `ContentModel::FieldTypes`).

- [ ] **Step 3: Implement**

Move each branch into its type: the refusals of `Definition#field` that name a type (select's `options:`, code's `translated`, `blank:` for select and content_type, `control:` for select, `help:`/`placeholder_from:`/`max:` for string) into `options`; `FieldSet#cast`'s branches and `cast_code` into `cast`; `validate_fields`' per-type errors into `validate`; `TRANSLATABLE_TYPES` into `translatable`; `Audit::Snapshot`'s `field.type == :code` (three places) into `audit == :digest`; `Field#segmented?` reads `options[:control] == :segmented` alone (the option is refused off a select). What stays in `FieldSet`: blank normalisation, groups, and the loop that calls each type's `validate`; `validate_lengths_in_every_language` moves into the string type's `validate` (it reads `translations:`), keeping its one-error-per-field rule. `config/initializers/types.rb`: `ContentModel::FieldTypes.reset!` and `.register_built_ins` first in the `to_prepare`, before `BlockTypes.reset!`. A comment at the registry's top states the invariant: a field type is one entry here and one input under `Admin::Fields`, and nothing else branches on its name.

- [ ] **Step 4: Run the new tests and every existing test that touches fields, unchanged**

Run: `PGGSSENCMODE=disable bin/rails test test/models/content_model test/models/content_block_test.rb test/models/audit test/components/admin test/integration/open_types_test.rb test/integration/admin/content_blocks_test.rb test/services/ai test/models/resume_fields_test.rb test/lib`
Expected: PASS with no existing test edited (the owner's answer 2). A failing existing test means a behaviour moved wrongly: fix the move, not the test.

- [ ] **Step 5: Commit** — `ref: field types are one registry, and the ten built-ins live on it`

---

### Task 2: The `:link` field type

**Files:**
- Modify: `app/models/content_model/field_types.rb`, `config/locales/en.yml` (only if the error needs words beyond `:invalid`)
- Create: `app/components/admin/fields/link_field.{rb,html.erb}` (from `url_field`, `type="text"`, `inputmode="url"`, no `pattern`)
- Test: `test/models/content_model/link_field_test.rb`, `test/components/admin/fields/link_field_test.rb`

**Interfaces:**
- Produces: field type `link` (`translatable: false`, `audit: :value`, `translated: true` refused: "link fields can't be translated (the address is the same in every language)"), and `ContentModel::FieldTypes.link?(value) → Boolean`, the one rule, which the Card's component (Task 10) asks before it draws a stored value.

- [ ] **Step 1: Write the failing tests** (`link_field_test.rb`)
- "a link takes http, https and mailto addresses and a site-relative one" (`https://example.com/a`, `HTTP://EXAMPLE.COM`, `mailto:a@b.example`, `/about`, `/about?x=1#y` valid).
- "a link refuses another host by //, javascript:, data:, a bare word and a relative path" (`//host`, `javascript:alert(1)`, `data:text/html,x`, `about`, `about/us`: each `errors[:target]` includes `:invalid`).
- "a link that a browser would send to another host is refused: a backslash, white space and control characters, wherever they stand" (`/\\evil.example`, `\\\\evil`, `/ /evil`, `"/a\tb"`, `"/a\nb"`, `"https://a b.example"`).
- "a link is cast stripped and blank is nothing, and :url is unchanged" (`"  /a  "` stored as `/a`; the `:url` cases of `field_set_test.rb` still pass and `/about` is still refused by `:url`).
- "a link field can't be translated".
- `link_field_test.rb` (component): "a text input with inputmode url and the stored address, and no pattern or maxlength".

- [ ] **Step 2: Run them to see them fail** — `PGGSSENCMODE=disable bin/rails test test/models/content_model/link_field_test.rb test/components/admin/fields/link_field_test.rb` (unknown field type `:link`).

- [ ] **Step 3: Implement** `link?`: refuse any character in `\s`, `\p{Cc}` or `\\`; accept `\A/(?!/)`; otherwise `URI.parse(value).scheme&.downcase` in `%w[http https mailto]` (rescuing `URI::InvalidURIError` as false). Register `link` after `tag`.

- [ ] **Step 4: Run them, plus `test/models/content_model test/components/admin/fields test/lib/field_type_branches_test.rb`** — PASS.

- [ ] **Step 5: Commit** — `feat: a link field type for site and outside addresses`

---

### Task 3: `theme.yml`: the format, the reader, the default declarations and the check

**Files:**
- Create: `app/values/theme/declarations.rb`, `app/values/theme/choice.rb`, `config/theme/default.yml`, `CHANGELOG.md`
- Modify: `lib/theme_folder.rb` (`theme.yml` admitted at the top; the stranger sentence names it), `app/values/theme.rb` (`choices`, `choice`; declarations kept per `Theme`), `app/values/theme/check.rb` (declaration problems at the plain depth), `app/values/theme/contract.rb` (`DECLARATIONS = "theme.yml"`, `CHOICE_LISTS = %w[section_styles page_templates icons]`, `PAGE_FIELDS = %w[hero]`)
- Create fixture: `test/fixtures/themes/choices/theme.yml` (section styles `services` and `contact`, the second with an `en`/`de` label; page templates `standard`, `landing`; icons left out until Task 4), `test/support/theme_test_helper.rb` (`choices_theme`, `with_choices_theme`)
- Test: `test/values/theme/declarations_test.rb`, `test/values/theme/check_test.rb`, `test/lib/theme_folder_test.rb`, `test/values/theme_test.rb`, `test/integration/theme_pages_test.rb`

**Interfaces:**
- Produces:
  - `Theme::Choice = Data.define(:list, :name, :labels, :fields, :file, :from)`; `#label_for(locale) → String`; `fields` an Array of Strings (page templates), `file` a String or nil (icons), `from` `:theme` or `:default` (whose file it is: an entry naming the default's entry and bringing no file is `:default`).
  - `Theme::Declarations.read(source, file:) → [Hash{String => Array<Theme::Choice>}, Array<String>]` (lists declared, problems); `.of(folder) → Hash` (merged with the default's: a list not declared is the default's whole, a declared one, even empty, replaces it); `.default → Hash` (read from `config/theme/default.yml`, memoised for the process; a problem in it raises at boot); `.problems(folder) → Array<String>`.
  - `Theme#choices(list) → Array<Theme::Choice>` (list as Symbol or String; a theme without a folder and a refused theme answer the default's); `Theme#choice(list, name) → Theme::Choice or nil`.
  - `Theme.load` hands the declarations to `new(..., declarations:)`, read once per `Theme`.
  - `config/theme/default.yml`: `page_templates` Standard (`standard`, no fields), Landing (`landing`, `fields: [hero]`); `icons: []` (filled by Task 12); no `section_styles` key, which means none.

- [ ] **Step 1: Write the failing tests**

`declarations_test.rb`:
- "a list a theme does not declare is the default's, and a declared one replaces it, an empty one included".
- "an entry naming the default's entry with no file of its own is the default's, and its label and fields are the theme's".
- "a label is a String or a mapping of languages, read in the interface's language, then English, then the first given".
- "an unknown list is refused by name, with the three it may be" (exact sentence from Global Constraints) and "settings: is refused with its own sentence".
- "an unknown key, a bad name, a duplicate name, a missing label and an unknown page field are one problem each".
- "values of the wrong kind are one problem each, named by list, place and key, and nothing raises" (Review Focus 4: `name: yes`, `name: 2`, `label: null`, `label: { en: 3 }`, `fields: hero`, an entry that is a String, a top that is a list).
- "a YAML error is one problem with its line, an alias and a tag are refused, and a file that is not UTF-8 is one problem".
- "a file of comments only declares nothing".
- "the default theme's own file is sound and declares Standard, Landing and no section style".

`check_test.rb`: "theme.yml is checked at the plain depth: its problems are the theme's, each starting with theme.yml". `theme_folder_test.rb`: "theme.yml is the one file admitted beside the four folders, and the stranger sentence names it"; "the fingerprint moves with theme.yml". `theme_test.rb`: "a theme answers its choices, a theme without a folder and a refused theme the default's". `theme_pages_test.rb`: "a theme.yml refused on a reload leaves CS Studio working and every public page saying why".

- [ ] **Step 2: Run them to see them fail** — `PGGSSENCMODE=disable bin/rails test test/values/theme test/values/theme_test.rb test/lib/theme_folder_test.rb test/integration/theme_pages_test.rb`

- [ ] **Step 3: Implement.** `YAML.safe_load(source, permitted_classes: [], aliases: false, filename: file)`; rescue `Psych::SyntaxError` (its `line`) and `Psych::DisallowedClass`/`Psych::AliasesNotEnabled`/`Psych::BadAlias` as one problem each. `ThemeFolder::ENTRIES` stays the four folders; add `FILES = %w[theme.yml]` and admit it in `strangers` and `check_shape!`; it is a file of the folder, so `files` and `fingerprint` include it already (assert, don't add code). `Theme::Check.problems` adds `Declarations.problems(folder)` after the strangers. Start `CHANGELOG.md`: `# Changelog`, `## Unreleased`, the four headings `### Theme contract`, `### Environment`, `### Migrations needing action`, `### Removed`, and this task's line under Theme contract ("Added `theme.yml` at a theme folder's top: the lists `section_styles`, `page_templates` and `icons`").

- [ ] **Step 4: Run Step 2's command plus `test/tasks/theme_tasks_test.rb test/lib/production_boot_test.rb test/lib/theme_guards_test.rb`** — PASS.

- [ ] **Step 5: Commit** — `feat: a theme declares its choices in theme.yml, checked strictly`

---

### Task 4: Icon files: the fence, the inline form and the served address

**Files:**
- Create: `app/values/theme/icon_file.rb`
- Modify: `app/values/theme/declarations.rb` (an icon entry's `file` is checked), `app/values/theme.rb` (`icon_svg`, `icon_asset`), `config/environments/test.rb` (the `choices` fixture's `assets/images` on the asset paths, as the plain theme's are)
- Fixture: `test/fixtures/themes/choices/theme.yml` gains `icons: [{ name: brush, label: Design, file: icons/brush.svg }]`, `test/fixtures/themes/choices/assets/images/icons/brush.svg` (a 24-unit outline in `currentColor`)
- Test: `test/values/theme/icon_file_test.rb`, `test/values/theme/declarations_test.rb`, `test/values/theme_test.rb`

**Interfaces:**
- Produces:
  - `Theme::IconFile.problems(path, file:) → Array<String>` (the fence; `file` is the name the sentence starts with); `Theme::IconFile.inline(source) → String` (the root with `aria-hidden="true"` and `focusable="false"` added, nothing else changed).
  - `Theme#icon_svg(name) → ActiveSupport::SafeBuffer or nil` (nil for blank or undeclared; read once per `Theme`, memoised by name); `Theme#icon_asset(name) → String or nil` (the logical asset path for `image_path`: the entry's `file`, which is relative to `assets/images` for a theme's entry and to `app/assets/images` for a `:default` one). `icon_svg` reads the file from the theme folder for `from: :theme` and from `Rails.root.join("app/assets/images", file)` for `from: :default`.
  - `MAX_BYTES = 32_768`.

- [ ] **Step 1: Write the failing tests** (`icon_file_test.rb`)
- "a well-formed svg passes, and inline adds aria-hidden and focusable to its root and changes nothing else".
- "a file that is not XML, has another root, is over 32 KB or holds a DOCTYPE or an entity is refused, each naming the file and what to take out".
- "a script, a foreignObject, a style element, an on-attribute and an href that is not a fragment are each refused" (`href="#g"` passes).
- "the fence is not fooled by a prefix, a case or a namespace: a prefixed script, ONLOAD, a use with a data address, an xlink bound to another prefix" (Review Focus 2).
- `declarations_test.rb`: "an icon with a name the default does not have must bring its file; a file that is missing, not under assets/images or not an svg is refused".
- `theme_test.rb`: "icon_svg inlines a declared icon once per theme and is nil for blank and unknown names"; "icon_asset is the served path of the theme's file".

- [ ] **Step 2: Run them to see them fail** — `PGGSSENCMODE=disable bin/rails test test/values/theme/icon_file_test.rb test/values/theme/declarations_test.rb test/values/theme_test.rb`

- [ ] **Step 3: Implement** with `Nokogiri::XML(source) { |c| c.strict.nonet }` (no network, no entity substitution); walk every element and attribute by `name.downcase` and `namespace&.href`; refuse `doc.internal_subset` (a DOCTYPE). The file is not rewritten or sanitised beyond the two attributes on the root (a comment says why: a fence, not a sanitiser). Ids are not refused.

- [ ] **Step 4: Run them, plus `test/values/theme test/lib/theme_folder_test.rb`** — PASS.

- [ ] **Step 5: Commit** — `feat: a theme's icon files, fenced, inlined on the site and served as images`

---

### Task 5: The `:theme_choice` field type, the stored-name rule and the select

**Files:**
- Create: `app/models/content_model.rb`, `app/components/admin/fields/theme_choice_field.{rb,html.erb}`, `config/locales/admin/fields.en.yml` keys (`theme_choice.default`, `theme_choice.no_icon`, `theme_choice.not_in_theme`)
- Modify: `app/models/content_model/field_types.rb`, `app/models/content_model/content_type_definition.rb` and `field_group_definition.rb` (refuse the type), `app/models/content_model/block_type_definition.rb` (`refuse_outside!`), `app/models/content_block.rb` (`stored:` and `carried_settings`), `app/services/content_blocks/duplicate.rb`, `app/components/admin/ui/field_component.rb` (`render?` follows its input), `config/initializers/types.rb`
- Test: `test/models/content_model/theme_choice_field_test.rb`, `test/components/admin/fields/theme_choice_field_test.rb`, `test/models/content_model/block_type_definition_test.rb`, `test/services/content_blocks/duplicate_test.rb`, `test/integration/theme_pages_test.rb`, `test/components/admin/editor_screen/shared_fields_component_test.rb`, `test/components/admin/editor_screen/held_fields_test.rb`

**Interfaces:**
- Consumes: `Theme#choices` (Task 3), `FieldType` (Task 1), `FieldSet::Base.new(…, stored:)`.
- Produces:
  - `ContentModel.theme_choices` / `.theme_choices=` (a callable `->(list) { Array of objects answering name and label_for(locale) }`; raises a clear error when unset, as `RichText.component_renderer` does), assigned in `config/initializers/types.rb` inside the `to_prepare`: `ContentModel.theme_choices = ->(list) { Theme.current.choices(list) }`.
  - Field type `theme_choice`: option `of:` required, one of `section_styles`, `icons` (refused otherwise, naming both); `translated: true` refused; `translatable: false`; `audit: :value`; `validate`: blank passes, a declared name passes, a name equal to `stored[field.name]` passes, anything else `:inclusion`. Refused for a content type and in a field group ("choices for posts are not built"), and for an outside type in `refuse_outside!` ("a block type from outside may not declare a :theme_choice field: its list would need a key of theme.yml, which the CMS owns").
  - `ContentBlock#carried_settings` (an attribute that is not stored, a Hash): settings carried from another record (a duplicate's original, a discard's copy) whose choice names count as stored. `settings_are_valid` hands `stored: persisted? ? settings_in_database.to_h.merge(carried_settings.to_h) : carried_settings.to_h`. `ContentBlocks::Duplicate` sets `copy.carried_settings = block.settings`.
  - `Admin::Fields::ThemeChoiceField#render?`: true when the list has one entry or more, or the stored value is not in it. Its select: the blank first ("Default" for `section_styles`, "No icon" for `icons`), then the theme's labels in the theme's order; a stored unknown name is the first option, selected, its text `"<name> (not in this theme)"` from the key. `self.display(field, value)`: the label in the interface language, the blank's word, or the name marked "not in this theme". `Admin::Ui::FieldComponent#render?` is its input's.

- [ ] **Step 1: Write the failing tests**
- `theme_choice_field_test.rb` (model, under `with_choices_theme`): "a declared name, blank and the value already stored are valid; another unknown name is refused"; "the options are asked at each validation, so a theme swapped afterwards is seen"; "a theme choice needs of: naming section_styles or icons, and can't be translated"; "a content type and a field group may not declare one".
- `block_type_definition_test.rb`: "an outside type may not declare a :theme_choice field".
- `duplicate_test.rb`: "duplicating a section whose style the theme no longer declares copies the style and saves" (Review Focus 3; register a test block type with a `style` theme choice via `TestTypes` if the Section's field is not in yet — Task 6 adds a case on the Section itself).
- `theme_choice_field_test.rb` (component): "no select without a choice: an empty list and no stored name draw nothing, label included"; "one declared style draws Default and the label, in the theme's order"; "a stored name the theme does not know is first, selected, by its name and marked not in this theme, also when the list is empty"; "a label that looks like markup is text".
- `shared_fields_component_test.rb`: "a theme choice is shown by its label, its blank word, or its name marked not in this theme".
- `held_fields_test.rb`: "a held theme choice's select is disabled with the stored name still selected".
- `theme_pages_test.rb`: extend "nothing of a theme reaches CS Studio…" with a case: under the choices theme an editor with a theme-choice field draws the theme's labels as escaped text, and no file of the theme (template, stylesheet, script, inlined SVG) is in the page.

- [ ] **Step 2: Run them to see them fail** — `PGGSSENCMODE=disable bin/rails test` with the six files above.

- [ ] **Step 3: Implement** as the Interfaces say. `test/lib/field_type_branches_test.rb` stays green: nothing outside the registry names `:theme_choice` but `ThemeChoiceField` by its class.

- [ ] **Step 4: Run them, plus `test/models/content_model test/components/admin test/services/content_blocks test/lib`** — PASS.

- [ ] **Step 5: Commit** — `feat: a field type for a theme's choices, with the stored-name rule`

---

### Task 6: Section styles

**Files:**
- Modify: `app/models/block_types/section.rb` (`t.field :style, :theme_choice, of: :section_styles`; `theme_methods` adds `:style`), `app/components/blocks/section_component.{rb,html.erb}`, `app/components/admin/editor_screen/section_card_component.{rb,html.erb}` (the Style select beside background and width, drawn by `ThemeChoiceField`'s rule; its place follows design answer 1 when given, after Width until then), `config/locales/admin/editor_screen.en.yml` (`style`), `app/values/theme/contract.rb` (`CLASSES = { "content-section--style-<name>" => "on the section, for a style the theme declares" }`), `test/support/contract_ledger.rb` (Section line + `style`; `CLASSES` mirrored), `test/integration/block_samples_test.rb` (`UNFILLED_FIELDS["section"]["style"]` with the reason: "the default theme declares no section style; the choices theme's tests fill and draw one"), `test/components/admin/editor_screen/block_samples_card_test.rb` (a theme-choice field with no choice and no stored name draws no control, by decision 3), `docs/reference/theming.md` (the components table's Section row; a "Classes" table), `test/lib/theming_reference_test.rb` (holds the Classes table to `ContractLedger::CLASSES`), `CHANGELOG.md`
- Fixture: `test/fixtures/themes/choices/assets/stylesheets/theme.css` (rules for `.content-section--style-services`), new `test/fixtures/themes/section_grid/` (`theme.yml` declaring `grid_six`; `components/blocks/section_component.html.erb` drawing `columns.flatten` in its own six-column grid when `style == "grid_six"`, written from the Section's line and the reference alone), `with_section_grid_theme`
- Test: `test/components/blocks/section_component_test.rb`, `test/integration/public_blocks_test.rb`, `test/integration/theme_pages_test.rb`, `test/integration/admin/content_blocks_test.rb`, `test/values/theme/contract_ledger_test.rb`, `test/services/content_blocks/duplicate_test.rb`

**Interfaces:**
- Consumes: `:theme_choice` (Task 5), `Theme#choice` (Task 3).
- Produces: `Blocks::SectionComponent#style → String or nil` (the stored name when `Theme.current.choice(:section_styles, name)`, else nil).

- [ ] **Step 1: Write the failing tests**
- `section_component_test.rb`: "style is the stored name when the theme declares it, and nil when it does not or is blank"; "the default template writes content-section--style-<name> for a style and nothing new without one" (the markup without a style is byte for byte today's).
- `public_blocks_test.rb`: "a section's style is read from the published copy: a save shows nothing until it is published"; "a style in a tinted and in a strong band keeps the band's class beside the style's".
- `theme_pages_test.rb`: "a theme that declares styles and writes CSS styles a section by its class alone"; "a theme that replaces the Section's template draws its own six-column grid from the section's blocks in reading order"; "a stored style the theme does not know draws the section as the default draws it and changes nothing stored".
- `content_blocks_test.rb`: "a section's style is saved and audited as a setting, its select drawn only under the choices theme, and an autosave after the theme dropped the style saves".
- `duplicate_test.rb`: the Review Focus 3 case on a real Section.
- `contract_ledger_test.rb` goes red on the ledger until the Section line is written; write it.

- [ ] **Step 2: Run them to see them fail** — the six files.

- [ ] **Step 3: Implement**; `CHANGELOG.md` Theme contract line: "The Section's template may call `style`; the default template writes `content-section--style-<name>`".

- [ ] **Step 4: Run them, plus `test/values/theme test/lib/theming_reference_test.rb test/integration/block_samples_test.rb test/components/admin/editor_screen test/values/theme/scaffold_test.rb test/integration/public_canary_test.rb`** — PASS. Then `bin/rails tailwindcss:build` (no tests running) and `PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test test/system/admin/sections_test.rb`.

- [ ] **Step 5: Commit** — `feat: section styles a theme declares and an editor picks`

---

### Task 7: Page templates: storage, the migration, publishing and the public page

**Files:**
- Create: `db/migrate/20261031120000_replace_page_type_with_page_settings.rb`, `app/views/pages/templates/_standard.html.erb`, `app/views/pages/templates/_landing.html.erb` (and, if they share markup, a partial of the default theme's own under `app/views/pages/templates/shared/` that is not on the contract — name it so `Theme::Check` never admits it in a theme: see Task 9)
- Modify: `app/models/page.rb` (enum and `landing?` gone; `settings` with `template`/`template=`; validation; comments state the invariants), `app/models/publishing.rb` (`CONTENT["Page"]`: `page_type` out, `settings` in), `app/services/pages/save.rb` (`ATTRIBUTES`: `page_type` → `template`), `app/services/publishing/discard_changes.rb` (writes `template` back, carrying the copy's name), `config/locales/admin/editor_screen.en.yml` (`field_names.settings: "Template"`, `page_type` key gone), `app/helpers/theme_helper.rb` (`page_template`), `app/values/theme.rb` (`page_template`), `app/values/theme/contract.rb` (`HELPERS` + `page_template`), `app/views/pages/show.html.erb`, `app/models/public_site/urls.rb` (`prefetch`), `app/models/public_site/paths.rb` (the comment naming `page_type`), `db/seeds.rb`, `db/schema.rb` (by the migration), `docs/reference/theming.md` (the helpers table's row), every test and preview that names `page_type` or `landing?` (the list from `grep -rln "page_type\|landing?" test`: write `template: "landing"` where they wrote `page_type: :landing`)
- Test: `test/models/publishing/page_settings_migration_test.rb` (new), `test/models/page_test.rb`, `test/models/publishing_test.rb`, `test/models/publishing/first_copies_migration_test.rb` (narrowed), `test/services/pages/save_test.rb`, `test/services/publishing/discard_changes_test.rb`, `test/models/publishing/changes_test.rb`, `test/integration/public_drafts_test.rb`, `test/helpers/theme_helper_test.rb`, `test/integration/public_subpages_test.rb`, `test/values/theme/scaffold_test.rb`

**Interfaces:**
- Consumes: `Theme#choices(:page_templates)`, `Theme::Choice#fields` (Task 3); `ContentModel.theme_choices` (Task 5).
- Produces:
  - `pages.settings` jsonb, default `{}`, not null; `Page#template → String or nil` (`settings["template"].presence`), `Page#template=(name)` (blank removes the key); `Page#carried_settings` (as `ContentBlock`'s, Task 5). Validation: `settings` keys ⊆ `%w[template]`; `template` blank, declared (`ContentModel.theme_choices.call(:page_templates)`), equal to the stored one (`settings_in_database`), or equal to `carried_settings["template"]`; otherwise `errors.add(:template, :inclusion)`. A change of `settings` moves `settings_changed_at` (it is not in `SETTINGS_BASE_IGNORES`; assert, don't add code).
  - `Pages::Save` attribute `template:` (String or nil).
  - `Theme#page_template(stored) → String` (stored when declared, else the first template's name; never nil); `ThemeHelper#page_template → String` (`Theme.current.page_template(@page&.template)`).
  - `pages/show.html.erb` renders `render "pages/templates/#{page_template}", page: @page, post: @post, list_block: @post_list_block`; the two templates read the locals and contract helpers only (`translated`, `block_outline`, `render_block`, `theme_site`, `published_views`, `page_url_path`, `site_string`), and `render_block`'s detail swap stays in the helper.
  - `PublicSite::Urls#prefetch(records, locale = I18n.locale) → self`: one `PublicSite::Paths.current_paths` read filling the memo for those records (nil for none), so the subpages list costs one statement for its addresses.

- [ ] **Step 1: Write the failing tests**
- `page_settings_migration_test.rb` (run `up` on rows built with `update_columns` before the column goes, as `first_copies_migration_test.rb` does; or run the migration's own `rewrite` methods on a schema-loaded database with the old column re-added in the test's setup): "landing pages become the Landing template, standard pages keep empty settings, and the column is gone"; "every copy of a page is rewritten: current, pending and superseded, and a copy with no page_type is left as it is" (Review Focus 5); "a copy after the migration equals Snapshot.of of the same rows"; "the migration moves no content version and writes no audit event".
- `first_copies_migration_test.rb`: narrow `assert_same_copy` for pages to leave out `page_type` and `settings` (the comment at its top says this is how), keeping every other assertion.
- `page_test.rb`: "a page's template is a name the theme declares, blank, or the one already stored"; "settings holds template and nothing else"; "a change of template moves settings_changed_at".
- `publishing_test.rb` stays the guard ("every column of pages is in exactly one of the copy, the rows and never stored") with `settings` in the copy.
- `save_test.rb`: "a template is saved, audited as a change of settings and marks a live page as changed".
- `discard_changes_test.rb`: "discard writes the template back from the copy"; "discard writes back a template the theme no longer declares" (Review Focus 3).
- `changes_test.rb`: "a changed template is named in the overview as Template".
- `public_drafts_test.rb`: "a live page switched to Landing shows its hero only after Publish changes".
- `theme_helper_test.rb`: "page_template is the stored name when declared, the first template otherwise, never nil".
- `public_subpages_test.rb`: "the subpages' addresses are read in one statement at 3 and at 30 subpages" (`capture_sql`).
- `scaffold_test.rb` ("a site under the folder it writes is drawn byte for byte…") and the public page tests hold Standard and Landing byte for byte as before: run, don't edit their expectations.

- [ ] **Step 2: Run them to see them fail** — the files above.

- [ ] **Step 3: Implement.** The migration is frozen logic in its own file calling no application class: add the column; `UPDATE pages SET settings = '{"template":"landing"}' WHERE page_type = 1`; rewrite `published_versions` rows with `record_type = 'Page'` whose `snapshot->'fields' ? 'page_type'`: drop `fields.page_type`, set `fields.settings` to `{"template":"landing"}` when it was `"landing"` (or `1`), else `{}`; remove `page_type`. `down` raises `ActiveRecord::IrreversibleMigration`. Each SQL string carries `# sql: <reason>` (`test/lib/sql_strings_test.rb` reads `app` and `lib`; keep the habit). If `test/lib/built_in_data_test.rb` flags it, it inserts nothing: account for it as `derived:` with that reason. `CHANGELOG.md`: Theme contract "Added the helper `page_template`"; Removed "`Page#page_type` and `Page#landing?`: a template writes `page_template == \"landing\"`"; Migrations needing action "None beyond `db:migrate`; it rewrites every page's published copies".

- [ ] **Step 4: Run them, plus `test/models test/services test/integration test/helpers test/lib test/values test/components/previews` (the previews compile)** — PASS.

- [ ] **Step 5: Commit** — `feat: a page's template replaces its page type, stored in page settings`

---

### Task 8: Page templates in CS Studio

**Files:**
- Modify: `app/controllers/admin/pages_controller.rb` (`ATTRIBUTE_FIELDS`, the error map, `new_page_params` permit `template`), `app/components/admin/editor_screen/page_settings_form_component.{rb,html.erb}` (the Template select; the hero fields when the chosen template's `fields` include `hero`; the subtitle always), `app/components/admin/editor_screen/new_page_form_component.{rb,html.erb}` and `app/views/admin/pages/new.html.erb`, `config/locales/admin/editor_screen.en.yml` (`template`, `default`-free: a template has no blank)
- Test: `test/components/admin/editor_screen/page_settings_form_component_test.rb`, `new_page_dialog_component_test.rb`, `test/integration/admin/page_editor_test.rb`, `test/integration/admin/new_record_dialogs_test.rb`, `test/system/admin/new_record_test.rb`, `test/system/admin/editor_fields_test.rb`

**Interfaces:**
- Consumes: `Page#template`, `Theme#choices(:page_templates)`, `Theme#page_template` (Task 7).
- Produces: the form field `page[template]`; the New page dialog posts `page[template]` only when it offers a choice, and a new page stores `{}` otherwise.

- [ ] **Step 1: Write the failing tests**
- `page_settings_form_component_test.rb`: "under the default theme the Template select offers Standard and Landing"; "a theme with one template draws no select"; "a stored template the theme does not know is first, selected and marked not in this theme"; "the hero fields are drawn only when the chosen template lists hero, and the subtitle always"; "on a translation tab the template is a read-only line with its label"; "held by someone else the select is disabled".
- `new_page_dialog_component_test.rb`: "the dialog asks for the template under the select's rule".
- `page_editor_test.rb`: "a template is saved by the settings autosave and refused when it is unknown and not the stored one"; "switching to Landing draws the hero fields in the answer".
- `new_record_dialogs_test.rb`: "a new page stores the template chosen, and {} when the dialog offered none".
- `new_record_test.rb` / `editor_fields_test.rb`: the browser steps that chose "Landing" under "Page type" choose it under "Template".

- [ ] **Step 2: Run them to see them fail.**
- [ ] **Step 3: Implement.** The look of the select's place and of the hero fields when hidden follows design answer 4 when given; until then the select stands where "Page type" stood and the hero fields are not drawn.
- [ ] **Step 4: Run them, plus `test/components/admin test/integration/admin test/lib/admin_i18n_test.rb test/lib/source_layout_test.rb`**; then the two system files with `PARALLEL_WORKERS=6`.
- [ ] **Step 5: Commit** — `feat: the page settings and the New page dialog ask for the template`

---

### Task 9: Page templates for a theme: the check, the deep check, the scaffold and a fixture

**Files:**
- Modify: `app/values/theme/contract.rb` (`PAGE_TEMPLATES = "pages/templates/"`, `PAGE_TEMPLATE_LOCALS = %w[page post list_block]`), `app/values/theme/check.rb` (`misplaced` admits `views/pages/templates/_<name>.html.erb`; a declarations problem both ways: a declared template with a name the default lacks and no file, and a file no entry names; the deep check refuses `landing?` and `page_type` in a template's code), `app/values/theme/scaffold.rb` (copies the default's page templates; writes a `theme.yml` of comments only that shows the three lists with the default's entries), `test/support/contract_ledger.rb` (`PAGE_TEMPLATE_LOCALS`), `test/values/theme/contract_ledger_test.rb`, `docs/reference/theming.md` (the "Page templates" table of the three locals; the templates table names `pages/templates/_<name>.html.erb`), `test/lib/theming_reference_test.rb` (holds that table to the ledger), `CHANGELOG.md`
- Fixture: `test/fixtures/themes/choices/theme.yml` gains `project` (`fields: [hero]`), `test/fixtures/themes/choices/views/pages/templates/_project.html.erb` written from the locals table and the helpers table alone (draws `page`'s title in a `div.project-page`, its blocks, and `post`'s detail through `render_block` when `post` is set)
- Test: `test/values/theme/check_test.rb`, `test/values/theme/scaffold_test.rb`, `test/integration/theme_pages_test.rb`, `test/tasks/theme_tasks_test.rb`

**Interfaces:**
- Consumes: Task 7's templates and locals.
- Produces: `Theme::Contract::PAGE_TEMPLATES`, `Theme::Contract::PAGE_TEMPLATE_LOCALS`, `ContractLedger::PAGE_TEMPLATE_LOCALS`.

- [ ] **Step 1: Write the failing tests**
- `check_test.rb`: "a page template file is admitted only for a declared template, and a declared template the default lacks must bring its file" (both sentences start with the file and say what to do); "the deep check refuses landing? and page_type in a theme's template and says what to write instead" (the sentence names `page_template == "landing"`); "a word landing? in a string or a comment is not refused".
- `scaffold_test.rb`: "the folder it writes holds the two page templates and a theme.yml of comments only, has no problem checked deeply, and draws byte for byte" (extend the existing byte-for-byte test's folder, don't loosen it).
- `theme_pages_test.rb`: "a theme's own template, written from the locals' table alone, draws a page and a post's detail under it"; "a page whose stored template the theme does not know is drawn by the first template".
- `contract_ledger_test.rb`: "the page templates' locals are the ledger's".

- [ ] **Step 2: Run them to see them fail.**
- [ ] **Step 3: Implement**; `CHANGELOG.md` Theme contract: "Added `views/pages/templates/_<name>.html.erb` and its locals `page`, `post`, `list_block`".
- [ ] **Step 4: Run them, plus `test/values/theme test/lib/theming_reference_test.rb test/tasks test/lib/production_boot_test.rb`** — PASS.
- [ ] **Step 5: Commit** — `feat: a theme declares page templates and brings their files`

---

### Task 10: The Card block (without its tokens and the default icon set)

**Files:**
- Generate: `bin/rails generate block_type card`
- Modify: `app/models/block_types/card.rb`, `app/components/blocks/card_component.{rb,html.erb}`, `app/models/content_model/block_type_definition.rb` (`ICONS` gets the type's CS Studio icon, **input: design answer 5**; if not given when the task starts, ask the controller), `app/views/admin/shared/_icon.html.erb` (its branch), `config/locales/admin/editor_screen.en.yml` (`tile_summary.types.card`: `empty`), `test/support/contract_ledger.rb` (the line `"blocks/card_component" => %w[block page title text link icon icon_name]`, after the Table's), `docs/reference/theming.md` (the components table's row), `test/integration/block_samples_test.rb` (`UNFILLED_FIELDS["card"]["icon"]`: "the default theme declares no icon until design question B is answered; the choices theme's tests draw one", removed by Task 12), `CHANGELOG.md`
- Test: `test/models/block_types/card_test.rb`, `test/components/blocks/card_component_test.rb`, `test/components/admin/editor_screen/tile_summary_component_test.rb`, `test/components/admin/editor_screen/block_card_component_test.rb`, `test/integration/admin/content_blocks_test.rb`, `test/integration/public_blocks_test.rb`, `test/services/translation_state_parity_test.rb` (only if the derived case does not cover it)

**Interfaces:**
- Consumes: `:theme_choice` over `icons` (Task 5), `:link` and `FieldTypes.link?` (Task 2), `Theme#icon_svg`, `Theme#choice` (Task 4).
- Produces: `BlockTypes::Card` with fields `icon` (`:theme_choice, of: :icons`), `title` (`:string, translated: true`), `text` (`:text, translated: true`), `link` (`:link`), in that order (design answer 5 may reorder before the build); `theme_methods :block, :page, :title, :text, :link, :icon, :icon_name`; `summary` the icon's label, " · " and the title (or `[:hint, "empty"]`); `stylesheet "card.css"`; no `tokens` yet (Task 11). `Blocks::CardComponent`: `title`/`text` read in the language shown along the site's fallback; `render?` true with a title or a text; `link` the stored value when `FieldTypes.link?`, else nil; `icon` `Theme.current.icon_svg(icon_name)`; `icon_name` the stored name when declared, else nil. The default template's markup (whole card or title as the link, heading level) follows design answer 6; until then `div.content-block.content-block--card` with the icon, an `h3` title, a `p` text, and the title wrapped in the link.

- [ ] **Step 1: Write the failing tests**
- `card_test.rb`: "a card is an icon, a title, a text and a link, none required, the title and text translated".
- `card_component_test.rb` (under `with_choices_theme` for the icon): "a card is drawn with a title alone and with a text alone, and not with neither, an icon alone included"; "the icon is inlined with aria-hidden and focusable false, and there is no icon element for an unknown or blank icon"; "each accepted link is drawn as the link, and a stored value no longer accepted is drawn as no link"; "a title and a text that look like markup are text"; "a visitor of another language reads the title and text with the site's fallback".
- `tile_summary_component_test.rb`: "a card is its icon's label and its title; an empty one says Empty".
- `block_card_component_test.rb`: "a card's card draws Icon only where the theme declares icons, then Title, Text and Link". And "the chosen icon is shown in CS Studio as an <img> of its served address, never inlined" (its look follows design answer 3; a plain image beside the select until then); extend `theme_pages_test.rb`'s "nothing of a theme reaches CS Studio…" case with it.
- `content_blocks_test.rb`: "a Card added from the picker saves its four values, a bad link is refused with the field's error and nothing is written, and its save is refused when stale and under another tab's hold".
- `public_blocks_test.rb`: "a card on a live page is read from its published copy".
- The generator's own tests and `test/integration/block_samples_test.rb`, `public_canary_test.rb`, `scaffold_test.rb` from the sample (title and text in en, de, es; the link `/about`; icon excused until Task 12).

- [ ] **Step 2: Run them to see them fail.**
- [ ] **Step 3: Implement** by the recipe's steps 2–8. `CHANGELOG.md` Theme contract: "Added the Card block's component line: `block page title text link icon icon_name`".
- [ ] **Step 4: Run them, plus `test/values/theme test/lib test/integration/block_samples_test.rb test/integration/public_canary_test.rb test/values/theme/scaffold_test.rb test/components/admin/editor_screen`** — PASS. Then `PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test test/system/admin/card_block_test.rb` (new: typed, autosaved, reloaded; a second person's card read-only with the icon select disabled).
- [ ] **Step 5: Commit** — `feat: the Card block`

---

### Task 11: The Card's tokens — BLOCKED until design questions A and B are answered

**Input (marked, from the Design System's answer to question A):** the `--th-card-*` token names; for each, themed or fixed, its definition from base tokens in light and dark; the strong band's re-values; the contrast pairs with their grounds (page, tinted band, strong band) and ratios. Do not start without it; do not invent a name.

**Files:**
- Modify: `app/models/block_types/card.rb` (`t.tokens themed: [<names from A>]`), `app/assets/tailwind/themes/default/tokens.css` (both schemes), `sections.css` (the strong band's re-values, the tinted band's if A says so), `card.css` (rules on the tokens only), `test/support/contract_ledger.rb` (the names after the Table's tokens, in A's order), `docs/reference/theming.md` (the tokens table's rows), `CHANGELOG.md`
- Test: `test/integration/design_tokens_test.rb` (A's pairs, in both schemes; "the card's tokens are defined from the theme's base tokens in both schemes, never a literal"), `test/values/theme/contract_test.rb`, `test/values/theme/contract_ledger_test.rb`, `test/lib/theming_reference_test.rb`, `test/system/card_block_test.rb` (new: the card in both schemes on the page, a tinted and a strong band)

- [ ] **Step 1:** Write the contrast and definition tests from A's list; run them (FAIL).
- [ ] **Step 2:** Implement; ledger and table lines with the release note ("Added the Card's tokens: …").
- [ ] **Step 3:** Run `test/integration/design_tokens_test.rb test/values/theme test/lib/theming_reference_test.rb` (PASS); `bin/rails tailwindcss:build`, then `PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test test/system/card_block_test.rb`.
- [ ] **Step 4: Commit** — `feat: the Card's tokens`

---

### Task 12: The default theme's icon set — BLOCKED until design question B is answered

**Input (marked, from the Design System's answer to question B):** the icon names, each label, the files' folder among the CMS's images, the licence line, and the drawing rules (view box, stroke, `currentColor`, no ids). Do not start without it.

**Files:**
- Create: one SVG per name under `app/assets/images/<B's folder>/`, the licence line beside them (as B says)
- Modify: `config/theme/default.yml` (`icons:` with B's entries, `file:` each), `app/models/block_types/card.rb` (the sample's icon, one of B's names), `test/integration/block_samples_test.rb` (remove the Card's `UNFILLED_FIELDS` entry), `test/support/contract_ledger.rb` (`DEFAULT_ICONS = %w[<B's names>]`), `test/values/theme/contract_ledger_test.rb` ("the default theme's icon names are the ledger's"), `docs/reference/theming.md` (the "Default icons" table), `test/lib/theming_reference_test.rb` (holds it), `CHANGELOG.md` ("Added the default theme's icon names: …")
- Test: `test/values/theme/declarations_test.rb` ("the default theme's icons pass the fence and are drawn by their names"), `test/values/theme/check_test.rb` (no default icon is shadowed by a theme's file of the same path), `test/values/theme/scaffold_test.rb`, `test/integration/public_canary_test.rb`

- [ ] **Step 1:** Write the tests; run (FAIL).
- [ ] **Step 2:** Implement.
- [ ] **Step 3:** Run `test/values/theme test/lib test/integration/block_samples_test.rb test/integration/public_canary_test.rb` — PASS.
- [ ] **Step 4: Commit** — `feat: the default theme's icons for the Card`

---

### Task 13: A theme's own Card, written from the reference — BLOCKED until design questions A and B are answered (after Tasks 11 and 12)

**Files:**
- Modify: `docs/reference/theming.md` (a "The Card block" section: its seven names and what each answers, its tokens, that the icon is inlined decoration and how a theme draws `currentColor`, the drawing rules from B)
- Create fixture: `test/fixtures/themes/card/` (`components/blocks/card_component.html.erb` and `assets/stylesheets/theme.css` declaring the Card's tokens again for both schemes, written from that section alone), `with_card_theme` in `test/support/theme_test_helper.rb`
- Test: `test/integration/theme_pages_test.rb` ("a theme replaces the Card's template from the contract's names alone, and a theme that does not is drawn the default one"), `test/lib/theming_reference_test.rb` ("the Card block's table names exactly the methods of its entry")

- [ ] **Step 1:** Write the tests; run (FAIL). **Step 2:** Write the section, then the fixture from it alone. **Step 3:** Run them and `test/values/theme` — PASS. **Step 4: Commit** — `test: a theme's own Card from the reference alone`

---

### Task 14: Documents (after Tasks 11–13)

**Files:**
- Create: `docs/reference/theme-choices.md` (the mechanism: the format and its rules, the stored-name rule and carried settings, the select's rule, section styles, page templates and the migration, the Card's icon, the `FieldType` seam, the guards by test name)
- Modify: `docs/reference/theming.md` (decision 5's wording "a theme brings no settings and no block types; it may offer named choices, which degrade to the default"; `theme.yml` in the folder's picture and the plain depth's list; the deep check's `landing?`; a pointer to `theme-choices.md`; "What is not built" without "A template per page type" and corrected on a published CMS image, and "Deployment"'s "No CMS image is published yet" corrected), `docs/reference/content-blocks-and-types.md` (a "The Card block" section; step 3 rewritten for the `FieldType` registry; the list at the top), `docs/reference/publishing.md` (`settings` in the copy, the migration's rewrite), `CLAUDE.md` (the reference index line for `theme-choices.md` and the new files; one-line rules, each with its guard: a field type is one registry entry and nothing branches on its name (`test/lib/field_type_branches_test.rb`); a stored choice the theme does not know is drawn as the default and changes nothing stored, and a carried name saves; CS Studio shows a theme's labels as text and its icons as `<img>` only ("nothing of a theme reaches CS Studio…"); the page's template is `pages.settings`, in the copy), `CHANGELOG.md` (complete and ordered under the four headings), `docs/roadmap.md` (#104, #105, #106 shipped; page types out of "Next", item 2), the spec's "As built" (rulings below, and where the build left the spec)
- Test: `PGGSSENCMODE=disable bin/rails test test/lib` (the guards read `CLAUDE.md` and `docs/reference`)

- [ ] **Step 1:** Write; run `test/lib`; commit — `docs: theme choices`.
- [ ] **Step 2:** Give the controller the PR's "Documentation" list (the guide, `contentspiel-docs`): `editors/pages/page-settings-and-search-appearance.md`, `editors/pages/create-and-organise-pages.md`, `editors/pages/arrange-blocks-in-sections.md`, `editors/pages/build-a-page-with-blocks.md`, `integrators/theming/what-a-theme-is.md`, `integrators/theming/build-a-theme.md`, `integrators/theming/the-theme-contract.md`, `integrators/theming/rendering-blocks-and-pages.md`, `integrators/theming/what-a-theme-cannot-do.md`, `integrators/how-it-works/blocks-content-types-and-registries.md`, with the release notes from `CHANGELOG.md`.

The whole-branch check (`bin/rubocop`, `bin/brakeman`, `bin/bundler-audit`, `bin/importmap audit`, `bin/rails zeitwerk:check`, the unit suite, the browser suite, `bin/theme-build-check` alone) is the controller's, after the final review.

---

## Rulings on gaps in the spec (for "As built")

1. **The `FieldType` value names no component.** Dependency direction keeps `ContentModel` from naming CS Studio, so a type's input and its read-only display are its `Admin::Fields::<Type>Field` (found by name, as today) and that class's `self.display`; the guard that every registered type answers every question is split into a model test and a component test.
2. **Carried names.** The spec's "a save keeps an unknown name it did not change" did not cover a duplicate or a discard, which write a name onto a record that did not store it; `carried_settings` (not stored) makes the source's names count as stored there.
3. **`:theme_choice` is refused for content types and field groups**, beside outside types: choices for posts are a non-goal.
4. **An entry of the theme naming a default entry** keeps the theme's own label and fields; only the file falls back.
5. **`theme:new` writes a `theme.yml` of comments only** (the spec's "one more file") and copies the two page templates.
6. **The Card's component line is written in Task 10**, before design questions A and B, since its seven names are the spec's; only the tokens and the default icon names wait. Until Task 12 the Card's sample leaves `icon` unfilled, named in `UNFILLED_FIELDS` with its reason.
