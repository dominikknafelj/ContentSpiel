# Source layout cleanup: one shape for every screen

Status: design, 2026-10-10. A refactor with no change of behaviour. It comes before presence (collaboration step 2), so that presence's slots and scripts land in the tidy layout.

## 1. Why

A screen in CS Studio is built from components, browser scripts and strings. Only the components got a folder per screen, and only partly:

- `app/components/admin/` has 15 screen folders and 36 components loose beside them. Most of the loose ones are shared building blocks (button, dialog, menu); a few belong to one screen and were never moved.
- `app/javascript/controllers/admin/` is one flat folder of 55 controllers. Notes alone is ten of them, media six. Beside it six topic folders (`autosave/`, `rich_text/`, `mind_graph/`, `media/`, `search/`, `i18n/`) hold plain modules, so a topic's code is in two places with no stated rule.
- `config/locales/admin/components.en.yml` holds every converted shared component in one file, while notes, tags and the mind graph each have their own.

The owner's words (2026-10-10): "the components are very unorganized in general", "the js is also very unorganized", "do everything".

## 2. What is in and what is not

In: where files live, the names that follow from where they live (a component's class, a controller's identifier, a translation scope), the tests, docs and guards that name them.

Not in:
- Any change a person could see or a test of behaviour could tell.
- Splitting the oversized files (`blocks_controller.js`, `translate_controller.js`, `rich_text/markdown.rb`, `content_blocks_controller.rb` and the others the roadmap lists). `notes_live_controller.js` is split by the presence spec.
- The flat `app/controllers/admin/` folder (Rails convention, shaped by the URLs) and the helpers.
- `app/components/admin/fields/` and `columns/`: they are registries of one kind of part (a field per content-model field type, a column per list), each cohesive.

## 3. Components

**Rule.** A component used by two or more screens is a shared building block and lives in `app/components/admin/ui/` as `Admin::Ui::<Name>Component`. A component used by one screen lives in that screen's folder. Nothing but `admin_component.rb` (the base class) is loose in `app/components/admin/`.

**Shared, to `admin/ui/`** (each is used by two or more screens today): button, channel_chip, checkbox, chip_input, confirm_dialog, content_type_dot, dialog, empty_state, error_summary, field, file_drop, language_tabs, menu, pagination, password_field, save_bar, save_status, status_chip, theme_switch, time_ago, toast, toast_region, translation_chip, user_name, word_diff.

**To a screen's folder:**

| Component | To | Why |
|---|---|---|
| block_card, block_picker | `editor_screen/` | The editor's parts; the pages views and the media library only render the editor's cards |
| page_settings_form, post_form, related_posts | `editor_screen/` | The two editors' forms |
| tree, tree_node | `pages_screen/` (new) | The page tree; the shell's sidebar renders it |
| permission_matrix | `groups_screen/` | Groups only |
| mind_graph_legend | `mind_graph_screen/` (new) | Mind graph only |
| system_check_row | `setup_screen/` (new) or `ui/` | Decide in the plan from its users (setup and system status) |
| prefix_input | `columns/` or `ui/` | Decide in the plan from its users |

The plan's first task re-counts every component's users from the code and corrects this table where the count disagrees; the rule decides, not the table.

**Names.** `Admin::Ui` is not a domain name, so the shadow guard (`test/lib/admin_namespace_shadow_test.rb`) is unaffected; the plan confirms it by running the guard. A moved component's class changes (`Admin::ButtonComponent` → `Admin::Ui::ButtonComponent`), and every reference changes with it (about a thousand mentions, by script, then by the suites).

## 4. Browser scripts

**Rule.** A topic has one name and up to two folders with that name:
- `app/javascript/controllers/admin/<topic>/` for its Stimulus controllers;
- `app/javascript/<topic>/` for its plain modules.

Nothing is loose in `controllers/admin/`. The controllers stay under `controllers/admin/` because two rules hang on that path: the registrar finds controllers by the `controllers/` prefix and splits public from admin by `controllers/admin/` (`app/javascript/controllers/index.js`, `admin.js`), and the import map gives everything under it `preload: "admin"`, which keeps CS Studio's code off public pages (`test/integration/public_javascript_test.rb`).

(An earlier sketch in the conversation merged controllers and modules into one folder per topic at the top of `app/javascript/`. That would have meant rewriting both of those rules; the two-folder rule gets the same findability without touching them.)

**Topics** (a controller's file loses the topic from its own name where it repeats it):

| Topic | Controllers |
|---|---|
| `shared` | auto_submit, branch_picker, bulk_select, busy, char_count, chip_input, clipboard, command_palette, dialog, drawer, file_drop_guard, fragment_links, menu, new_record, override_field, password_answer, password_disclosure, quick_create, repeat_rows, sortable_rows, toast |
| `saving` | autosave, save_bar, queue_hold, pending_lock (modules: today's `autosave/`, renamed `saving/`) |
| `editor` | blocks, section, tree, slug_preview |
| `rich_text` | rich_text (as `editor`), rich_text_dialog (as `dialog`) (modules: `rich_text/`) |
| `translation` | translate |
| `media` | drop, field, panel, picker, select, upload (modules: `media/`) |
| `notes` | notes (as `drawer`), notes_live (as `live`), notes_alert (as `alert`), notes_permission (as `permission`), note_composer, note_gif, note_reactions, note_refusal, note_unsaved (as `composer`, `gif`, `reactions`, `refusal`, `unsaved`) |
| `mind_graph` | mind_graph (as `graph`) (modules: `mind_graph/`) |
| `groups` | groups, group_hint, permission_matrix |
| `settings` | settings_tabs, ai_settings |
| `tokens` | token_reveal |
| `tags` | tag_dialogs |

The plan's first script task re-reads each controller's users and corrects the table by the same rule as for components (one screen: that topic; several: `shared`).

**Identifiers.** A controller's identifier follows its path, so `admin--notes-live` becomes `admin--notes--live`, `admin--dialog` becomes `admin--shared--dialog`. Every `data-controller`, `data-action`, target, value, class and outlet attribute, every event name a controller dispatches under its identifier (`admin--notes-live:delivery`), every selector in a script, a stylesheet or a test, and every mention in a comment or a doc changes with it. This is the delicate part of the whole cleanup: it is done one topic at a time, by a script that rewrites exact identifiers, with that topic's system tests run after each.

**Loading.** `pin_all_from "app/javascript/controllers/admin"` already covers nested folders; the plan verifies that with the import map's output before anything moves. The mind graph's modules stay `preload: false`, and its controller keeps loading them by dynamic import.

**Before moving `saving/` and anything the write queue names:** re-read the headers of `autosave/queue.js` and `save_bar_controller.js` (the Turbo pin rule in `CLAUDE.md`), since they name controllers and events by identifier.

## 5. Strings

A component's translation scope follows its class (`Admin::AdminComponent.translation_scope`), so a moved component's keys move too. The one file `components.en.yml` is split to follow the folders: `config/locales/admin/ui.en.yml` for the shared building blocks and one file per screen folder that has strings (`editor_screen.en.yml`, `groups_screen.en.yml` and so on), beside the existing `notes`, `tags`, `mind_graph` and `layout` files. `test/lib/admin_i18n_test.rb`'s `CONVERTED` list is updated to the new paths. No string changes.

## 6. Two small oddities in the models

`app/models/admin/field_params.rb` (a module that reshapes request parameters, under `Admin` in the models folder) and `app/models/page/tree_ranking.rb` (the only file in its folder). The plan looks at each: `Admin::FieldParams` probably belongs with the controller concerns; `Page::TreeRanking` probably stays, since it is the page model's own concern. Moved only if the move is clean.

## 7. Tests, docs, guards

- Tests mirror the app: `test/components/admin/`, the system and integration tests that name an identifier, and the component previews move or are rewritten with what they test. No assertion changes except names.
- `CLAUDE.md` and `docs/reference/*.md` name many of these paths, classes and identifiers; they are updated in the same commits. `CLAUDE.md`'s convention on screen namespaces gains `Admin::Ui::` and the script rule.
- One new guard, `test/lib/source_layout_test.rb`: nothing loose in `app/components/admin/` but the base class; nothing loose in `app/javascript/controllers/admin/`; every folder under `controllers/admin/` whose topic has plain modules has them in `app/javascript/<same name>/`; no `data-controller` value in `app/` names an identifier that no controller file has.

## 8. How it is proven

Behaviour is unchanged, so the proof is the existing suites, unchanged in what they assert: `bin/rubocop`, `bin/brakeman`, `bin/rails zeitwerk:check`, the unit suite, and the system suite after `bin/rails tailwindcss:build`. Tailwind reads class names from the sources it is pointed at (`test/lib/tailwind_sources_test.rb`): moved script folders are checked against its `@source` lines.

Order of work: components (with their strings), then scripts topic by topic, then the model oddities, then the guard and the docs. One PR.

## 9. Risks

- A missed identifier does not fail loudly: a controller that never connects is silence, not an error. The guard in §7 (no `data-controller` without a file) and the system suite are the nets; the per-topic order keeps a miss small and findable.
- Open pull requests and the `presence` branch (one roadmap commit) rebase over this; presence's design is written after it merges.
