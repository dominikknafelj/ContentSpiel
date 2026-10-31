# Theme choices: section styles, page templates and the Card block

Status: design (2026-10-31), not built. Issues #104 (section styles), #106 (page templates) and #105 (the Card block). The owner's decisions are those of 2026-10-31 and are binding; calls marked "(my call)" are this spec's and the owner may overturn them. Looks are not decided here: "Open design questions" lists what goes to the Design System. The architecture review of 2026-10-31 is folded in where this work touches the code a finding is about ("The architecture review's findings", near the end).

## Why

A theme today can tell two sections, two pages or two items apart only by where they are: the third section of the homepage is the contact band, a page under "Work" is a project page, the second item gets the second icon. An editor who reorders sections in CS Studio, moves a page in the tree or adds an item breaks the design, and nothing says so. The fix is the same for all three: **the theme declares named choices, an editor picks one, and the choice is stored on the section, the page or the card**, so it moves with it.

One mechanism, three uses:

- **Section styles (#104).** A theme declares styles (a name and a label each); an editor picks "Style" in a Section's settings; the Section's template reads `style`.
- **Page templates (#106).** A theme declares templates (a name, a label and a template file each); an editor picks "Template" in the page settings; `pages/show` draws the chosen template.
- **The Card block (#105).** A new built-in block type: an icon, a title, a text and an optional link, title and text translated, the icon one of a set the theme declares (a name, a label and an SVG file in the theme folder).

## Goals, non-goals, anti-goals

**Goals**

- A section, a page and a card keep their look when they are moved, reordered or copied: the look follows a stored name, never a position.
- A theme declares its choices in a data file and holds no Ruby; the declarations are checked as strictly as the rest of the folder.
- A stored name the current theme does not know is drawn as the default and changes nothing stored, so a theme changed by a deploy never takes a page down and never rewrites content.
- Page templates replace the page types `standard` and `landing`; the default theme's "Standard" and "Landing" draw exactly what those types draw today.
- The data file's format can later carry a theme's appearance settings (footer text, link lists, a palette colour) without a change of format.

**Non-goals (this work)**

- Appearance settings of any kind: the format leaves room for them; nothing reads or shows them.
- A choice a gem's block type declares or reads: outside types stay as they are (below).
- Choices for posts, for content types, or per language.
- Behaviour per template: a template is a look. A page that redirects, a contact page with a form, a sitemap page are kinds of behaviour and are not templates (the roadmap's page-type candidates, "Questions only the owner can answer").
- A menu link that leaves the site, "show in menu", a navigation title.
- A report of which stored names the current theme does not know (named under "Left for later").

**Anti-goals**

- Content that changes because the theme changed. A deploy with another theme rewrites no row, no copy and no audit event; it only changes what is drawn.
- A theme's file or script in CS Studio. CS Studio shows a theme's names and labels as text and its icons as images, and nothing else of it.
- A choice that goes live on save. A page's template and a section's style are content: they are published with "Publish changes…", like a title.
- Ruby in a theme by the back door: the data file is data (no ERB in it, no tags, no aliases), read once per `Theme`.

## Constraints: the CLAUDE.md rules this touches

Each is kept as written; where this work extends one, the extension is said.

- **"A theme folder is checked strictly, and a file the contract does not name stops the boot."** `theme.yml` becomes a name the contract knows, at the folder's top beside the four folders. A misspelt key, a missing template, a missing or refused SVG, a template file no declaration names: each is a problem of `Theme::Check`, at the plain depth, so the boot and every development reload say it. The reading is a fence against mistakes, not a sandbox.
- **No Ruby in a theme** (theming decision 8), and **"a theme brings no settings"** (decision 5). Decision 5 is about content a switched theme could not draw. A choice is a name stored on content the CMS draws with or without the theme, and an unknown name draws the default, so decision 5's reason holds and its wording becomes "a theme brings no settings and no block types; it may offer named choices, which degrade to the default" (my call on the wording; the reference says it).
- **"A theme reaches the two public controllers and nothing else."** Extended, on purpose: CS Studio now reads a theme's declarations (`Theme.current.choices`), its names and labels drawn as escaped text and its icons as `<img>` (never inlined there). No template, partial, stylesheet or script of a theme reaches CS Studio, and the guard that says so (`test/integration/theme_pages_test.rb`, "nothing of a theme reaches CS Studio…") grows a case for the icons and labels.
- **`Theme::Contract` names are promises**; renaming or removing one is a release note. Every new name below is a ledger line or a contract row, written with its release note ("Where the release note goes").
- **Every column of `pages` is in the copy, on the rows or never stored** (`test/models/publishing_test.rb`). The new column `pages.settings` is in the copy; `page_type` leaves all three lists with its column.
- **A new database is built by loading `db/schema.rb`.** The migration only transforms rows that exist (it inserts none, so `test/lib/built_in_data_test.rb` has nothing to account for), and an empty `settings` is the default template, so a schema-loaded database needs nothing.
- **No new integer enums** (roadmap, "Guardrails"). The page's template is stored as a name in a jsonb column; `enum :page_type` goes.
- **A helper a theme's template may call reads a published record through its copy.** `page_template` reads the settings of the page the controller resolved, which on the site is rebuilt from its copy.
- **Every content write goes through an `ApplicationService`**, and **`Pages::Save` takes only the keys in its `ATTRIBUTES`.** The template is written by `Pages::Save` (its list swaps `page_type` for the template), a section's style and a card's fields by `ContentBlocks::Save`, as every block setting is. No new service.
- **The page settings form's base is `pages.settings_changed_at`**: `settings` joins the columns whose change moves it.
- **`Publishing::DiscardChanges` writes back through `Pages::Save`**: it writes `settings` back where it wrote `page_type`.
- **A block type declares what it brings**, and a built-in starts from `bin/rails generate block_type`: the Card follows "Adding a block type" step by step, with a sample, `theme_methods`, its tokens, the ledger and a fixture theme.
- **Outside types** (`ContentSpiel::Plugins.block_types`) claim no `:container`, declare no `read_only_actions`, and so on: they also may not declare a field of the new choice type (below).
- **Dependency direction**: `ContentModel` is at the bottom and names no `Theme`. What a choice field may hold reaches it as a callable assigned in an initializer, as `RichText.component_renderer` is.
- **The theme's fingerprint is in the public ETag.** `theme.yml` and the icon files are files of the folder, so a changed declaration or icon moves the fingerprint and no stale page is confirmed.
- **New admin strings are keys**; the "Style", "Template" and "Icon" labels, "Default", "No icon" and "not in this theme" are keys. A theme's labels are the theme's data and are drawn as they are given.
- **The Code block's rule that pasted text is text** applies to every label: escaped, never marked safe, in CS Studio and in the public templates.

## Decided

### 1. The declarations live in `theme.yml` at the folder's top

(The owner: a data file, checked strictly; the name `theme.yml` is the working name and my call to keep.)

```yaml
# What this theme offers editors to choose. A name is what is stored and what
# a template reads; a label is what CS Studio shows.
section_styles:
  - name: services
    label: Service tiles
  - name: contact
    label:
      en: Contact band
      de: Kontaktband

page_templates:
  - name: standard            # the default theme's: no file here, drawn as the default draws it
    label: Standard
  - name: landing
    label: Landing
    fields: [hero]
  - name: project
    label: Project page
    fields: [hero]             # views/pages/templates/_project.html.erb

icons:
  - name: brush
    label: Design
    file: icons/brush.svg      # under assets/images
```

**The shape** (my call on each line):

- The top is a mapping of **named lists**. Today there are three keys, `section_styles`, `page_templates` and `icons`, and no other: an unknown key is a problem ("`setions_styles` is not a list a theme may declare: section_styles, page_templates, icons").
- **Each entry is a mapping with a closed set of keys**: `name` and `label` always; `fields` for a page template; `file` for an icon. An unknown key is a problem.
- **A name** is lowercase letters, digits and underscores, starting with a letter, at most 40 characters, unique in its list. It is what is stored and what templates compare, so it never changes with a label.
- **A label** is a String, or a mapping of locale codes to Strings. CS Studio shows the label of its own interface language, then English, then the first one given (my call: CS Studio runs in English today, `docs/reference/i18n.md`, "How CS Studio chooses its own UI language", and a German interface is planned; a single String is the common case and costs nothing). A label is text: no markup is read from it.
- **A list a theme does not declare is the default theme's list.** A list it declares, even an empty one (`section_styles: []`), replaces the default's whole. A theme with no `theme.yml` offers exactly what the default theme offers. This is the rule a template already follows: what the folder does not hold is the default theme's.
- **An entry that names the default theme's entry of the same name and brings no file is that entry**: `landing` with no file in the theme is drawn by the default theme's Landing template, as a missing template falls back today; an icon `arrow_right` with no `file` is the default's icon. An entry with a name the default does not have must bring its file.
- **The file is read with YAML's safe loader**: no aliases, no tags, no Ruby objects, UTF-8 only. A YAML syntax error is one problem with its line.
- **Room for appearance settings.** A future `settings:` list (the architecture review's "Client sites need editable appearance") is one more named list of entries of the same shape (`name`, `label`, and a `type` such as `text`, `link_list`, `image`, `colour`). Nothing in this format has to change for it, and no version key is needed: an older CMS that meets a newer theme's key refuses it by name, which is the right answer (the theme needs a newer CMS). Today `settings` is refused like any unknown key, with a sentence of its own: "Appearance settings are not built yet."

`ThemeFolder`'s top-level shape admits `theme.yml` as the one file beside the four folders; the strangers' sentence names it. The file is part of the fingerprint as every file is.

**The default theme's declarations are a data file too**, read by the same reader and checked by the same check in a test (my call: the place is the builder's, beside the default theme's other files; `config/theme/default.yml` is the suggestion). It declares `page_templates` Standard (`standard`, no fields) and Landing (`landing`, `fields: [hero]`), `icons` a small set (the Design System's choice, below), and **no section styles**: in the default theme the Style select does not appear.

### 2. What a stored name means

- **A choice is stored as its name**: a section's style in the block's `settings` (`"style"`), a card's icon in the block's `settings` (`"icon"`), a page's template in the page's new `settings` (`"template"`). Blank or absent is the default.
- **The default** is: for a section, no style (the Section template as it draws today); for a page, the first template of the list (the default theme's `standard`); for a card, no icon.
- **A stored name the current theme does not know** (the theme changed, an entry was removed) is drawn as the default. Nothing stored changes: not when the page is drawn, not when CS Studio opens it, not when a deploy changes the theme. A card whose icon is unknown draws no icon (the owner).
- **A save keeps an unknown name it did not change.** The validation accepts a declared name, blank, or the value already stored; so an autosave of a section's form after a theme change does not fail on a style nobody touched (my call; without it every form holding a dangling name would be refused on its next keystroke). Choosing another value replaces it; the unknown name cannot be chosen back once it is gone.
- **A refused theme** (a development reload whose folder is refused) brings nothing, so CS Studio then offers the default theme's lists and marks the theme's names "not in this theme" until the folder is mended. Nothing is written by that either.

### 3. The editor's select

- **A select appears only where the theme offers a real choice** (the owner: only where the theme declares something). For a section's style and a card's icon that is one declared entry or more (blank, "Default" or "No icon", is the other choice); for a page's template, two or more. **Or** where the stored name is not in the theme: the select then appears whatever the theme declares, so the editor can change it.
- **A stored name the theme does not know is shown by its name, marked "not in this theme"**, selected, as the first option. Its look is the Design System's.
- **The options are the theme's labels, in the theme's order.** The select's own label ("Style", "Template", "Icon") is a key.
- **On a translation tab** the choice is shared by every language: a read-only line, as "Page type" is today, so that tab's autosave never sends it. The shared fields' display shows the label (or the name marked "not in this theme").
- **A held form** is read-only as every held form is: the select is disabled by `HeldFields`.

### 4. Section styles (#104)

- The Section's schema gains `style`, a field of the new choice type (decision 7) over `section_styles`, not required, no default. It is a setting like `layout`, so it is in the copy, audited, held and stale-checked as every block setting is.
- **The Section template is handed `style`**: the stored name when the current theme declares it, otherwise nil. The ledger line becomes `block page columns layout background width style`.
- **The default template writes `content-section--style-<name>` on the section** when `style` is a name (my call), so a theme that only declares styles and writes CSS needs no template of its own. The class pattern is a contract row, the one class name of the default theme that is a promise. Without a style nothing changes in the markup.
- **A grid of more than four columns** (#104's "Done when") is a style whose template draws its own grid: it reads the section's blocks in reading order (`columns`, flattened) and lays them out as it likes. The editor still shows the section's lanes; how that reads to an editor is a Design System question.
- `layout`, `background` and `width` stay as they are. A theme's style may ignore them; whether the editor should hide them for such a style is a later declaration, not this work's.

### 5. Page templates (#106)

**The owner's decisions:** page templates replace the page types `standard` and `landing`. The integer enum goes and the template is stored as a name, with no new integer enum. The default theme ships "Standard" and "Landing", drawn exactly as today, and existing landing pages become the Landing template by a migration.

- **Storage: `pages.settings`, a jsonb column carried in the published copy** (the architecture review's "Pages have no extensible fields" direction, decision 11), holding `{"template" => "<name>"}`; `{}` is the default template. Not a one-off `template` column.
- **The template files.** A page template is `views/pages/templates/_<name>.html.erb` in the theme, a partial named by its entry's name (my call: the owner's "template file" is a fixed place derived from the name, so there is nothing to misspell twice; the check refuses the mismatch both ways). The default theme's two are `app/views/pages/templates/_standard.html.erb` and `_landing.html.erb`: today's `pages/show` split in two, byte for byte the same output for each (the scaffold test's byte-for-byte page holds it).
- **`pages/show` stays the one page template a theme may replace**, and the default one renders the chosen template: `render "pages/templates/#{page_template}"`. A theme that replaced `pages/show` before this work and never asks `page_template` keeps working, except for `@page.landing?` (below). A template is the whole of what `pages/show` drew: the heading, the hero, the blocks, the post detail's swap and the subpages, so a template may lay out all of it.
- **The helper `page_template`** (a contract helper) answers the name of the template to draw for the shown page: its stored name when the theme declares it, otherwise the theme's first template. Always a declared name, never nil, never the unknown one.
- **A template declares the page fields it draws** (`fields:`; the owner's suggestion, my call to take it). The set is closed and today holds one entry, `hero` (the hero image and its alt text). CS Studio shows the hero fields in the page settings only when the chosen template lists `hero`, which is exactly today's "hero only for a landing page". **The subtitle stays shown for every template** (my call): it is not only the page template's to draw, since `PublicSite::Branch::Node#subtitle` hands it to any template that draws a menu or a tree. Fields a template does not draw keep their values: changing the template hides nothing for good and clears nothing.
- **`@page.landing?` goes with the enum**, and `page_type` with it, without an alias (the architecture review's "no compatibility code before the first release"). A scaffolded theme's copy of `pages/show` calls `@page.landing?` today (theming reference, "What a copied default template asks of a RECORD is not yet contract"), so the release note says what to write instead (`page_template == "landing"`), and the deep `theme:check` refuses `landing?` and `page_type` in a theme's template with that sentence (my call: a fence for the one mistake every scaffolded theme will make on upgrade).
- **The New page dialog** asks for the template where it asked for the page type, under the same rule as the select (two or more templates). A new page stores the name chosen, or `{}` when the dialog offered no choice.

**The migration** (frozen logic in its own file, calling no application class, as the first copies' migration is):

1. add `pages.settings` (jsonb, default `{}`, not null);
2. write `{"template": "landing"}` into every page whose `page_type` is landing; a standard page keeps `{}`;
3. rewrite every page's published copy in `published_versions` the same way: the snapshot loses `page_type` and gains `settings`, in whatever form the copy stores the type (the builder reads `Publishing::Snapshot.of`). This is the successor migration `test/models/publishing/first_copies_migration_test.rb` asks for when a copy's shape changes on purpose, and it is the one rewrite of a copy's content outside `repoint_tag!` (my call over a reader that understands old copies: no compatibility code, and every copy then has one shape);
4. remove `pages.page_type`.

Nothing is drawn differently afterwards, so the migration moves no content version. **The audit log is not rewritten**: it is append-only (`db/triggers/audit_events_append_only.sql`), and an old event's snapshot and changes keep `page_type`. They are history; nothing restores from them (a discard restores from the copy).

### 6. The Card block (#105)

A built-in block type made with `bin/rails generate block_type card`, following "Adding a block type" from step 0 to step 11.

| Value | Where it is stored | Translated |
|---|---|---|
| icon | `settings["icon"]`, a field of the choice type over `icons` | no |
| title | a `:string` field, `translated: true` | yes |
| text | a `:text` field, `translated: true` (plain text, a sentence or two; my call over a rich-text body, which would bring the toolbar, Markdown and the render cache for a sentence) | yes |
| link | a `:url` field (my call: the same in every language) | no |

- **No column, no migration, no service**: settings and translated settings, as the Code block's are.
- Nothing is required (the picker creates an empty block first). `render?` is false without a title and a text in the language shown along the site's fallback.
- **The link** is drawn only for `http`, `https`, `mailto` and an address that starts with one `/` (my call, the rule `safe_social_links` follows); anything else is no link. A link to a page of the site written as its address breaks when that page's slug changes: a link that follows a page is the roadmap's "Links (D13)", not this work's.
- **The icon on the site is inlined** (decision 8), so a theme colours it with `currentColor` and its tokens. It is decoration: `aria-hidden="true"` and `focusable="false"` on the root, since the title says what the card is. A card whose icon is unknown or blank draws no icon element at all.
- **The template's line** (the ledger and the contract; exact names are the builder's within this meaning, written once into the ledger): `block`, `page`, `title`, `text`, `link` (the address when it may be drawn, else nil), `icon` (the icon's SVG markup, safe, or nil) and `icon_name` (the stored name when the theme declares it, else nil).
- **Tokens**: the card's own, themed, each defined from a base token as the Note's and the Table's are, re-valued in a strong band where needed, and measured in `test/integration/design_tokens_test.rb` on the page, a tinted band and a strong band in both schemes. Their names and number are the Design System's.
- **CS Studio**: the card is drawn from the schema (`Admin::EditorScreen::BlockCardComponent` needs nothing); the type's icon is a new entry of `BlockTypeDefinition::ICONS`; the tile's `summary` is the icon's label and the title. `read_only_actions`: none expected.
- **The sample** fills all four fields, with an icon of the default theme's set and a title and text in three languages, chosen as a hand-written row is (CLAUDE.md, "Every block type's sample…").
- A row of cards is a Section with cards in its lanes; a theme's section style may draw them as its own grid (decision 4).

### 7. A field type for a theme's choices, through one seam

Section styles and card icons are block settings whose options come from the theme at run time, which no field type can say today (`:select` takes a fixed `options:` list). So there is one new field type, `:theme_choice`, with `of:` naming the list (`section_styles`, `icons`; my call on the name).

- **The options are asked at run time** of a callable, `ContentModel.theme_choices = ->(list) { Theme.current.choices(list) }`, assigned in `config/initializers/types.rb` (my call; `ContentModel` names no `Theme`, the dependency rule). The `FieldSet` is built once per definition and asks at each validation, so a theme reloaded in development is seen without a restart.
- **It is never translated** (refused with `translated: true`, as `:code` is) and never offered to AI.
- **Its audit form is the stored name**, as a select's is.
- **An outside type may not declare one** in step 1 (refused at registration, the type's name first): a gem's choice would need a list of its own in `theme.yml`, whose keys are a closed set the CMS owns. Opening that is the gem hook's step 2.
- **It is added through the seam the architecture review asks for** ("A field type's behaviour is spread over seven core files", pulled in, decision 11): one `ContentModel::FieldType` per type answering cast, validation, option rules, its input component, its read-only display, whether it is translatable and its audit form, the built-in types registered in one place, and a guard that every registered type answers every question. `:theme_choice` is written only through it. The ten existing scalar types move onto it in this work (my call: the guard is only a guard if it covers every type, and adding an eleventh type the old way is exactly the silent miss the finding names). If that is more than the owner wants in this work, it is the first thing to cut ("Questions only the owner can answer").
- A page's `template` is not a block field: `Page` checks `settings` itself (a closed set of keys, today `template`, and the stored-name rule of decision 2). Whether page settings later become a schema of their own (a `FieldSet` for pages, field groups) is the "Pages have no extensible fields" finding's remaining part.

### 8. Icons: files, safety, and how CS Studio shows them

- **An icon file is an SVG under the theme's `assets/images`** (`file:` is a path under it), so it is checked by the rules every image already meets (the extension, never shadowing one of the CMS's assets) and served by Propshaft at its digested address. The default theme's icons are SVG files among the CMS's own images.
- **A theme is trusted as the deployment is, and the check is a fence** (theming, "Checking a folder"). At the plain depth it refuses an icon file that is not well-formed XML with an `svg` root, that is over 32 KB (my call), or that holds a `script` or `foreignObject` element, an event-handler attribute (`on…`), an `href` or `xlink:href` that is not a fragment (`#…`), a `DOCTYPE` or an entity, or a `style` element. Each refusal names the file and what to take out. The CMS does not rewrite or sanitise the file at render (my call: a sanitiser would be a promise of safety a fence does not make, and it would change the drawing); it adds `aria-hidden` and `focusable` to the root.
- **The public site inlines the icon**, read once per `Theme` (it is part of the fingerprint, so a changed icon is a new `Theme` and a new ETag).
- **CS Studio never inlines a theme's file**: it shows an icon as `<img src>` of its served address, where a browser runs no script and loads nothing from an SVG. The select's preview (decision 3, and the Design System's question 3) uses that image. One cost: an icon drawn in `currentColor` shows black in an `<img>`, so its preview needs a ground it reads on in both schemes.
- **An icon's ids**: an SVG that defines ids (a gradient) and is drawn twice on one page repeats them. The check does not refuse ids; the reference says so to the theme's author.

### 9. The published copy, audit, translations and the rest

- **Published, not live on save.** A section's style and a card's fields are block settings, in the block's copy. A page's template is in `pages.settings`, which joins `Publishing::CONTENT["Page"]`. `Publishing::Changes` names a changed template in the publish dialog's overview as a changed field; "Discard changes…" writes it back; the mark is set on save as for any content column.
- **Audit**: every write is the existing event of its service (`page.updated`, `block.updated`), with the stored names in its changes. No new action, so `Audit::Sentence::ACTIONS` and `Editing::Signals::MAP` are untouched.
- **Translations**: choices are shared by every language and are not tracked; the card's title and text are tracked, Missing, Outdated and Translated, offered to AI as any translated `:string` and `:text` field is.
- **MCP and Markdown**: the MCP server has post tools only, and none of this reaches a post, so no round trip changes. A later block or page tool reads and writes a choice as its name (the review's "Plan the MCP page and block tools" constraint).
- **The ETag**: the page's copy id and the theme's fingerprint are already in it, and `theme.yml` and the icons are in the fingerprint. Nothing to add.
- **The canary**: a page's `settings` is overwritten with a canary like every content column; an unknown template draws the default, so nothing a visitor sees changes until a publish. `test/integration/public_drafts_test.rb` gets the case that matters: a live page switched to Landing shows its hero only after "Publish changes…".
- **A deploy that changes the theme** leaves dangling names in rows and copies. That is the intended state: drawn as the default, marked in CS Studio, changed by an editor when they choose.

### 10. Where the release note goes

There is no version, no tag and no changelog yet (the review's "Version the CMS"). This work starts **`CHANGELOG.md`** at the repository's top with an **Unreleased** section and the review's fixed headings (Theme contract, Environment, Migrations needing action, Removed), and writes its notes there (that part of the finding pulled in, decision 11):

- **Theme contract, added**: `theme.yml` and its three lists; `views/pages/templates/_<name>.html.erb`; the helper `page_template`; the Section's `style` and the class `content-section--style-<name>`; the Card's component line and tokens.
- **Removed**: `Page#page_type` and `Page#landing?`, with what a template writes instead.
- **Migrations needing action**: none beyond `db:migrate`; the migration rewrites page copies.

When a version exists, Unreleased becomes its first entry. The guide's contract page names the same changes.

### 11. The architecture review's findings

The owner's rule: a finding about code this work changes has its part pulled in. Every one of the 35 was read against the files this design changes.

| Finding | Here | What and why |
|---|---|---|
| Shrink CLAUDE.md to an index, the commands and the unguarded rules | part pulled in | The new rules this work adds to CLAUDE.md are one line each, with the guard named; the long account goes to the reference. The rest of the shrink is not this work's. |
| Version the CMS: a version number, release tags and a changelog | part pulled in | `CHANGELOG.md` with the fixed sections and this work's entries (decision 10). Not: `ContentSpiel::VERSION`, tags, images on tags, the PR checkbox, a ledger test that asks for a changelog line. |
| The docs disagree on whether a CMS image is published | part pulled in | This work edits `theming.md`'s "What is not built" (line 800) and "Deployment"; it corrects "No CMS image is published yet" and "A published CMS image" there. `hosting.md` and the roadmap are not touched. |
| Registries other than block types are emptied before a gem can register | not touched | The Card's line in `types.rb` is a built-in's; no reset, hook or comment the finding names changes. |
| Image delivery: stable cacheable URLs and a queue of their own for variants | not touched | Icons are theme assets inlined or served by Propshaft, not Active Storage. |
| Content types are code-only, have no declarations, and ship the owner's site | not touched | `theme/contract.rb` is edited, but not `POST_COMPONENTS` or `ContentTypeDefinition`. |
| Integrator kit: a site template, and theme work without a CMS checkout | not touched | `theme:new` writes one more file; the kit is about a site's repository. |
| Add a schema field type that refers to library images | advanced | The `FieldType` seam `:media` would use is built (decision 7). The type is not. |
| Keep code comments about invariants, not plan steps and review rounds | part pulled in | Comments on the lines this work writes or moves (`page.rb`'s enum, `pages/show`, the Section) state invariants, with no `Task N`, round or spec-step references. No sweep. |
| Replace marker comments and exact-line allow-lists with structure | not touched | No new marker is needed: every write goes through its service's callbacks. |
| Split the reference docs and stop citing tests by their full name | part pulled in | The mechanism's account goes into a new `docs/reference/theme-choices.md` instead of growing `theming.md`, which gets only the contract's tables (its test reads them there) and a pointer. Test citations keep the house style. |
| Every image change and publish empties every render cache on the site | not touched | The content version and the render key are unchanged. |
| No whole-page cache, and the content version costs four statements | not touched | The ETag's parts are unchanged. |
| Public read path: one path query per link, and lists that load every body | part pulled in | The subpages list moves from `pages/show` into the two default templates; while it moves, its addresses are read in one statement (`Urls#prefetch` for that list only, held by a `capture_sql` test at 3 and 30 subpages). The header, post lists, alternates and the body projection are not touched. |
| The page tree reads every page and is redrawn on every settings autosave | not touched | `Admin::PagesController` changes its attribute list (`page_type` for the template), not the redraw. A template is drawn nowhere in the tree. |
| Load admin scripts on demand, and give public pages their own import map | not touched | No script is added (the selects are plain). |
| A field type's behaviour is spread over seven core files | part pulled in | The `FieldType` seam and its guard, with every built-in type on it (decision 7). Not: opening it to gems. |
| Pages have no extensible fields | part pulled in | `pages.settings` jsonb in the copy, in `Publishing::Changes` and the discard, written through `Pages::Save`; the hard enum goes. Not: `translated_settings` (no translated page field needs it yet; my call, it comes with the first one, SEO's), and no page schema or field groups. |
| Slots fit one shape | not touched | |
| A routes hook must draw before the public catch-all | not touched | |
| A plugin's tables have no way into a site's database | not touched | |
| Make audit events a usable extension point | not touched | No new action. |
| Give gem authors the CMS's conformance checks | not touched | Outside types gain one refusal (no `:theme_choice`), no check. |
| Split the largest scripts and controllers, and share one merge core | not touched | One constant of `Admin::PagesController` changes. |
| Lower the entry cost of writing a system test | not touched | |
| Every browser test signs in through the form | not touched | |
| Local setup leaves first-day failures to every contributor | not touched | |
| Client sites need editable appearance and site structure | advanced | Templates per page kind are built; `theme.yml` is the manifest's home and its format leaves room for `settings`. Not: the Appearance card, menu links that leave the site, "show in menu". |
| The dev seed shows two of seven block types | not touched | `db/seeds.rb` changes its `page_type:` arguments to the template; the block section the finding is about is not changed. |
| List every environment variable in one place | not touched | No variable. |
| Remove compatibility code a pre-release CMS does not need | followed | No alias for `page_type` or `landing?`, no reader of old copies: the migration rewrites them. Nothing of the finding's list is in the files touched. |
| One name for a person's short name | not touched | |
| Plan the MCP page and block tools to serialise any block type from its schema | not touched | The constraint is noted: a choice serialises as its name. |
| Default a new site to one language | not touched | |
| Solid Cable polls ten times a second when nobody is signed in | not touched | |

## Left to the builder

- The default theme's declarations file's place, and how `Theme` exposes the lists (`Theme#choices(list)` answering entries with `name`, `label_for(locale)`, `fields`, `file`).
- The exact method names of the Card's line and of `page_template`, within their meaning, written once into the ledger and the contract.
- The `FieldType` value's shape, and how the ten existing types are moved onto it without changing what any of them does (every existing test stays green unchanged).
- Whether the check of an icon file uses Nokogiri's strict XML parser or another; the 32 KB limit may move if a real icon set needs it.
- How the default templates share what Standard and Landing have in common (a partial of the default theme's own, not on the contract), as long as each draws byte for byte what `pages/show` draws today.
- Where in `Theme::Check` the declarations are read (the plain depth, beside the folder's shape), and the exact sentences, each starting with the file and ending with what to do.
- The form of a page's copy rewritten by the migration (read it from `Publishing::Snapshot.of`).

## Left for later

- A report of stored names the current theme does not know (a System status row, or a `theme:` task that counts them in the database): useful after a deploy that changes the theme; not built.
- Appearance settings (`settings:` in `theme.yml`, an Appearance card, a contract helper).
- A choice a gem's block type declares; choices for posts.
- `pages.translated_settings`, a page schema, field groups for pages.
- A link that follows a page (Links, D13).
- Hiding a section's `layout`, `background` and `width` for a style that ignores them.

## Open design questions (for the Design System)

Listed, not decided.

1. **Style in a Section's settings**: where the select sits among layout, background and width; what the default option is called ("Default", "Theme default", "None").
2. **"Not in this theme"**: how a select shows a stored name the theme does not know, in the card, in the page settings, on a translation tab's shared line and on a held form.
3. **The icon picker**: a plain select of labels, or a grid of previews (a radio group); the preview's size and the ground it stands on in both schemes, given that an SVG shown as an image draws `currentColor` black; how "No icon" looks.
4. **Template in the page settings and the New page dialog**: its place; whether the hero fields, when the chosen template does not draw them, are hidden or shown dimmed with a word; what a change of template says.
5. **The Card block's editor card and its tile**: the order of icon, title, text and link; the tile's summary; the type's icon in `ICONS`.
6. **The Card on the site** (the default template): the icon's size and colour, the title's level and size, whether the whole card or the title is the link and how a link is shown, the card on a tinted and a strong band, its tokens.
7. **The default theme's icon set**: which icons and how many, and their labels.
8. **A style that draws its own grid**: how the editor's lanes read when the site ignores them.
9. **The publish dialog's overview** naming a changed template or style.

## Questions only the owner can answer

1. **The `FieldType` seam's scope** (decision 7): this spec moves all ten existing field types onto it in this work, under the review rule. The cheaper alternative is the seam and the guard for the new type alone, the others moved later. Which?
2. **The roadmap's behavioural page kinds** (redirect or link page, contact, sitemap page) were page types; with page types gone, this spec treats each as its own page setting or block when it comes, never a template. Is that the intent?

## Risks

- **The first theme data that reaches CS Studio.** The labels are escaped text and the icons images; a later change that inlines an icon in CS Studio, or reads more of the theme there, crosses the line the guard holds.
- **An inlined SVG is markup from a folder.** The fence catches the honest mistakes; it is not a sanitiser, and the reference says so.
- **The migration rewrites published copies**, which no code does but `repoint_tag!`. It runs once, in SQL, and its test compares every copy afterwards with `Snapshot.of` of the same rows.
- **Every scaffolded theme's `pages/show` calls `landing?`** and breaks on upgrade; the release note and the deep check's sentence are the mitigation.
- **The `FieldType` move** touches every field of every type; the existing tests are the net, unchanged.
- **New contract names** (the format, the template folder, a helper, a class pattern, a component's line, tokens) are promises from the day they ship.

## Testing

- **The declarations**: `theme.yml` read and refused by name (an unknown list, an unknown key, a bad or duplicate name, a missing label, a missing template, a template file no entry names, an icon file missing, not an SVG, over the limit or holding each refused thing, a YAML error with its line, an alias, `settings:` with its own sentence); a list not declared is the default's; an empty list is none; an entry without a file is the default's of that name; the default theme's file is sound; the fingerprint moves with `theme.yml` and with an icon; a development reload that refuses the file leaves CS Studio working and every public page saying why.
- **Stored names**: a known, an unknown and a blank style, template and icon each drawn as decided; nothing written by drawing, by opening CS Studio or by a theme change; a save that leaves an unknown name passes and one that sets an unknown name is refused.
- **Section**: the template's `style`, the default's class, a style in each band; a fixture theme that styles a section by CSS alone and one that replaces the template and draws its own grid from the reference alone.
- **Page templates**: Standard and Landing drawn byte for byte as `standard` and `landing` were (the scaffold test, the public page, a post's detail under a landing page); a theme's own template; `page_template` for each case; the hero fields shown only for a template that lists `hero`; the New page dialog; the migration (landing pages and their copies become Landing, standard pages and theirs `{}`, the column gone, a copy after it equal to `Snapshot.of`); `settings` in the copy, in the overview and the discard (`test/models/publishing_test.rb`, `test/integration/public_drafts_test.rb`, `test/services/publishing/discard_changes_test.rb`); the settings base moves with it; the deep check refuses `landing?`.
- **The Card**: the recipe's tests from its sample, at the top level and in a column; the icon inlined with `aria-hidden`, none for an unknown or blank icon; each link scheme; the canary and the scaffold; contrast of its tokens; a fixture theme that replaces its template from the reference alone.
- **The field type and its seam**: every registered type answers every question; `:theme_choice` refuses `translated:`; an outside type declaring one is refused.
- **CS Studio**: the select drawn only under the rule of decision 3; "not in this theme" marked and selected; a held form's select disabled; a translation tab's shared line; icons shown as `<img>` and no theme file inlined (the "nothing of a theme reaches CS Studio" guard).
- **The subpages list**: its addresses in one statement at 3 and 30 subpages.

## Documentation

In `contentspiel-docs`, updated before the release:

- `editors/pages/page-settings-and-search-appearance.md`: Template replaces Page type; the hero fields follow the template.
- `editors/pages/create-and-organise-pages.md`: the New page dialog's Template.
- `editors/pages/arrange-blocks-in-sections.md`: a section's Style, and what "not in this theme" means.
- `editors/pages/build-a-page-with-blocks.md`: the Card block.
- `integrators/theming/what-a-theme-is.md`: `theme.yml` at the folder's top.
- `integrators/theming/build-a-theme.md`: declaring choices; what `theme:new` writes.
- `integrators/theming/the-theme-contract.md`: the format, the template folder, `page_template`, the Section's `style` and class, the Card's line and tokens, and the release note (`landing?` removed).
- `integrators/theming/rendering-blocks-and-pages.md`: page templates, a section style's own grid, the Card's icon.
- `integrators/theming/what-a-theme-cannot-do.md`: a theme now offers choices in CS Studio; it still brings no settings.
- `integrators/how-it-works/blocks-content-types-and-registries.md`: page types are gone; a page's template is the theme's.

In this repository: `docs/reference/theme-choices.md` (new), the tables and a pointer in `docs/reference/theming.md` (decision 5's wording, "What is not built" without "A template per page type"), `docs/reference/publishing.md` (`settings` in the copy, the migration's rewrite), `docs/reference/content-blocks-and-types.md` (the Card, the `FieldType` seam in "Adding a block type" step 3), `CHANGELOG.md`, the CLAUDE.md index and its one-line rules, and the roadmap's rows (#104, #105, #106; page types in "Next", item 2).
