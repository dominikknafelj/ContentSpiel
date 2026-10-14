# A block type declares everything it brings

Status: approved by the owner (2026-10-13). The owner approved the direction the same day: a block type declares what it brings, every list that only repeats it is derived, built-in types stay where Rails puts them, and an outside type comes as a Rails engine through one registration hook. This spec is step 1; step 2 is named at the end and not designed.

## Why

Adding the Code block meant writing it into about twenty places by hand (`docs/reference/content-blocks-and-types.md`, "Adding a block type: what the Code block touched"): the initializer, the theme contract's component and token lists, the default theme's stylesheet imports, a branch in the editor's tile, the held form's allow-list, and a row in every shared test that lists types by name or needs one block of each. Most of those places say nothing a type does not already know. Every one of them is a place to forget, and a gem can reach none of them.

## What changes for whom

**A visitor and an editor:** nothing. Step 1 changes no page, no card, no tile, no word.

**A developer adding a built-in type:** runs `bin/rails generate block_type <name>`, fills in one definition and its files, and the contract, the stylesheet build, the tile, the allow-list and the shared tests take the type in by themselves.

**A theme's author:** the contract is the same names for the five built-ins. A type from a gem adds its own lines to the contract the site runs with, and `theme:new` copies its template too.

## Decisions

1. **The definition gains six declarations; everything else is derived from them.** The lines below are fixed; each is read from the registry by the place that today holds a hand list.

   ```ruby
   BlockTypes.register :code do |t|
     t.label "Code"
     t.field :language, :select, options: CodeHighlight::LANGUAGES, blank: "Plain text"
     t.field :filename, :string, label: "File name"
     t.field :code, :code, max: CodeHighlight::MAX_CHARACTERS
     t.uses :caption
     t.component Blocks::CodeComponent
     t.theme_methods :block, :page, :lines, :code, :language, :language_label, :filename, :caption, :string
     t.tokens themed: %w[syn-comment syn-keyword syn-string syn-constant syn-tag syn-attribute syn-embed]
     t.stylesheet "code.css"
     t.summary ->(block, locale:) { Code.summary(block, locale: locale) }
     t.read_only_actions "admin--editor--code-limit#update"
     t.sample settings: { "language" => "ruby", "filename" => "show.html.erb", "code" => "a = 1" },
              translations: { "en" => { caption: "A template" } },
              shows: [ "show.html.erb", %(<span class="syn-) ]
   end
   ```

   | Declaration | What it says | What is derived from it |
   |---|---|---|
   | `theme_methods *names` | the methods the type's public template may call | the type's line in the contract's components |
   | `tokens themed: [], fixed: []` | the `--th-` names it brings, without the prefix | the contract's two token lists |
   | `stylesheet path` | its stylesheet for the public build | the build's imports |
   | `summary callable` | its line on a closed block's tile, as data | the tile's per-type branch |
   | `read_only_actions *ids` | its editor script's actions that only read | the held form's allow-list |
   | `sample settings:, translations:, body:, image:, shows:` | one filled block of itself | one block of the type in every shared test |

   Reason: these are the six things the map found written by hand per type (the map in `.superpowers/block-types-map.md`, sections 2, 3, 6 and 7). A declaration that is not read by something derived would be documentation in code; each of these is.

2. **`theme_methods` and `sample` are required; the other four are optional.** `finalize!` refuses a block type without either. Reason: a type's public template is part of a site's look, so a theme must be able to replace it, which needs the line; and the sample is what lets the shared tests (the canary above all) cover a type nobody wrote a row for. A type with no tokens, no stylesheet, no editor script and the default tile is ordinary. The test-only `test/quote` type gains both lines.

3. **A block follows the look of where it is drawn: in CS Studio CS Studio's, on the site the theme's** (the owner, 2026-10-13: "for the backend it follows the backend, for the frontend it should follow the theme"). In CS Studio a type brings no colour of its own: its card, tile and inputs are drawn with CS Studio's design system and its tokens, as every type's are. On the site a type's tokens are defined IN TERMS OF the theme's base tokens (`--th-accent`, `--th-accent-tint`, `--th-ink`, `--th-line`, `--th-surface`, …), never as colour literals, so a theme that re-colours its base re-colours every block, built-in or from a gem, and a theme may still give any block token a value of its own. For a built-in type the defaults stay in `tokens.css` (the default theme's rule "tokens.css is the one place a colour literal is written" holds; a built-in token may keep a literal where no base token is right, as the seven syntax colours do), and the strong band's re-values of the Code block stay in `sections.css` in step 1. An outside type writes its tokens' defaults in its own stylesheet, as `var()` or `color-mix()` of base tokens only, under the same selectors (`:root, [data-theme="light"]`, `[data-theme="dark"]`, and `.content-section--strong` where it re-values for the band); a guard refuses a colour literal in an outside type's stylesheet. An outside type's token names start with its owner (`gallery-frame` for `gallery/album`, written `--th-gallery-frame`), so two gems cannot claim one name and no gem a built-in's. Contrast of an outside type's pairs is the gem's to test; the CMS computes its own built-ins' only.

4. **The contract is a method, not a constant, and the five built-ins' part of it is held by a ledger.** `Theme::Contract::COMPONENTS`, `THEMED_TOKENS`, `FIXED_TOKENS` and `TOKENS` become `Contract.components`, `.themed_tokens`, `.fixed_tokens` and `.tokens`, because a frozen constant is read when the file loads, before `to_prepare` has registered anything. What is not a type's stays a constant: the shared tokens (`SHARED_THEMED_TOKENS`, `SHARED_FIXED_TOKENS`, today's lists without `syn-*`), `TEMPLATES`, the three post components (`POST_COMPONENTS`; content types are not part of this change), `HELPERS`, `RICH_TEXT`. A block type's line is `definition.component.name.underscore => theme_methods`, so the contract still names no class (`dependency_direction_test.rb` sees no `Component` constant in it). A new test holds a written copy of today's contract, the **ledger** (`test/values/theme/contract_ledger_test.rb`: "the built-in types' part of the contract is the ledger: a name added, renamed or removed is a release note"). Reason: derived lists make adding easy and also make *removing* easy, and a name in the contract is a promise to themes outside this repository. The ledger is the one hand list kept on purpose: changing it is the moment a person writes the release note.

5. **An outside type's lines are as binding for a site as a built-in's, and are its gem's promise, not the CMS's.** `Theme::Check` lets a theme replace `components/gallery/album_component.html.erb` exactly when a registered type hands out that component; `theme:new` copies every registered type's template and names every registered token in the stylesheet it writes; the scaffold's byte-for-byte test runs over every registered type. `docs/reference/theming.md` keeps its tables hand-written for the built-ins, held to the ledger by `theming_reference_test.rb` as today (a generated table is no reading aid in a diff and moves the review of a promise into a script); a gem documents its own lines.

6. **The theme is prepared after the types are registered, in one block.** Today `config/initializers/theme.rb`'s `to_prepare` runs before `types.rb`'s because the files are loaded by name. With a derived contract, the check needs the registry filled. The theme's prepare step moves to the end of the registration block in `types.rb`; `theme.rb` keeps what it does once at boot (watched folders, asset paths). Reason: an order written in one block is read; an order that depends on two file names is not.

7. **The stylesheet build imports each registered type's stylesheet, handed in as data.** `ThemeCss.entry(folder, root:, blocks:)` takes the list from its caller (`lib/tasks/theme_css.rake`, which loads the environment), because `lib/` must not read the registry. The entry becomes: the default theme's `theme.css` (which no longer imports `sections.css` and `code.css`; it keeps `tokens.css` and `prose.css`, which belong to no type), then each type's stylesheet in registration order, then the theme's, then the `@source` lines, now with the folder of every registered component outside `app/components/blocks` (an engine's), so utilities in its template are built. A relative `stylesheet` path is in the default theme's folder; an absolute one is taken as it is (an engine writes `Engine.root.join(...)`). `sources_glance` watches the same files. **The `@theme inline` mapping stays hand-written** for the shared tokens: a type's tokens are not utilities (the Code block's `syn-*` are not today); a type that wants one writes its own `@theme inline` in its stylesheet. **Uncertain:** registration order puts `code.css` before `sections.css`, the reverse of today. They share no selector at equal specificity (read for this spec), so the output should hold the same rules in another order; the build before and after is compared in the pull request. **For the owner** (question 4).

8. **The tile's line is data the type returns and the tile draws.** `summary` is a callable taking the block and the locale and answering parts, each one of a closed set: `[:text, string]`, `[:mono, string]` (the monospace face), `[:word, key, **values]` (a CS Studio word, which the tile looks up under `admin.components.editor_screen.tile_summary.types.<type>.<key>`, a slash in the type's name read as a dot). A model returns no markup and translates nothing (rule "Dependency order"); `Admin::EditorScreen::TileSummaryComponent` draws the parts, as it draws its own today. A type with no `summary` keeps today's rules from the columns it uses (an image's file name, a body's first paragraph), so Rich text and Image declare none; Code and Post list move their branches into `BlockTypes::Code.summary` and `BlockTypes::PostList.summary`, and their words move to the `types.code` and `types.post_list` keys. The marks of attention (unavailable type, missing image, invalid save) stay the tile's. Reason: the tile was the one place a new type had to be named in a component.

9. **The `:code` capability goes.** Its one reader was the tile's branch (and `finalize!` checking the three fields it reads); with the summary in the type's own module, nothing asks it. Reason: a capability is how *other* code asks about a type, and no other code does. **For the owner** (question 2).

10. **The held form's allow-list is the CMS's own four plus every type's `read_only_actions`.** `HeldFields::ALLOWED_ACTIONS` becomes `HeldFields.allowed_actions` (and `rules` reads it), so the region renders the same list to the browser's `editing/freeze`. The decision "may this action survive in a held form" moves from the shared list to the type's definition, where it is reviewed with the type. `held_fields_test.rb` keeps its own list of the four and checks each type's declared actions against its controller file.

11. **One registration hook for outside code: `ContentSpiel::Plugins.block_types { |types| … }`.** In `lib/content_spiel/plugins.rb` (the sixth place: required from `config/application.rb` before `Bundler.require`, so an engine can name it whenever it loads, and not reloaded). The hook keeps the block, not a definition, for the life of the process; the registration block in `types.rb` calls every kept block after the built-ins, on every `to_prepare`, so a reload re-registers outside types against freshly loaded classes as it does the built-ins. An engine calls it from an `initializer` of its own (Rails' convention). Rules:
    - **Order:** built-ins first, in their written order, then outside types in the order their hooks were called (the order of the `Gemfile`). That is the picker's order.
    - **Names:** the hook hands the block a registrar that refuses a bare name (bare names are the built-ins', `ContentModel::Registry::NAME_FORMAT` already reserves them) and a name whose owner is not the same for all the types of one hook call.
    - **A duplicate** is `ContentModel::DuplicateType`, raised at boot with the place the hook was called from in the message (kept with `caller_locations` when the hook is called), so the site's log names the gem.
    - **Not `Admin::`:** `ContentSpiel` is the application's own module (`config/application.rb`); `test/lib/admin_namespace_shadow_test.rb` derives `ContentSpiel` from `lib/content_spiel/` and refuses `Admin::ContentSpiel`.
    Reason: an engine's own `to_prepare` runs before the application's, whose first line is `reset!`, so a gem that registered there would be wiped on every prepare (the map, section 1).

12. **What an outside type may use in step 1.** Fields of every scalar and group type and every option; `uses` within the card's closed vocabulary, `body`, `caption`, `alt`, `image`, which `Definition#uses` now refuses outside of for a block type (today unvalidated, and a fifth name is silently drawn as nothing); no capability: `:container` is bound to the section classes and `BlockOutline`, and `:lists_posts` to `BlockTypes::PostList`'s criteria, which decide post addresses (the map, section 9). Registration refuses either for a name with an owner. Each is opened when an outside author needs it, with a seam of its own.

13. **A block of a type that is no longer registered is dormant, and stays as today.** Verified: the public page skips it with a log line and draws a dormant container's inner blocks (`ThemeHelper#render_block`); the editor shows its card as "Unavailable type — <name>" with only Delete, and the tile marks it; the picker does not offer it; saving it is refused (`ContentBlock` validation). What must stay true after this change: nothing raises on a page that holds such a block, in public or in CS Studio, and removing a gem moves no published copy. One consequence is new: a site whose theme replaces the removed type's template does not start, because the check refuses a template the contract does not name. **For the owner** (question 3).

14. **The sample drives the shared tests.** Its shape: `settings:` (the block's `settings`), `translations:` (locale to values, `"en"` at least; schema fields and the used columns `caption`, `alt`), `body:` (Markdown, through `RichText::Document.from_markdown`), `image: true` (the test attaches a library image), and `shows:` (text the public page must hold for the block; the scaffold test's "the comparison is on" check). A container's sample holds no blocks: the shared tests put one sample of every other type in its first column. A sample that depends on the site (a post list lists posts) relies on the site the shared tests build, which has posts. One helper, `test/support/block_samples.rb` (`sample_block(page, type, section: nil)`), builds a block from a sample through `ContentBlocks::Save`, so every shared test builds it the same way.

15. **Built-ins stay where Rails expects them.** No folder per type: the definition in `app/models/block_types/`, the component and template in `app/components/blocks/`, the stylesheet in `app/assets/tailwind/themes/default/`, words in `config/locales/`. Reason: the owner's standing rules, framework conventions and plain namespaces for internal features. An engine is the packaging for outside code only, and puts the same files in the same places under its own root.

16. **Five built-ins in one pull request, one commit per type, the mechanism first.** The first commit adds the declarations, the derived lists and the ledger, with the five types still written as today; then each type gets its lines and its hand-written entries go, one commit each, the suite green after each. Reason: the ledger and the derived tests go red at the first missed line, and a reviewer reads one type's move at a time.

## Where each derived list sits

Each list is derived where its hand list was, and reads downwards only, so `test/lib/dependency_direction_test.rb` needs no new entry: the definition holds data (names, a path, a callable that answers data), and only a component or a task turns it into markup or a file.

| Derived list | Where | Reads |
|---|---|---|
| `Contract.components`, `.themed_tokens`, `.fixed_tokens`, `.tokens` | `app/values/theme/contract.rb` | `BlockTypes.all` (a value reading a model: allowed) |
| the check, `theme:new`, the scaffold's stylesheet comment | `app/values/theme/check.rb`, `scaffold.rb` | the contract's methods |
| the build's imports and `@source` lines | `lib/tasks/theme_css.rake` builds the list, `lib/theme_css.rb` writes it | `BlockTypes.all`, handed to `lib/` as paths |
| the tile's line | `Admin::EditorScreen::TileSummaryComponent` | `definition.summary`, parts as data |
| the held form's allow-list | `Admin::EditorScreen::HeldFields.allowed_actions` | `definition.read_only_actions` |
| the shared tests' blocks | `test/support/block_samples.rb` | `definition.sample` |
| outside types' registrations | `lib/content_spiel/plugins.rb`, replayed in `config/initializers/types.rb` | kept blocks, called with `BlockTypes` |

The one entry the guard already allows stays the only one: a type's definition names its component (`app/models/block_types/*.rb`, "the registration is the plugin seam"). `summary` is written as a module method of the type (`BlockTypes::Code.summary`) and names no component.

## The generator

`bin/rails generate block_type callout` (in `lib/generators/block_type/`, Rails' place for a generator, with `.tt` templates; `lib/generators` joins `autoload_lib`'s ignore list beside `tasks`, and `CLAUDE.md`'s "Where a class goes" names it). It writes a built-in type of this repository; an engine's generator is step 2.

| File | What it holds |
|---|---|
| `app/models/block_types/callout.rb` | `BlockTypes::Callout.register` with `label`, one `:text` field, `component`, `theme_methods :block, :page`, `stylesheet "callout.css"`, and a `sample` with that field filled and in `shows` |
| `config/initializers/types.rb` | one line, `BlockTypes::Callout.register`, after the last built-in |
| `app/components/blocks/callout_component.rb` and `.html.erb` | `initialize(block:, page:)`, `render?` false for an empty block, the outer element `content-block content-block--callout` |
| `app/assets/tailwind/themes/default/callout.css` | an empty rule under `.content-block--callout`, with the comment that colours are tokens |
| `config/locales/public.en.yml`, `config/locales/admin/editor_screen.en.yml` | an empty `callout:` scope under `public.blocks` and under the tile's `types`, inserted after a marker line; where the marker is missing it writes nothing there and says so |
| `test/components/previews/blocks/callout_component_preview.rb` | a Lookbook preview built from the sample |
| `test/models/block_types/callout_test.rb` | the declaration: fields, nothing required, what is translated |
| `test/components/blocks/callout_component_test.rb` | the markup from the sample, nothing for an empty block, text that looks like markup is text |

The generated type passes the whole suite as written: that is the generator's own test (`test/lib/generators/block_type_generator_test.rb`: "a generated type registers, joins the contract and every shared test, and the suite's guards pass").

## Tests

**What each hand-maintained test becomes** (the map, section 7):

| Test | Becomes |
|---|---|
| `built_in_types_test.rb` "built-ins are registered" | kept: the list of built-ins is a fact, not a repetition |
| `built_in_types_test.rb`, one test per type | kept, plus each type's new declarations |
| `content_block_test.rb:29` (literal names) | kept, for the same reason |
| `theme_pages_test.rb:337,381` (sorted names after a reload) | derived: the names after the reload equal the names before it |
| `contract_test.rb` `registry_components` (skips names with a slash) | derived over every registered type, outside ones included |
| `contract_test.rb:212` (stylesheet list) | derived: the default folder's files and every built-in's `stylesheet` |
| `contract_test.rb:181` (tokens against `tokens.css`) | derived: every declared token is defined in the built stylesheet, a themed one for light and dark, and no `--th-` name is undeclared |
| `contract_test.rb` Code-only tests, the invented `marquee` | kept |
| `scaffold_test.rb:114` (the page and its words) | derived: the page holds a sample of every type, top level and in a column; the words are the samples' `shows` |
| `public_canary_test.rb:40-53` (rows per type) | derived: one sample of every type, top level and in a column, then overwritten |
| `public_blocks_test.rb` | per-type tests kept; one derived test added (below) |
| `design_tokens_test.rb:138-141` (`@import "./code.css";`) | derived: the entry imports every registered stylesheet once |
| `design_tokens_test.rb` contrast of the Code block | kept: which pairs on which grounds is a design question, per type |
| `theming_reference_test.rb` | tables held to the ledger; the Code section kept |
| `translation_state_parity_test.rb:248` | kept, plus a derived parity case for every type whose sample has translations |
| `block_card_component_test.rb`, `tile_summary_component_test.rb` | per-type tests kept; the tile's Code and Post list cases read the new keys |
| `held_fields_test.rb:112-118` | its own list of the CMS's four, plus each type's declared actions checked |
| `public_javascript_test.rb:270`, `admin_i18n_test.rb` `CONVERTED` | unchanged |
| `public_readers_test.rb:68,71` (`COMPONENT_FOLDERS`) | the folders of every registered type's component added, so an engine's component is in the guard's reach |

**New guards:**

- The ledger (decision 4).
- `test/models/block_samples_test.rb`: "every registered type has a sample that saves, publishes and draws its words, at the top level and in a column, from the copy": the derived public smoke test, which also renders each type's card and its held form from the sample (every field of the schema is a control, and the held form keeps every name and value).
- "every shared test that builds a site ran each registered type": `sample_block` records the types it built, and each shared test (the canary, the scaffold, the smoke test, the parity case) ends with `assert_every_type_built`, which compares them with `BlockTypes.names` (the parity case with the types whose sample has translations). In the test, not after the run: the suite runs in parallel workers.
- `test/lib/content_spiel/plugins_test.rb`: "a type registered through the hook survives a reload, after the built-ins", "a bare name, a second owner in one call and a duplicate are refused, and the message names the place of the call", "an outside type may not claim `:container` or `:lists_posts`".
- `test/models/content_model/block_type_definition_test.rb`: "a block type without theme methods or a sample is refused", "`uses` outside body, caption, alt and image is refused", "an outside type's token names start with its owner".
- `lib/theme_css` test: "the entry imports the default theme, each registered stylesheet once in registration order, then the theme's, and scans an outside component's folder".
- A test engine in `test/fixtures/engines/sample_block/` would be the honest proof of the hook and the build; it is **step 2**. Step 1 proves the hook with a block registered from a test, which is the same call.

**How the reviewer sees that no behaviour changed:** the ledger (the contract is the same names); the scaffold's byte-for-byte test (every public page under the copied theme as under the default, now over samples of every type); the canary; the full unit and browser suites; and, once in the pull request and not kept, the built public stylesheet and every public page of the seeded site compared before and after.

## What this does not do

- No folder per type, and no engine for a built-in.
- No content-type declarations: the three post components stay written in the contract.
- No public script declaration: a built-in's public controller stays in `app/javascript/controllers/`; an engine's scripts are step 2.
- No generated reference tables.
- No capability for an outside type, and no `uses` beyond the four columns.
- No change to the strong band's re-values in `sections.css`.

## Risks

- **Derived lists make removing a promise as easy as adding one.** The ledger is the brake; it is one hand list, kept on purpose.
- **The stylesheet order changes** (decision 7). If the before-and-after comparison shows a rule winning that did not, `sections.css` is ordered before the types' stylesheets by the entry rather than by registration.
- **The derived shared tests test less than a hand row did where the row was more than "one of each".** The canary's Code row and the scaffold's words were chosen; the samples must be chosen as carefully (a sample that leaves the caption empty proves nothing about the caption). The conversion commits keep each row's values as the type's sample.
- **A stored hook block holds whatever the engine's code does at registration**, run on every prepare. A hook that raises stops the boot with its place named, which is the behaviour wanted, and is also how a broken gem takes a site down.
- **The check's strictness meets a removed gem** (decision 13).

## The owner's answers (2026-10-13)

The owner restated the aim: the block types are part of the CMS and ship with it; this change makes adding one cheap and leaves a door to extend the CMS later, through which nothing but a test passes in step 1.

1. Colours: decision 3 (in CS Studio a type follows CS Studio; on the site its tokens are defined from the theme's base tokens).
2. The `:code` capability goes (decision 9), and the Note block registers without a `:note` capability: a label nothing reads is not kept.
3. A theme that replaces the template of a type no longer registered is refused by the check, strictly, with a message that names the missing type and says to remove the template; the check runs at the image's build, so it stops the build, not a running site.
4. The default theme's own stylesheets (`sections.css` among them) come before every type's stylesheet, by a fixed rule of the entry, whatever the registration order.
5. The hook is `ContentSpiel::Plugins.block_types { |types| … }`.
6. `theme_methods` and `sample` are required of every block type, `test/quote` included.

## What the Note block changes

Its spec (`ContentSpiel-note`, `2026-10-13-note-block-design.md`) is the first customer, and it shrinks:

- The definition gains `theme_methods :block, :page, :kind, :heading, :titled?, :icon, :body`, `tokens themed:` with its sixteen names (`note-note-ground` … `note-warning-border`), `stylesheet "note.css"`, a `summary` and a `sample` (a Tip with a title in two languages and a body). Its sixteen values go in `tokens.css`, light and dark.
- `t.capability :note` goes (question 2): the tile asks its `summary`. The summary needs an icon before its words, so the Note's pull request adds one part kind to the tile's set, `[:icon, name]`, drawn at 12px in `text-meta`.
- Its contract line, its tokens, its import, its tile branch and its rows in the canary, the scaffold, the smoke test and the parity case are no longer steps: what stays per type is the component's own tests, the segmented control, the 72 contrast pairs, the translated title's path through the translation state, the AI field list, the copy and the audit snapshot, the two browser files, the fixture theme and the reference's section.
- Its spec says the body text stays `--th-fg`; the contract has no such token (`ink` is the body's colour). The derived token guard would refuse it; the Note's spec should say `--th-ink`.

## The recipe, rewritten

"Adding a block type" in `docs/reference/content-blocks-and-types.md` becomes:

0. **Decide where each value is stored** (unchanged).
1. **Generate:** `bin/rails generate block_type <name>`.
2. **Fill the definition:** fields, `uses`, `theme_methods` (promise only what a theme's layout can use), `tokens`, `stylesheet`, `summary` if the default tile line is wrong for it, `read_only_actions` for an editor script, and a `sample` that fills every value a visitor reads.
3. **A new field type**, only if needed (unchanged).
4. **What is no component's business** goes in a value object or a query (unchanged).
5. **The component, its template, its stylesheet**, the token values in `tokens.css`, and the contrast of each new pair on every ground in both schemes.
6. **Strings** (unchanged, the generator has made the scopes).
7. **A public script**, if the block has behaviour (unchanged).
8. **An editor script**, if the card needs one; its reading actions in `read_only_actions`.
9. **The contract's ledger and the reference:** the type's line and tokens in the ledger, its rows in `docs/reference/theming.md` and a section of its own, and a fixture theme that replaces its template from that section alone.
10. **The documents** (unchanged).
11. **The whole check** (unchanged).

What a type no longer touches: the initializer beyond the generator's line, `Theme::Contract`, the default theme's `theme.css`, the tile, `HeldFields`, and the rows of the canary, the scaffold test, the smoke test and the parity test. `CLAUDE.md`'s rule "a new block type joins by its component's line in `COMPONENTS` and its tokens' lines" becomes "by its declarations, and by the ledger".

## Step 2, named

- How a site adds a gem to its image: the `Dockerfile` freezes the bundle (`BUNDLE_DEPLOYMENT=1`) and there is no `eval_gemfile`; a site's own Gemfile fragment, or an image layer that bundles again.
- An engine's public and editor scripts: its `config/importmap.rb` added to the application's import map, and the public and admin entry points registering its controllers.
- The stylesheet stamp covering the registered types' stylesheets, so production refuses a build made with another set of gems.
- A sample plugin gem as a test fixture (`test/fixtures/engines/`), loaded in a child process, proving the hook, the build, the check and `theme:new` from outside.
- An engine generator (or a template gem) for `owner/name` types.
- A guide page, "How to write a block type gem", in `contentspiel-docs`.
- The capabilities and columns an outside type may not use yet, each opened with its own seam when someone asks.

## Documentation

In this repository: the recipe above, the reference's "Rules a change can break silently" lines for the ledger and the hook, `docs/reference/theming.md` on outside types' lines, and `CLAUDE.md`'s two rules and "Where a class goes". In `contentspiel-docs`: none for step 1, which changes nothing a person sees; the gem guide is step 2.

In the guide (`contentspiel-docs`, the owner asked for it explicitly): the integrators' pages on theming name the block tokens as defined from the theme's base tokens and list every block's template methods and tokens as the contract now derives them; a page "Adding a block type" for someone working on the CMS, from the rewritten recipe; and, marked as step 2's, a short page saying that the CMS can be extended with a block type from outside and that how a site installs one is not built yet. The pull request names these pages under "Documentation".
