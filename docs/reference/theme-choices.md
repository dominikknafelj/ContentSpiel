# Theme choices: section styles, page templates and the Card's icon

> Describes: `app/values/theme/declarations.rb`, `app/values/theme/choice.rb`, `app/values/theme/icon_file.rb`, `config/theme/default.yml`, `Theme#choices`, `#choice`, `#page_template`, `#icon_svg` and `#icon_asset` (`app/values/theme.rb`), the `theme.yml` and page-template parts of `app/values/theme/check.rb` and `app/values/theme/scaffold.rb`, `app/models/content_model.rb` (`ContentModel.theme_choices`), `app/models/content_model/field_type.rb`, `app/models/content_model/field_types.rb`, `app/components/admin/fields/` (`theme_choice_field`, `link_field`, every type's `display`), `app/models/page.rb` (`settings`, `template`, `carried_settings`), `app/models/content_block.rb` (`carried_settings`, `stored_settings`), `app/models/block_types/section.rb` (`style`, `anchor`), `app/models/block_types/card.rb`, `app/components/blocks/section_component.rb`, `app/components/blocks/card_component.rb`, `app/views/pages/show.html.erb`, `app/views/pages/templates/`, `app/helpers/theme_helper.rb` (`page_template`, `page_anchors`), the template parts of `Admin::EditorScreen::PageSettingsFormComponent` and `NewPageFormComponent`, `app/javascript/controllers/admin/editor/template_fields_controller.js`, `db/migrate/20261101100000_replace_page_type_with_page_settings.rb`.

Spec: `docs/superpowers/specs/2026-10-31-theme-choices-design.md` (its last section, "As built", lists where the build left it). The theme's side of this, what an author writes in `theme.yml`, the contract's tables and the icon fence, is `docs/reference/theming.md` ("`theme.yml`", "Page templates", "Classes", "The Card block", "Checking a folder"); this file is the mechanism. Tests are cited by file.

## What it is

A theme could tell two sections, two pages or two cards apart only by their place: the third section of the homepage is the contact band, a page under "Work" a project page, the second card the second icon. A reorder, a move in the tree or a new card broke the design without a word. Now **the theme declares named choices in `theme.yml`, an editor picks one, and the NAME is stored on the section, the page or the card**, so the look moves with the content.

One mechanism, three uses:

| Choice | The theme's list | Stored in | The default | Drawn by |
|---|---|---|---|---|
| A section's Style | `section_styles` | the block's `settings["style"]` | no style | the Section's `style` (and the default template's class `content-section--style-<name>`) |
| A page's Template | `page_templates` | the page's `settings["template"]` | the theme's first template | `pages/show` rendering `pages/templates/_<page_template>` |
| A card's Icon | `icons` | the block's `settings["icon"]` | no icon | the Card's `icon` (the file inlined) and `icon_name` |

## The lists: `Theme::Declarations`

`Theme::Declarations.read(source)` answers the lists and the problems; `Theme::Check` says the problems at the plain depth, so the boot and every development reload refuse a bad `theme.yml` as they refuse a misplaced file (and a reload keeps the refusal as every reload does). `Declarations.of(folder)` is read once, by `Theme.load`, and kept on the `Theme`; a refused theme and a theme without a folder answer `Declarations.default`. **Nothing in the file may raise**: a value of the wrong kind (`name: yes` is `true` to YAML, `label:` with nothing is nil, an entry can be a bare string) is one problem naming the list, the entry's place and the key, and the entry is left out. YAML is loaded with `safe_load` and no aliases, after the parsed tree has been walked without recursion for a tag, an anchor, an alias, a key written twice and nesting past 16 levels, because a `!!binary` value, a duplicate key (YAML keeps the last) and a deep nesting (a `SystemStackError` out of a reload) each passed the plain loader. The file is at most 64 KB and UTF-8.

**The default theme's lists are a data file too**, `config/theme/default.yml`, read by the same reader: the page templates `standard` and `landing` (`fields: [hero]`) and the twelve icons; no section styles. A problem in it is the CMS's own fault and stops the boot. Its icons are `from: :default`, so a theme that inherits the list, or names one of them without a `file`, draws the CMS's file (`Theme#icon_path`).

Each entry is a `Theme::Choice` (`list`, `name`, `labels`, `fields`, `file`, `from`); `label_for(locale)` is CS Studio's interface language, then `en`, then the first given. `Theme#choices(list)` answers a list, `#choice(list, name)` one entry.

**An entry naming a default entry** keeps its own label and fields; only the file falls back (a theme may rename Landing "Campaign" and still draw the default's file).

The format leaves room for appearance settings: a later `settings:` list would be one more list of entries of the same shape. Today `settings:` is refused with "Appearance settings are not built yet."

## What a stored name means

**The one rule for all three: a stored name the current theme does not know is drawn as the default, and nothing stored changes.** Not when the page is drawn, not when CS Studio opens it, not when a deploy changes the theme. A deploy with another theme rewrites no row, no copy and no audit event.

- **Drawing.** The Section's `style` is the stored name while the theme declares it, else nil. `Theme#page_template(stored)` is the stored name while the theme declares it, else the theme's first, and never nil (the default theme's first for a theme built around the check with none). The Card's `icon` is nil for a blank name, an undeclared name, a file gone since the check, or one that no longer passes the fence (`Theme#icon_svg` fences the bytes it inlines, not only those the check read).
- **Saving.** A choice is valid when it is blank, declared now, **the value already stored**, or **carried**. So an autosave of a form after a theme change does not fail on a style nobody touched; choosing another value replaces it, and the unknown name cannot be chosen back once it is gone. The `:theme_choice` type's `validate` asks this of `stored` (the block's `stored_settings`); `Page#settings_are_known` asks it of the page's `settings_in_database`.
- **Carried names** (`carried_settings`, on `ContentBlock` and on `Page`, never stored). A duplicate and a discard write a name onto a record that did not store it: `ContentBlocks::Duplicate` hands the original's settings to the copy, `Publishing::DiscardChanges` hands the copy's settings to the page and to each restored and re-created block. Their names count as stored for that save, so a discard of a section whose published style the theme has since dropped writes it back instead of being refused.
- **Absent means the default.** A page that uses the theme's first template stores no template (`{}`): the settings form and the New page dialog send blank for the first, and `Pages::Save` drops a template equal to the first when the page stores none, so a save of a title never pins a page to today's first template (and never marks a live page as changed with nothing to publish). The cost: a page cannot be pinned to the first template explicitly; it follows the theme's first.
- **A refused theme** (a development reload whose folder is refused) brings nothing, so CS Studio offers the default theme's lists until the folder is mended, marking the theme's names "not in this theme". Nothing is written by that.
- **Validated against the theme that runs.** A save is checked against `Theme.current`, so a seed or a test that saves a card's icon or a section's style under one theme is refused under another (the default theme declares no section styles). A site's loader runs under the site's `THEME_PATH`; a test draws the theme with `with_choices_theme` and the like.

Tests: `test/models/content_model/theme_choice_field_test.rb`, `test/models/page_test.rb`, `test/services/pages/save_test.rb`, `test/services/content_blocks/duplicate_test.rb`, `test/services/publishing/discard_changes_test.rb`, `test/values/theme_test.rb`.

## The editor's select

- **A select is drawn only where there is a choice**: for a section's style and a card's icon when the list has one entry or more (blank, "Default" or "No icon", is the other choice); for a page's template when it has two or more; **and always when the stored name is not in the theme**, since every save sends the field back and the editor must be able to see and change it. Otherwise nothing is drawn, label included (`Admin::Fields::ThemeChoiceField.draws?`, asked by `Admin::Ui::FieldComponent` as `render?`).
- **An unknown stored name comes first, selected, by its name, marked "not in this theme"**; then the default; then the theme's entries in the theme's order, by their labels.
- **The words are keys** ("Style", "Template", "Icon", "Default", "No icon", "not in this theme": `config/locales/admin/fields.en.yml`, `editor_screen.en.yml`); a theme's labels are its data, always escaped text.
- **On a translation tab** a choice is shared by every language: a line of the shared fields, read by the type's `display` (the label, or the name marked "not in this theme"). **A held form** disables the select as every held control (`HeldFields`).
- **The hero fields follow the template.** Each template option carries the fields its template declares (`data-fields`), and `admin--editor--template-fields` shows or hides the hero's group by `hidden` alone: the groups are always in the form, because a form holding unsaved text is never replaced. A hidden hero still posts its values (harmless: `Pages::Save` takes them), and changing the template clears nothing.
- **The New page dialog** asks for the template under the same rule (two or more) and sends blank for the first.

Tests: `test/components/admin/fields/theme_choice_field_test.rb`, `test/components/admin/editor_screen/page_settings_form_component_test.rb`, `new_page_dialog_component_test.rb`, `section_card_component_test.rb`, `shared_fields_component_test.rb`, `held_fields_test.rb`, `block_card_component_test.rb`, `test/integration/admin/page_editor_test.rb`, `test/integration/admin/new_record_dialogs_test.rb`, `test/system/admin/editor_fields_test.rb`, `test/system/admin/card_block_test.rb`.

## CS Studio and the theme

CS Studio now reads a theme's declarations (`Theme.current.choices`), and only those: **its names and labels as escaped text, and its icons as `<img>` of their served address**, never inlined (`ThemeChoiceField#icon_source`, `Theme#icon_asset`; Propshaft serves the theme's `assets/images` and the CMS's own). A browser runs no script and loads nothing from an SVG shown as an image. No template, partial, stylesheet or script of a theme reaches CS Studio. The cost: an icon drawn in `currentColor` is black in an `<img>`, so its preview stands on a light ground.

Test: `test/integration/theme_pages_test.rb` (the "nothing of a theme reaches CS Studio" cases: a theme's file named as an admin view, a theme choice's labels, a card's icon).

## Section styles and the anchor

The Section's schema has `style` (`:theme_choice`, `of: :section_styles`) and `anchor` (a `:string` with a format). Both are settings like `layout`: in the copy, audited, held and stale-checked as every block setting is, and shared by every language.

- **`style`** is handed to the Section's template (the ledger line `block page columns layout background width style anchor`). The default template writes `content-section--style-<name>` beside the band's class, so a theme that only declares styles and writes CSS needs no template; without a style the markup is as it was. **A grid of five or more columns** is a style whose template draws its own grid from `columns` flattened in reading order; the editor still shows the section's lanes. `layout`, `background` and `width` stay; a style may ignore them.
- **`anchor`** is the address of a link that jumps to the band (`#services`) and the section's `id`: lowercase letters, digits and hyphens, a letter first, at most 40 characters, refused otherwise and never cleaned (no `maxlength`, which would cut a paste). Blank is none. Unique among the page's sections: checked in `ContentBlocks::Save` under the page's row lock with a field message, with a partial unique expression index (`index_content_blocks_on_section_anchor`) as the backstop. A duplicated section's anchor is cleared. A discard releases the anchors it changes before it writes any back, so an anchor that moved between two sections is restored. A heading of the article whose id would equal an anchor of the shown page gets the next suffix (`ThemeHelper#page_anchors`), so the anchor is always the section's. The ids the public templates write themselves are refused as anchors with "already taken by the page itself" (`BlockTypes::Section::RESERVED_ANCHORS`: `page-children-label`, and `note-<id>-…`, `code-<id>-…`, `table-<id>-…` for any id). A theme should not use ids an editor may pick.

Tests: `test/components/blocks/section_component_test.rb`, `test/services/content_blocks/section_anchor_test.rb`, `test/services/content_blocks/duplicate_test.rb`, `test/services/publishing/discard_changes_test.rb`, `test/helpers/theme_helper_test.rb`, `test/integration/admin/content_blocks_test.rb`, `test/integration/theme_pages_test.rb` (the fixture theme `section_grid`).

## Page templates

**Page templates replace the page types.** The integer enum `page_type` is gone with `Page#page_type` and `Page#landing?`, without an alias and without a reader of old copies. A page's template is a name in `pages.settings` (jsonb, default `{}`, not null): `{"template" => "landing"}`, and `{}` is the theme's first. `Page::SETTINGS_KEYS` is a closed set (today `template`), so a forged key never reaches a copy. `settings` moves the settings form's base (`settings_changed_at`) and is written by `Pages::Save`, whose `ATTRIBUTES` swapped `page_type` for `template`.

- **The files.** `views/pages/templates/_<name>.html.erb`, one per declared name; the default theme's are `app/views/pages/templates/_standard.html.erb` and `_landing.html.erb`, today's `pages/show` split in two, each drawing byte for byte what the page type drew. `pages/show` stays the one page template a theme may replace and renders `render "pages/templates/#{page_template}", page: @page, post: @post, list_block: @post_list_block`. A theme that replaced `pages/show` and never asks `page_template` keeps working, except for `@page.landing?`, which the deep check refuses with the sentence to write `page_template == "landing"`.
- **The locals are the contract** (`Theme::Contract::PAGE_TEMPLATE_LOCALS`; the table in `docs/reference/theming.md`, "Page templates"): `page`, `post`, `list_block`. The deep check refuses `@page`, `@post` and `@post_list_block` in a page template and names the local.
- **`page_template`** (a contract helper) reads the page the controller resolved, which on the site is rebuilt from its copy: a template changed and not published is not drawn.
- **A template declares the page fields it draws** (`fields:`, a closed set, today `hero`), which is what CS Studio shows. The subtitle is shown for every template.
- **The subpages list** moved into the two default templates, and its addresses are read in one statement (`PublicSite::Urls#prefetch`, called by `published_views`).
- **Templates are look only**: a redirect, a contact form and a sitemap are behaviour (a page setting, blocks), none built.

**The migration** `20261101100000_replace_page_type_with_page_settings` is frozen SQL calling no application class: it adds `pages.settings`, writes `{"template": "landing"}` into every landing page, rewrites **every** page copy in `published_versions` (current, pending and superseded) so the snapshot loses `page_type` and gains `settings` (whichever form the copy stored the type in, the enum's key or its number), and removes the column. It is named in `test/lib/publishing_guards_test.rb`'s `COPY_MIGRATIONS`, the one rewrite of a copy's content besides `repoint_tag!`. It inserts no row (a schema-loaded database has the column's default), moves neither the content version nor `updated_at`, and leaves the append-only audit log as it is: an old event keeps `page_type` as history, and nothing restores from it.

Tests: `test/models/publishing/page_settings_migration_test.rb`, `test/models/publishing/first_copies_migration_test.rb`, `test/lib/publishing_guards_test.rb`, `test/models/publishing_test.rb`, `test/models/publishing/changes_test.rb`, `test/integration/public_drafts_test.rb`, `test/integration/public_subpages_test.rb`, `test/integration/pages_routing_test.rb`, `test/values/theme/check_test.rb`, `test/values/theme/scaffold_test.rb`, `test/helpers/theme_helper_test.rb`.

## The Card's icon

The Card (`BlockTypes::Card`; `docs/reference/content-blocks-and-types.md`, "The Card block") stores its icon as a name of the `icons` list. **On the site the file is inlined** (`Theme#icon_svg`, read once per `Theme`: the files are in the fingerprint, so a changed icon is a new `Theme` and a new ETag), with `aria-hidden="true"` and `focusable="false"` added to the root where the file does not write them; `Theme::IconFile.inline` changes nothing else. **In CS Studio it is an `<img>`** ("CS Studio and the theme", above).

**A fence, not a sanitiser.** A theme is trusted as the deployment is; `Theme::IconFile` refuses what an icon has no business holding (the list is in `docs/reference/theming.md`, "Checking a folder") and does not rewrite the file, because a sanitiser would promise a safety a fence does not give and would change the drawing. Two parsers read the file, XML at the check and HTML at the page, so names are compared lowercased and by their local part, every element must be one of SVG's drawing elements in SVG's namespace and unprefixed, and what the HTML parser ends early (a short comment, CDATA, a processing instruction) is refused. **No id in any icon** (the owner, 2026-11-01): an icon drawn twice repeats it, and a reference meant for the layout's gradient could find the icon's own. **The drawing rules (24 view box, stroke 2, `currentColor`, round caps, no fill) bind the default set only**; a theme's icon keeps its stroke, fills, classed layers, its own size and `url(#…)` references to its layout's definitions.

Tests: `test/values/theme/icon_file_test.rb`, `test/values/theme/declarations_test.rb`, `test/components/blocks/card_component_test.rb`, `test/system/card_block_test.rb`, `test/integration/theme_pages_test.rb`.

## The field-type registry

`:theme_choice` and `:link` are the two new field types, and they are written only through one seam: **a field type is one `ContentModel::FieldType` on `ContentModel::FieldTypes` and one input `Admin::Fields::<Type>Field`, and nothing else branches on its name.** All twelve built-ins are registered there (`register_built_ins`, reset and filled first in `config/initializers/types.rb`'s `to_prepare`).

- **`FieldType`** (a `Data`): `name`, `cast` (a value that is not blank to what is stored, or nil), `options` (the type's refusals of a declaration, raised at registration), `validate` (`field:, value:, raw:, errors:, stored:, translations:`), `translatable` (offered to AI translation) and `audit` (`:value`, or `:digest` for two digests and two lengths in an event's changes, the `:code` type's way, read by `Audit::Snapshot`).
- **It names no component**: the content model sits below CS Studio, so a type's input and its read-only `display` are `Admin::Fields::<Type>Field`, found by name. The guard that every type answers every question is therefore two tests, one of the model and one of the components.
- **`:theme_choice`** (`of:` one of `section_styles`, `icons`) asks its options of `ContentModel.theme_choices`, a callable assigned in `config/initializers/types.rb` (`->(list) { Theme.current.choices(list) }`), at each validation and each draw, never kept: `ContentModel` names no `Theme`. It is never translated (refused with `translated: true`), never offered to AI, audited as its name, and refused for a content type, a field group and an outside block type (`FieldTypes::BLOCK_ONLY`): choices for posts are not built, and an outside type's list would need a key of `theme.yml`, which the CMS owns.
- **`:link`** takes an `http`, `https` or `mailto` address, a site-relative one (`/` and then neither `/` nor a backslash), or a bare same-page anchor (`#` and then one or more letters of any script, marks, digits, underscores or hyphens: what a Section's anchor or a heading's id holds, so `#team` jumps to a section and `#`, `# x`, `#/x` and `#a#b` are refused), at most 2,048 characters, with no white space (Unicode's too), control or invisible format character and no backslash anywhere, and refuses anything else with the field's error, never cut. `FieldTypes.link?` is total over any value and never raises, and the Card asks it again before it draws the stored value. `:url` is unchanged.

Adding a type is `docs/reference/content-blocks-and-types.md`, "A new field type".

Tests: `test/lib/field_type_branches_test.rb` (no file outside the registry compares, cases or dispatches on a registered type's name, with each allowance named and still matching), `test/models/content_model/field_types_test.rb`, `test/components/admin/fields/field_types_studio_test.rb`, `test/models/content_model/link_field_test.rb`, `test/components/admin/fields/link_field_test.rb`, `test/models/content_model/block_type_definition_test.rb`, `test/models/content_model/field_options_test.rb`.

## Published, audited, translated

- **Published, not live on save.** A style, an anchor and a card's fields are block settings, in the block's copy; a page's `settings` is in `Publishing::CONTENT["Page"]`. The publish dialog's overview names a changed template "Template"; "Discard changes…" writes it back; the mark is set as for any content column. The canary overwrites `settings` like every content column, and an unknown template draws the default, so nothing a visitor sees changes until a publish.
- **Audit**: the existing events of the services (`page.updated`, `block.updated`), with the stored names in their changes. No new action.
- **Translations**: choices are shared by every language and not tracked; the card's title and text are tracked and offered to AI as any translated `:string` and `:text`.
- **The ETag**: `theme.yml` and the icons are files of the folder, so they are in the fingerprint already.

## In tests

- `with_choices_theme` (`test/fixtures/themes/choices`): two section styles (one labelled in two languages), the two page templates and `project` with its file, one icon of its own.
- `with_section_grid_theme` (`test/fixtures/themes/section_grid`): a style whose own Section template draws a grid, written from the Section's row alone.
- `with_card_theme` (`test/fixtures/themes/card`): a Card template and an icon written from "The Card block" alone, the icon classed, filled, of its own size and filled by a gradient its frame defines.
- `with_page_templates(*names)`: the default theme with other page templates and no files, for a dropped or an added name.
- A test that saves a choice saves it under the theme that declares it ("Validated against the theme that runs", above).

## What is not built

- A report of stored names the current theme does not know (a System status row, or a task that counts them), useful after a deploy that changes the theme.
- Appearance settings (`settings:` in `theme.yml`, an Appearance card, a contract helper).
- A choice a gem's block type declares; choices for posts, content types or per language.
- `pages.translated_settings`, a page schema, field groups for pages.
- A link that follows a page (Links, D13): a card's link to a page by its address breaks when the slug changes.
- Hiding a section's `layout`, `background` and `width` for a style that ignores them; how the editor's lanes read for a style that draws its own grid.
- An image on a card.

## What a change can break silently

- **A branch on a field type's name** outside the registry (`field.type == :code`, a `case` over types): the type's behaviour is then in two places, and a new type misses the second. `test/lib/field_type_branches_test.rb` greps `app/` and `lib/` for it.
- **A drawing or a save that writes a "corrected" name** (a style the theme dropped cleared, a template set to the first): content would then change because the theme changed. Nothing draws or opens by writing; the tests above hold the save side.
- **A choice validated without `stored`/`carried_settings`**: every form holding a dangling name would be refused on its next keystroke, and a discard would roll back.
- **A theme's icon inlined in CS Studio**, or a label marked safe: the first theme data that reaches CS Studio crosses the line `test/integration/theme_pages_test.rb` holds.
- **A form that sends the theme's first template for a page that stores none**: every save would pin the page and mark a live page as changed.
