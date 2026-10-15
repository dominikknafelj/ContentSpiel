# The Note block Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A sixth built-in block type, "Note": a highlighted `aside` of one of four kinds (Note, Tip, Important, Warning) with the kind's icon and word (or the editor's translated title, after the kind's word hidden for a screen reader) above a short rich text, themable through sixteen tokens and a replaceable template, and chosen in CS Studio with a segmented control.

**Architecture:** The first block built entirely by the recipe (`docs/reference/content-blocks-and-types.md`, "Adding a block type"): `bin/rails generate block_type note`, then one definition (`app/models/block_types/note.rb`) that declares everything it brings. Its values are a `settings` field (`kind`), a translated schema field (`title`, in `translated_settings`) and the existing `body` column: no column, no migration, no service. Four generic pieces are built first, each usable by any type: `control: :segmented` for a `:select`, `max:` / `help:` / `placeholder_from:` for a `:string`, and `icon … for_block:`, a type's CS Studio icon that follows a value of each block on its card and its tile (the contrast branch's block icons, plan ruling 12).

**Tech Stack:** Rails 8.1, ViewComponent, Minitest + fixtures, Capybara on Cuprite, Stimulus over import maps, Tailwind (product build) and plain token CSS (public build), Postgres jsonb via Mobility.

**Spec:** `docs/superpowers/specs/2026-10-13-note-block-design.md`, corrected 2026-10-15 with Claude Design's D4 answers (decisions 6, 9 and 10). Design answers behind it: B1 to B3 (`/Users/dknafelj/src/ContentSpiel/.superpowers/design-answers/2026-10-13-note-and-table-blocks.md`) and C2 and D4 (`/Users/dknafelj/src/ContentSpiel/.superpowers/design-answers/2026-10-15-contrast-and-icons.md`). Read them before Task 1, with `docs/superpowers/specs/2026-10-15-contrast-and-buttons-design.md` (Rulings 6 and 7: block icons; the dark strong band) and `CLAUDE.md`'s "Rules a change can break silently" for the theming, Code block and held-form rules.

## Global Constraints

- **This plan assumes the `contrast` branch (contrast and buttons, part 1) is merged into `main` and `note-block` is rebased onto it before Task 1 starts.** Every step below is written against that code: `ContentModel::BlockTypeDefinition::ICONS` and `t.icon`, `Admin::EditorScreen::BlockIconComponent` in the picker, the card's head and the tile, `test/support/contrast_measure.rb`, the dark strong band (`--th-band-strong: #34353a`), `border-field-line` for controls. If the branch is not merged yet, stop and say so; do not port pieces of it.
- Four kinds, stored as `note`, `tip`, `important`, `warning`; a new block is a `note`; an unknown stored kind is drawn as a Note.
- Each kind has its own word and its own Lucide icon: `info`, `lightbulb`, `circle-alert`, `triangle-alert` (CS Studio's icon partial spells them `info`, `lightbulb`, `circle_alert`, `triangle_alert`); 16px on the site; in CS Studio the contrast branch's block icon: the type's `info` in the picker (16px dim), the block's kind on the card's head (14px dim) and on the tile (12px meta); always `aria-hidden`.
- The heading is the CMS's word (`public.blocks.note.kinds.*` in `config/locales/public.en.yml`, read in the visitor's language with English as the explicit fallback) unless the editor typed a title; a title replaces the word, the icon and the kind stay. A title that is only the kind's word is no title.
- The text is the block's ordinary rich text (`body`); nothing is switched off in the editor.
- An empty note (no text in the visitor's language and none in the default one) draws nothing on the site, whatever its title.
- The block is an `aside` named by its heading (`aria-labelledby`), never `role="alert"`; the heading is an `h3` (plan ruling 14). Under an editor's title the heading starts with the kind's word and a colon, visually hidden ("Tip: Before you publish"); without a title there is no hidden word, so the kind is never said twice (spec decision 6).
- `theme_methods` are exactly `:block, :page, :kind, :heading, :titled?, :word, :icon, :body` (plan ruling 13: `word` is the eighth); `read_only_actions`: none; no capability.
- Sixteen themed tokens, `--th-note-{kind}-ground`, `-line`, `-ink`, `-border` for the four kinds, light and dark, each DEFINED in `tokens.css` from the theme's base tokens (`var()` and `color-mix(in srgb, …)` of them); body text stays `--th-ink`. The hues (spec decision 9): Note neutral (a 4% tint of `--th-ink` with a `--th-line-strong` rule), Tip `--th-ok`, Important `--th-accent`, Warning `--th-warn`. **No note token names `--th-danger`**: red is kept for errors and destructive actions.
- On a strong band (spec decision 10) a note shares the band's ground, its text is the band's, and each kind keeps its colour on the rule and the icon: the band is a dark ground in both schemes since the contrast branch, so the dark-scheme kind inks are used in both (plan ruling 8).
- Contrast, computed in `test/integration/design_tokens_test.rb`: `--th-ink`, `--th-accent` and the kind's ink each at 4.5:1 or better against the kind's ground, on the page, in a tinted band and in a strong band, in both schemes: 72 pairs. And on a strong band each kind's rule and ink (the icon's colour) at 3:1 or better against the band, in both schemes: 16 pairs.
- Inline code inside a note: `--th-surface` ground with a 1px `--th-line` border.
- `title` is `:string`, translated, at most 80 characters; the kind is the same in every language (`settings`).
- No column, no migration, no service; the writes are `ContentBlocks::Save`, `Duplicate`, `Destroy`, `Reorder`.
- CS Studio strings are keys (`config/locales/admin/`); a type's label, a select's choices, `blank:`, `label:` and (new) `help:` are literals in the definition (`docs/reference/i18n.md`, "Out of scope, named").
- No colour literal outside `tokens.css`; no inline event handlers; tokens, not colours, in CS Studio markup.
- Tests: every command is prefixed `PGGSSENCMODE=disable`; before any system or design-token run, `bin/rails tailwindcss:build` then `bin/rails theme_css:build` (never while tests run); system runs with `PARALLEL_WORKERS=6`; no fixed `sleep`; a click is `press` (or a native `.click` on a found node), never a scripted click without its one-line reason; any JavaScript error fails a system test.
- Every commit message is conventional (`feat|fix|ref|style|docs|test|chore`) and ends with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT
  ```
- Work in `/Users/dknafelj/src/ContentSpiel-note` on branch `note-block`; never push from a task.

## Plan rulings

Where the spec assumes something the code does differently, the plan takes the design that conforms to the code and says why. Each ruling is also written into the spec's "As built" in Task 10.

1. **`KINDS` lives on the type, not the component.** The spec writes `options: Blocks::NoteComponent::KINDS`. The tile's line is a module method of the type (`BlockTypes::Note.summary`) and needs the kinds and their icons, and a model names a component only to register it (`CLAUDE.md`, "Dependency order"). So `BlockTypes::Note::KINDS` (value to CS Studio label, a literal like `CodeHighlight::LANGUAGES`) and `BlockTypes::Note::ICONS` (value to Lucide name) are the type's, and `Blocks::NoteComponent` reads them.
2. **`max:` on a `:string` did nothing.** `ContentModel::FieldSet#validate_fields` reads `max:` for `:code` (characters) and `:integer` (a bound) only, so `max: 80` on the title would be silently ignored. Task 2 teaches `:string` the same `:too_long` as `:code`, and checks a translated string in EVERY language it is stored in, because `ContentBlock#settings_are_valid` validates the default language only and a German title would otherwise pass at any length. Refused on the server with the text left in the field; no `maxlength` (the Code block's rule: a `maxlength` cuts a paste without a word).
3. **The title's placeholder and help line need two schema options.** The card draws every type's fields generically, and the schema had no placeholder and no help line. Task 2 adds `help:` (a literal line under a string field, its `aria-describedby`) and `placeholder_from:` (names an earlier `:select`; the card shows the label of the choice stored, and a small reading script, `admin--ui--placeholder-from`, follows a new choice before it is saved). A placeholder drawn from the stored kind alone would say "Note" while "Tip" is pressed. A post type's field with `placeholder_from:` gets the help line but no placeholder: only the block card hands one over (a roadmap row in Task 10).
4. **The sample's body is `body:`, not a key of `translations`.** `BlockTypeDefinition::Sample` takes the body as Markdown in the default language (`body:`); `translations` holds translated schema fields and the `caption`/`alt` columns. The spec's `translations: { "en" => { title:, body: } }` would be refused at registration.
5. **No block's text makes a page "missing".** `Translations::Status.missing_count` counts the page's title and REQUIRED translated schema fields; a rich-text body left blank in a language is never "missing" for any block type. The spec's "missing in a language only for the body" is therefore not what the code does: a Note never makes its page missing (its title is optional and its text is a body), and both its title and its text are tracked for "outdated". Task 6's test pins that.
6. **The tile's line only.** A collapsed card of the page's own list shows its type's label for every type (`TileSummaryComponent`'s class comment; a roadmap row from the Code block). The Note's line ("Tip · first words") is on the tile, as the Code block's is; the kind's ICON is on the card's head and on the tile (ruling 12).
7. **The kinds' hues are base tokens, as Claude Design's D4a names them (spec decision 9).** Note is neutral: its ground `--th-ink` at 4% over `--th-paper`, its rule `--th-line-strong`, its word and icon `--th-ink`, its frame `--th-line`. Tip is `--th-ok` (word and icon `--th-ok-ink`), Important `--th-accent` (word and icon `--th-accent`), Warning `--th-warn` (word and icon `--th-warn-ink`); for these three the ground is the hue at 8% (light) or 12% (dark) over `--th-paper` and the frame the hue at 24%. No token names `--th-danger`. All mixes are `color-mix(in srgb, var(a) N%, var(b))`, the form the contrast test resolves. Computed beforehand with the contrast branch's values and its arithmetic (`test/support/contrast_measure.rb`): the lowest of the 72 pairs is 4.88:1, the accent (the link, and Important's word) on the light Important ground; the lowest in the dark scheme is 6.64:1 (Tip's word on the strong band).
8. **On a strong band a note shares the band's ground and each kind keeps its colour (spec decision 10, D4b).** A custom property is computed where it is declared, so without a rule a note's ground would stay the page's light tint inside the strong band while `--th-ink` turns to the band's light text. `sections.css` re-values the sixteen inside `.content-section--strong`: every ground `var(--th-band-strong)`, every frame `var(--th-line)` (the band's), the body text the band's through `--th-ink`, and per kind a rule and an ink (word and icon) that keep its colour: Note the band's dim (rule) and the band's text (ink), Important the band's accent (`--th-on-band-strong-accent`, the light blue the band already carries), Tip and Warning their hue mixed 60% with the band's text (`color-mix(in srgb, var(--th-ok) 60%, var(--th-on-band-strong))`). Why not the dark-scheme inks themselves: since the contrast branch the strong band is a dark ground in BOTH schemes (the page's ink in light, the raised `#34353a` in dark), so D4b's "dark-scheme inks on a dark band" applies in both, and a light-scheme page cannot read a dark-scheme token's value; a mix with the band's text is the dark-scheme ink derived from the base, no literal and no new token. Measured: rule and ink at 6.64:1 or better against the band (3:1 asked; the ink is text too, so it is held at 4.5:1 among the 72). Cost if wrong: a theme that colours its strong band light gets light inks on it; the reference says a theme that changes the band answers for these sixteen there, as it does for code.
9. **Note stands after Code in the picker.** The generator writes the line above its marker, after Section; Task 4 moves it after `BlockTypes::Code.register`, so the picker reads Rich text, Image, Code, Note, Post list, Section and the containers stay last. The ledger's component and token order follows registration order.
10. **On a translation tab the segmented control is not drawn.** An untranslated field is listed read-only under "Shared fields" on a translation tab (`BlockCardComponent#shared_fields`, `SharedFieldsComponent.select_label`), which already reads a Hash's label ("Tip"). "Read-only on a translation tab as a select is" holds with nothing new; in a held form `HeldFields` disables every radio. The control's look is the posts list's scope toggle as the contrast branch left it (field-line outline, inverted when chosen).
11. **The four kind icons join CS Studio's closed list.** `ContentModel::BlockTypeDefinition::ICONS` gains `info`, `lightbulb`, `circle_alert`, `triangle_alert`, each a branch of `app/views/admin/shared/_icon.html.erb` (Lucide, 1.5px); `block_icon_component_test.rb`'s "every icon a block type may name is drawn by the icon partial" then draws them. The list spells a Lucide name as the partial's symbol (`circle_alert`, as it has `code_xml`); the public template's `icon` keeps Lucide's own spelling (`circle-alert`), which is the theme contract's (spec decision 2). `BlockTypes::Note::ICONS` holds the Lucide names, and `BlockTypes::Note.studio_icon` turns one into the partial's.
12. **A type's icon may follow its block (`t.icon "info", for_block: ->(block) { … }`); the spec's `[:icon, name]` summary part is not built.** The spec was written before the contrast branch, which draws ONE icon per type in the picker, on the card's head and on the tile (where it stands in for the type's name, kept as `sr-only` text). A summary part would draw a second icon on the tile beside the type's and none on the card's head, which C2 asks for ("Note: its kind icon"). So the Note declares its type icon, `info` (the default kind's, drawn in the picker, which has no block), and a callable that answers the block's kind's icon from the same closed list; `BlockTypeDefinition#icon_for(block)` asks it, and `BlockIconComponent` takes the block on the card and the tile. One icon in each place, a name from `ICONS` and never markup, a built-in's wrong answer raises naming the list, the tile's accessible name still says "Note". Neither the card's head nor the tile's face is re-rendered by a save, so for a type whose icon follows its block the icon carries an id (`block-<id>-icon-card`, `-icon-tile`) and `Admin::ContentBlocksController#update` replaces both with every save that went through, as it replaces the tile's line. An outside type may not declare `for_block:` yet (refused at registration): its callable would run on every card and tile, where a raise is a 500 of the editor, and the tile's rescue for a gem's `summary` is not repeated for an icon until a gem asks. `TileSummaryComponent` and its `LOOKS` do not change. Cost if wrong: a kind changed in another tab shows its new icon on this tab's card only after the live refresh redraws the card or a reload (the live refresh replaces a clean card whole, so it does follow); and a fourth declaration keyword is one more thing the generator's commented `t.icon` line does not mention.
13. **The theme contract's Note line has eight names: `word` joins the spec's seven.** Spec decision 6 asks the template to say the kind's word, hidden, before an editor's title; `heading` is then the title, so the template needs the word by another name, and a template may call only the names its line promises ("a default component template calls no method of its component that its line does not name"). A template that looked the key up itself (`I18n.t("public.blocks.note.kinds.…")`) would make a locale key a silent promise and leave a theme's template, written from the reference alone, no promised way to say the kind. So `word` is promised: the CMS's word for the kind in the language shown, English where that language has none, titled or not. This departs from the spec's list of seven ("The data", "The public side"); the owner confirms it (open questions).
14. **The heading is an `h3`.** D4c asks for the kind to be heard "in a heading list too", so the heading is a heading element, not the first draft's `p`. `h3` because a note stands inside a page's or a section's `h2` part far more often than directly under the page's `h1`; note.css sets its size, weight and spacing, so it looks the same whatever the theme's `h3`. Cost if wrong: a note at the very top of a page skips a level in the outline (an accessibility checker's warning, not an error); a theme's template chooses its own element.

## Open questions for the owner (the plan builds its rulings; each is named in the spec's "As built" in Task 10)

- **The Note's theme line is eight names, not the spec's seven** (ruling 13): `word` is promised so a template can say the kind before an editor's title (decision 6). The alternative, a template that looks up `public.blocks.note.kinds.<kind>` itself, keeps seven names and makes a locale key a promise nobody tests.
- **The spec's `[:icon, name]` part of a tile summary is replaced by `icon for_block:`** (ruling 12), because the contrast branch already draws one icon per type on the tile, the card and the picker.

The three questions the first draft carried (no kind heard under a title, a red Important, four look-alike kinds on a strong band) were answered by Claude Design's D4 and are spec decisions 6, 9 and 10.

## Review Focus

The six inputs the spec implies and no task would otherwise exercise, most likely first. Each has its test in the task named.

1. **A title of only spaces** (pasted, or typed and erased to spaces): it is no title; the site heads the note with the kind's word, with no hidden word before it, and the tile says the word. Test: Task 4, "a title of only white space is no title: the heading is the kind's word, said once".
2. **A stored kind that is not on the list** (written around the services, a canary, a kind removed later): the site draws a Note (word "Note", `info`); the card checks no button and a save that picks a kind is accepted. Tests: Task 4 (component), Task 8 (card and save).
3. **A title with no text** (the editor typed a title, no body yet): nothing is drawn on the site; the tile still shows the title and "Empty". Tests: Task 4 (component and tile).
4. **Text only in the default language, read in another** (a German visitor, English body, German title or none): the English text is drawn under the German title, or under the German word (English where German has no file). Test: Task 4, "a visitor of another language reads the text with the site's fallback, the title in their language where there is one, and the word in English where their language has no words".
5. **A title over 80 characters typed on a translation tab**: refused with the message in the title's slot, nothing written; 80 exactly is saved. Test: Task 8, "a note's title over 80 characters is refused on the German tab too, and nothing is written".
6. **A title that is only the kind's word** ("Tip" typed as a Tip's title, in any case): it is no title, so the hidden word is not added and a screen reader hears "Tip" once, not "Tip: Tip" (decision 6: "so 'Tip' is never read twice"). Test: Task 4, "a title that is only the kind's word is no title: the word is said once".

---

## File Structure

| File | Task | Responsibility |
|---|---|---|
| `app/models/content_model/definition.rb` | 1, 2 | the new options `control`, `help`, `placeholder_from`; `max:` on a string; their refusals; `Field#segmented?`, `Field#help` |
| `app/models/content_model/field_set.rb` | 2 | `:too_long` for a `:string` with `max:`, in every stored language |
| `app/components/admin/fields/select_field.rb`, `.html.erb` | 1 | radios in a `fieldset` for `control: :segmented` |
| `app/components/admin/fields/base.rb` | 2 | `placeholder:` keyword, `help_id` |
| `app/components/admin/fields/string_field.rb`, `.html.erb` | 2 | the placeholder, its script's values, `aria-describedby` |
| `app/components/admin/ui/field_component.rb`, `.html.erb` | 1, 2 | no `<label>` over a segmented control; the help line; forwards `placeholder:` |
| `app/components/admin/editor_screen/block_card_component.rb`, `.html.erb` | 2 | `placeholder_for(field)` handed to each schema field |
| `app/javascript/controllers/admin/ui/placeholder_from_controller.js` | 2 | follows the chosen option's label into the placeholder |
| `app/models/content_model/block_type_definition.rb` | 3 | four names join `ICONS`; `icon … for_block:`, `#icon_for`, `#icon_follows_block?`; an outside type may not declare `for_block:` |
| `app/views/admin/shared/_icon.html.erb` | 3 | four Lucide icons for CS Studio |
| `app/components/admin/editor_screen/block_icon_component.rb` | 3 | `block:`, the block's own icon, `.dom_id` |
| `app/components/admin/editor_screen/block_card_component.html.erb`, `block_tile_component.rb` | 3 | hand their block to the icon |
| `app/controllers/admin/content_blocks_controller.rb` | 3 | `#block_icon_streams`: a save redraws an icon that follows its block |
| `app/models/block_types/note.rb` | 4 | the type: fields, declarations, `KINDS`, `ICONS`, `kind_of`, `studio_icon`, `summary` |
| `config/initializers/types.rb` | 4 | `BlockTypes::Note.register` after Code |
| `app/components/blocks/note_component.rb`, `.html.erb` | 4 | the public block |
| `app/assets/tailwind/themes/default/note.css` | 5 | the public rules, tokens only |
| `app/assets/tailwind/themes/default/tokens.css` | 5 | the sixteen tokens, light and dark |
| `test/support/contrast_measure.rb` | 7 | reads `color-mix(in srgb, var(a) N%, var(b))` |
| `app/assets/tailwind/themes/default/sections.css` | 7 | the strong band's sixteen re-values: the band's ground, each kind's colour |
| `config/locales/public.en.yml`, `config/locales/admin/editor_screen.en.yml` | 4 | the four words; the tile's "Empty" |
| `test/support/contract_ledger.rb` | 4, 5 | the component's line (eight names); the sixteen tokens |
| `docs/reference/theming.md` | 4, 5, 10 | tables, "The Note block", "In tests" |
| `test/fixtures/themes/note/…` | 5 | a theme that replaces the template from the reference alone |
| `test/support/theme_test_helper.rb` | 5 | `with_note_theme` |
| `test/components/previews/blocks/note_component_preview.rb` | 4 | Lookbook, from the sample |
| tests named in each task | 1 to 9 | |
| `docs/reference/content-blocks-and-types.md`, `docs/reference/i18n.md`, `docs/reference/design-system.md`, `CLAUDE.md`, `docs/roadmap.md`, the spec's "As built" | 10 | documents |

---

### Task 1: `control: :segmented` for a `:select` field

**Files:**
- Modify: `app/models/content_model/definition.rb` (`OPTIONS`, `Field`, `#field`)
- Modify: `app/components/admin/fields/select_field.rb`, `app/components/admin/fields/select_field.html.erb`
- Modify: `app/components/admin/ui/field_component.html.erb`
- Create: `test/models/content_model/field_options_test.rb`
- Test: `test/components/admin/fields/select_field_test.rb`, `test/components/admin/ui/field_component_test.rb`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: the schema option `control: :segmented` (only on a `:select` without `blank:`); `ContentModel::Definition::CONTROLS = %i[segmented]`; `ContentModel::Definition::Field#segmented?` (Boolean); `Admin::Fields::SelectField::SEGMENT_CLASS`; for a segmented field the markup `fieldset#<input_id>` > `legend` + one `input[type=radio][name=<form_name>[<name>]]#<input_id>-<value>` per choice, the stored value `checked`.

- [ ] **Step 1: Write the failing tests**

Create `test/models/content_model/field_options_test.rb`:

```ruby
require "test_helper"

# The schema options a field type's look and wording hang on (note block
# spec, "CS Studio"): `control: :segmented` draws a select's choices as a row
# of buttons. Each is refused where it would mean nothing.
class ContentModel::FieldOptionsTest < ActiveSupport::TestCase
  def define(&block) = ContentModel::BlockTypeDefinition.new("sample").tap(&block)

  test "a segmented control is a look of a select: on a select it is kept, and the field says so" do
    definition = define { |t| t.field :kind, :select, options: { "a" => "A", "b" => "B" }, default: "a", control: :segmented }
    field = definition.fields.sole

    assert field.segmented?
    assert_equal :segmented, field.options[:control]
    assert_not define { |t| t.field :kind, :select, options: %w[a b] }.fields.sole.segmented?, "a select without it is a select"
  end

  test "a segmented control is refused on any field but a select, on a select with a blank choice, and as any other control" do
    error = assert_raises(ArgumentError) { define { |t| t.field :name, :string, control: :segmented } }
    assert_includes error.message, "select"
    error = assert_raises(ArgumentError) { define { |t| t.field :kind, :select, options: %w[a b], blank: "None", control: :segmented } }
    assert_includes error.message, "blank:"
    error = assert_raises(ArgumentError) { define { |t| t.field :kind, :select, options: %w[a b], control: :tabs } }
    assert_includes error.message, ":segmented"
  end
end
```

Add to `test/components/admin/fields/select_field_test.rb`, before the final `end`:

```ruby
  # Note block spec, decision 7: a select may be drawn as a segmented control,
  # a group of radio buttons underneath, so it works from the keyboard and
  # without a script. The group is a fieldset named by its legend.
  test "a segmented select is a fieldset of radios named by its legend, the stored choice checked" do
    field = Field.new(name: "kind", type: :select, options: { options: { "note" => "Note", "tip" => "Tip" }, control: :segmented })
    render_inline Admin::Fields::SelectField.new(field:, form_name: "block[settings]", value: "tip", locale: "en", id_prefix: "block-7")

    assert_no_selector "select"
    assert_selector "fieldset#block-7-kind > legend", exact_text: "Kind"
    assert_selector "fieldset#block-7-kind input[type=radio]", count: 2
    assert_selector "fieldset#block-7-kind > div[class~='border-field-line']", count: 1
    assert_selector "label[for='block-7-kind-note'] input#block-7-kind-note[type=radio][name='block[settings][kind]'][value='note']:not([checked])"
    assert_selector "label[for='block-7-kind-tip'] input#block-7-kind-tip[type=radio][value='tip'][checked]"
    assert_selector "label[for='block-7-kind-tip']", text: "Tip"
  end

  test "a segmented select whose stored value is not on its list checks no button" do
    field = Field.new(name: "kind", type: :select, options: { options: { "note" => "Note" }, control: :segmented })
    render_inline Admin::Fields::SelectField.new(field:, form_name: "block[settings]", value: "gone", locale: "en")

    assert_no_selector "input[type=radio][checked]"
  end

  # A form someone else holds is rewritten by `HeldFields`: every radio is
  # disabled, and which one is checked stays.
  test "held by someone else, a segmented select keeps its checked button and disables every one" do
    field = Field.new(name: "kind", type: :select, options: { options: { "note" => "Note", "tip" => "Tip" }, control: :segmented })
    render_inline Admin::Fields::SelectField.new(field:, form_name: "block[settings]", value: "tip", locale: "en", id_prefix: "block-7")
    held = Nokogiri::HTML5.fragment(Admin::EditorScreen::HeldFields.call(rendered_content))

    assert_equal %w[disabled disabled], held.css("input[type=radio]").map { |radio| radio["disabled"] }
    assert_equal [ "tip" ], held.css("input[type=radio][checked]").map { |radio| radio["value"] }
  end
```

Add to `test/components/admin/ui/field_component_test.rb`, before the final `end`:

```ruby
  # The segmented control names itself with its legend; a <label for> above
  # it would point at no control (the radios have ids of their own).
  test "a segmented select has its legend and no label of the field's above it, and its error slot is where it always is" do
    field = Field.new(name: "kind", type: :select, options: { options: { "note" => "Note" }, control: :segmented })
    render_inline Admin::Ui::FieldComponent.new(field:, form_name: "block[settings]", value: "note", locale: "en", id_prefix: "block-7", errors: [ "is not included in the list" ])

    assert_no_selector "label[for='block-7-kind']"
    assert_selector "fieldset#block-7-kind legend", exact_text: "Kind"
    assert_selector "#block-7-kind-errors", text: "is not included in the list"
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `PGGSSENCMODE=disable bin/rails test test/models/content_model/field_options_test.rb test/components/admin/fields/select_field_test.rb test/components/admin/ui/field_component_test.rb`
Expected: FAIL: "unknown field option(s) [:control]" in the model test; `NoMethodError: undefined method 'segmented?'` or "expected to find fieldset" in the component tests.

- [ ] **Step 3: Implement**

In `app/models/content_model/definition.rb`, replace the `OPTIONS` line and its comment's last sentence, add `CONTROLS`, add the `Field` predicate and the refusal:

```ruby
    # `control:` is how CS Studio draws a field where its type's default
    # control is wrong for it: `:segmented` draws a `:select`'s choices as a
    # row of buttons (radios underneath, so it works from the keyboard and
    # without a script; note block spec, decision 7). It is a look and changes
    # nothing about the value or its validation.
    OPTIONS = %i[required default min max translated options of blank label control].freeze
    CONTROLS = %i[segmented].freeze
```

```ruby
    Field = Data.define(:name, :type, :options) do
      def translated? = options[:translated] == true
      def required? = options[:required] == true
      def group? = GROUP_TYPES.include?(type)
      def label = options[:label].presence || name.humanize
      # Drawn as a row of buttons (`control: :segmented`), not a <select>.
      def segmented? = type == :select && options[:control] == :segmented
    end
```

In `#field`, directly after the `blank:` refusal:

```ruby
      if options.key?(:control)
        raise ArgumentError, "`control:` is one of #{CONTROLS.map(&:inspect).join(", ")}" unless CONTROLS.include?(options[:control])
        raise ArgumentError, "`control: :segmented` draws a select's choices as buttons: it is for a select" unless type == :select
        raise ArgumentError, "`control: :segmented` has no button for a select's empty choice: it is for a select without `blank:`" if options.key?(:blank)
      end
```

Replace `app/components/admin/fields/select_field.rb`:

```ruby
module Admin
  module Fields
    # A `<select>` (spec §4.3), for `:select` fields. `field.options[:options]`
    # is either a `{value => label}` Hash (`ContentModel::Definition#field`'s
    # own doc) or a bare Array of values used as both -- `option_pairs`
    # normalizes either shape into `[label, value]` pairs for
    # `options_for_select`, which is what actually marks the current `value`
    # `selected`.
    #
    # A field that says `control: :segmented` (the Note block's kind, note
    # block spec decision 7) is drawn as a SEGMENTED CONTROL instead: a
    # fieldset named by its legend, one radio per choice inside its own
    # label, the radio visually hidden and the label drawn as the segment.
    # Radios underneath, so the arrow keys move the choice and a change
    # bubbles to the form's autosave like a select's; a form someone else
    # holds disables every radio (`HeldFields`), and a translation tab never
    # draws it, since the value is the same in every language.
    class SelectField < Base
      # The posts list's scope toggle's look (`PostsScreen::ToolbarComponent::
      # SEGMENT_CLASS`, as the contrast branch left it: the chosen segment
      # inverted, ink on paper, with a paper focus ring), with a disabled
      # state for a held or view-only form. The group around the segments is
      # outlined in `border-field-line`, as every control is (contrast and
      # buttons spec, C1).
      SEGMENT_CLASS = "flex cursor-pointer items-center border-r border-line px-3 py-1.5 text-sm text-dim last:border-r-0 hover:bg-sunken " \
                      "has-[:checked]:bg-ink has-[:checked]:font-semibold has-[:checked]:text-paper has-[:checked]:hover:bg-ink " \
                      "has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:-outline-offset-2 has-[:focus-visible]:outline-accent " \
                      "has-[:checked]:has-[:focus-visible]:outline-paper has-[:checked]:has-[:focus-visible]:-outline-offset-4 " \
                      "has-[:disabled]:cursor-not-allowed has-[:disabled]:opacity-60 has-[:disabled]:not-has-[:checked]:hover:bg-transparent".freeze

      def option_pairs
        options = field.options[:options]
        return options.map { |v, l| [ l, v ] } if options.is_a?(Hash)

        Array(options).map { |v| [ v.to_s, v ] }
      end

      # The empty choice of a select that is not required: unnamed, unless
      # the field says what it means (`blank: "Plain text"`).
      def blank_choice = field.required? ? false : (field.options[:blank] || true)

      def segment_id(option) = "#{input_id}-#{option}"

      def checked?(option) = value.to_s == option.to_s
    end
  end
end
```

Replace `app/components/admin/fields/select_field.html.erb`:

```erb
<% if field.segmented? %>
  <%# `control: :segmented` (see the class comment): the fieldset carries the field's id, which its
      error slot and its legend are named after; each segment is a label around its radio. %>
  <%= tag.fieldset id: input_id, class: "m-0 min-w-0 border-0 p-0" do %>
    <legend class="<%= setup_label_class %> mb-1"><%= field.label %></legend>
    <div class="inline-flex overflow-hidden rounded-cs border border-field-line bg-surface">
      <% option_pairs.each do |label, option| %>
        <label for="<%= segment_id(option) %>" class="<%= SEGMENT_CLASS %>">
          <%= radio_button_tag input_name, option, checked?(option), id: segment_id(option), class: "sr-only", required: field.required? %>
          <span><%= label %></span>
        </label>
      <% end %>
    </div>
  <% end %>
<% else %>
  <%= select_tag input_name, options_for_select(option_pairs, value), id: input_id, class: setup_select_class, include_blank: blank_choice, required: field.required? %>
<% end %>
```

In `app/components/admin/ui/field_component.html.erb`, replace the label block:

```erb
    <%# A switch carries its own label beside it (`Admin::Fields::BooleanField`), and a segmented
        control its legend (`Admin::Fields::SelectField`); a second one above either would say it twice. %>
    <% unless field.type == :boolean || field.segmented? %>
      <label class="<%= setup_label_class %> mb-1" for="<%= input_id %>"><%= label_text %></label>
    <% end %>
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `PGGSSENCMODE=disable bin/rails test test/models/content_model/field_options_test.rb test/components/admin/fields/select_field_test.rb test/components/admin/ui/field_component_test.rb test/models/content_model/code_field_test.rb test/lib/admin_design_rules_test.rb test/lib/admin_i18n_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/content_model/definition.rb app/components/admin/fields/select_field.rb app/components/admin/fields/select_field.html.erb app/components/admin/ui/field_component.html.erb test/models/content_model/field_options_test.rb test/components/admin/fields/select_field_test.rb test/components/admin/ui/field_component_test.rb
git commit -m "$(cat <<'EOF'
feat: a select field may be drawn as a segmented control (control: :segmented)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT
EOF
)"
```

---

### Task 2: `max:`, `help:` and `placeholder_from:` for a `:string` field

**Files:**
- Modify: `app/models/content_model/definition.rb`, `app/models/content_model/field_set.rb`
- Modify: `app/components/admin/fields/base.rb`, `app/components/admin/fields/string_field.rb`, `app/components/admin/fields/string_field.html.erb`
- Modify: `app/components/admin/ui/field_component.rb`, `app/components/admin/ui/field_component.html.erb`
- Modify: `app/components/admin/editor_screen/block_card_component.rb`, `app/components/admin/editor_screen/block_card_component.html.erb`
- Create: `app/javascript/controllers/admin/ui/placeholder_from_controller.js`
- Test: `test/models/content_model/field_options_test.rb`, `test/components/admin/fields/string_field_test.rb`, `test/components/admin/ui/field_component_test.rb`, `test/components/admin/editor_screen/block_card_component_test.rb`

**Interfaces:**
- Consumes: `Field#segmented?` and `control:` (Task 1).
- Produces: options `help:` (String, `:string` only), `placeholder_from:` (Symbol naming an earlier `:select`, `:string` only), `max:` on `:string` (positive Integer, characters, `:too_long`); `Field#help` (String or nil); `Admin::Ui::FieldComponent.new(..., placeholder: nil)`; `Admin::Fields::Base#placeholder` (Hash or nil, keys `:text`, `:source`, `:labels`) and `#help_id` (`"<input_id>-help"` or nil); `BlockCardComponent#placeholder_for(field)`; the Stimulus identifier `admin--ui--placeholder-from` with values `source` (String, the choice's input name) and `labels` (Object, value to label).

- [ ] **Step 1: Write the failing tests**

Add to `test/models/content_model/field_options_test.rb`, before the final `end`:

```ruby
  test "a string's help line is a string with something in it, for a string field" do
    assert_equal "Empty: the kind's word.", define { |t| t.field :title, :string, help: "Empty: the kind's word." }.fields.sole.help
    assert_nil define { |t| t.field :title, :string }.fields.sole.help
    [ "", " ", nil, :word ].each do |help|
      assert_raises(ArgumentError, help.inspect) { define { |t| t.field :title, :string, help: help } }
    end
    assert_raises(ArgumentError) { define { |t| t.field :count, :integer, help: "A number." } }
  end

  test "a string takes its placeholder from a select declared before it, and from nothing else" do
    definition = define do |t|
      t.field :kind, :select, options: { "a" => "A" }
      t.field :title, :string, placeholder_from: :kind
    end
    assert_equal :kind, definition.fields.last.options[:placeholder_from]

    error = assert_raises(ArgumentError) { define { |t| t.field :title, :string, placeholder_from: :kind } }
    assert_includes error.message, "declared before"
    assert_raises(ArgumentError) { define { |t| t.field(:name, :string); t.field :title, :string, placeholder_from: :name } }
    assert_raises(ArgumentError) { define { |t| t.field(:kind, :select, options: %w[a]); t.field :body, :text, placeholder_from: :kind } }
  end

  # Plan ruling 2: `max:` on a string was read by nothing. It counts
  # characters, as for a code field, and is Rails' own too_long.
  test "a string longer than max is too long, counted in characters, and the text is still in the object" do
    definition = define { |t| t.field :title, :string, max: 5 }
    fields = ->(value) { ContentModel::FieldSet.for(definition).new({}).assign("title" => value) }

    over = fields.("abcdef")
    assert_not over.valid?
    assert_equal [ "is too long (maximum is 5 characters)" ], over.errors[:title]
    assert_equal "abcdef", over.title
    assert fields.("abcde").valid?
    assert fields.("ééééé").valid?, "characters, not bytes"
    assert fields.("  abcde  ").valid?, "counted after the value is stripped, as it is stored"
    assert_raises(ArgumentError) { define { |t| t.field :title, :string, max: 0 } }
    assert_raises(ArgumentError) { define { |t| t.field :title, :string, max: "80" } }
  end

  # A block's settings are validated in the default language only
  # (`ContentBlock#settings_are_valid`), so a translated string's length is
  # checked in every language the object holds.
  test "a translated string over max is too long in whichever language holds it" do
    definition = define { |t| t.field :title, :string, translated: true, max: 5 }
    object = ContentModel::FieldSet.for(definition).new({}, { "en" => { "title" => "short" }, "de" => { "title" => "zu lange" } }, locale: "en")

    assert_not object.valid?
    assert_equal [ "is too long (maximum is 5 characters)" ], object.errors[:title], "said once"
    assert ContentModel::FieldSet.for(definition).new({}, { "en" => { "title" => "short" }, "de" => { "title" => "kurz" } }, locale: "en").valid?
  end
```

Add to `test/components/admin/fields/string_field_test.rb`, before the final `end`:

```ruby
  test "a placeholder handed over is the input's, and one that follows a choice wires the script with the choice's name and labels" do
    field = Field.new(name: "title", type: :string, options: { placeholder_from: :kind })
    render_inline Admin::Fields::StringField.new(field:, form_name: "block[settings]", value: nil, locale: "en", id_prefix: "block-7",
      placeholder: { text: "Tip", source: "block[settings][kind]", labels: { "note" => "Note", "tip" => "Tip" } })

    input = page.find("input#block-7-title")
    assert_equal "Tip", input[:placeholder]
    assert_equal "admin--ui--placeholder-from", input["data-controller"]
    assert_equal "block[settings][kind]", input["data-admin--ui--placeholder-from-source-value"]
    assert_equal({ "note" => "Note", "tip" => "Tip" }, JSON.parse(input["data-admin--ui--placeholder-from-labels-value"]))
  end

  test "without a placeholder or a help line the input has neither, and no script" do
    field = Field.new(name: "title", type: :string, options: {})
    render_inline Admin::Fields::StringField.new(field:, form_name: "post[fields]", value: nil, locale: "en")

    assert_no_selector "input[placeholder], input[aria-describedby], input[data-controller]"
  end
```

Add to `test/components/admin/ui/field_component_test.rb`, before the final `end`:

```ruby
  test "a help line stands under the input and describes it" do
    field = Field.new(name: "title", type: :string, options: { help: "Empty: the kind's word." })
    render_inline Admin::Ui::FieldComponent.new(field:, form_name: "block[settings]", value: nil, locale: "en", id_prefix: "block-7")

    assert_selector "input#block-7-title[aria-describedby='block-7-title-help']"
    assert_selector "p#block-7-title-help.text-meta", exact_text: "Empty: the kind's word."
  end

  test "a placeholder handed to the field reaches its input" do
    field = Field.new(name: "title", type: :string, options: {})
    render_inline Admin::Ui::FieldComponent.new(field:, form_name: "block[settings]", value: nil, locale: "en", placeholder: { text: "Note" })

    assert_selector "input[placeholder='Note']"
  end
```

Add to `test/components/admin/editor_screen/block_card_component_test.rb`, before the final `end`:

```ruby
  # Plan ruling 3: a field that takes its placeholder from a select shows the
  # label of the choice stored, read from the default language, and carries
  # what the browser needs to follow a new choice before it is saved.
  def with_hint_type
    BlockTypes.register(:test_hint) do |t|
      TestTypes.declare(t)
      t.label "Hint"
      t.field :tone, :select, options: { "calm" => "Calm", "loud" => "Loud" }, default: "calm", control: :segmented
      t.field :headline, :string, translated: true, placeholder_from: :tone, help: "Empty: the tone's word heads it."
    end
    yield
  ensure
    Rails.application.reloader.prepare!
  end

  test "a field that takes its placeholder from a select shows the stored choice's label, on the default tab and on a translation tab" do
    with_locales(%w[en de], default: "en") do
      with_hint_type do
        page = create_page(title: "Hints")
        block = page.content_blocks.create!(block_type: "test_hint", position: 0, settings: { "tone" => "loud" })

        render_card(block, page: page)
        input = self.page.find("input[name='block[settings][headline]']")
        assert_equal "Loud", input[:placeholder]
        assert_equal "block[settings][tone]", input["data-admin--ui--placeholder-from-source-value"]
        assert_equal({ "calm" => "Calm", "loud" => "Loud" }, JSON.parse(input["data-admin--ui--placeholder-from-labels-value"]))
        assert_selector "p#block-#{block.id}-headline-help", exact_text: "Empty: the tone's word heads it."
        assert_selector "fieldset#block-#{block.id}-tone input#block-#{block.id}-tone-loud[checked]"

        render_inline Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "de")
        assert_equal "Loud", self.page.find("input[name='block[settings][headline]']")[:placeholder]
        assert_no_selector "input[type=radio]", visible: :all
      end
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `PGGSSENCMODE=disable bin/rails test test/models/content_model/field_options_test.rb test/components/admin/fields/string_field_test.rb test/components/admin/ui/field_component_test.rb test/components/admin/editor_screen/block_card_component_test.rb`
Expected: FAIL: "unknown field option(s) [:help]" / "[:placeholder_from]", "unknown keyword: :placeholder", and the too-long assertions (`max:` on a string is read by nothing yet).

- [ ] **Step 3: Implement the schema half**

In `app/models/content_model/definition.rb`, extend `OPTIONS` and its comment, and the `Field`:

```ruby
    # `help:` is a line under a string field in CS Studio (the Note block's
    # title: what an empty one does), and `placeholder_from:` names a select
    # declared BEFORE the string whose chosen label is the string's
    # placeholder (the Note block's title shows the kind's word, design
    # answer B3). Both are literals of the type's definition, as `label:` is.
    # `max:` on a string counts characters, as on a code field.
    OPTIONS = %i[required default min max translated options of blank label control help placeholder_from].freeze
```

```ruby
      # The line under the field in CS Studio, or nil.
      def help = options[:help].presence
```

In `#field`, after the `control:` refusals:

```ruby
      raise ArgumentError, "`help:` is a line under a string field, written as a String" if options.key?(:help) && !(type == :string && options[:help].is_a?(String) && options[:help].strip != "")
      if options.key?(:placeholder_from)
        source = @fields.find { |candidate| candidate.name == options[:placeholder_from].to_s }
        raise ArgumentError, "`placeholder_from:` is for a string field and names a select field declared before it" unless type == :string && source&.type == :select
      end
      raise ArgumentError, "`max:` on a string field is a number of characters, a positive Integer" if type == :string && options.key?(:max) && !(options[:max].is_a?(Integer) && options[:max].positive?)
```

In `app/models/content_model/field_set.rb`, add the string limit beside the code limit inside `validate_fields` (after the `:code` line):

```ruby
          errors.add(field.name, :too_long, count: field.options[:max]) if field.type == :string && field.options[:max] && value.length > field.options[:max]
```

and a second validation, declared under `validate :validate_fields`:

```ruby
      # A translated string's limit in every language this object holds, not
      # only its own: a block's settings are validated in the default
      # language alone (`ContentBlock#settings_are_valid`), and a German
      # title would otherwise be stored at any length (note block plan,
      # ruling 2). One error per field, however many languages are over.
      validate :validate_lengths_in_every_language
```

and, as a private method below `code_limit`:

```ruby
      def validate_lengths_in_every_language
        definition.fields.each do |field|
          max = field.options[:max]
          next unless field.type == :string && field.translated? && max
          next if errors.added?(field.name, :too_long, count: max)

          over = @translations.values.any? { |values| cast(field, values.to_h[field.name]).to_s.length > max }
          errors.add(field.name, :too_long, count: max) if over
        end
      end
```

- [ ] **Step 4: Implement the drawing half**

`app/components/admin/fields/base.rb`: add `placeholder: nil` to the signature, keep it, and add `help_id`:

```ruby
      def initialize(field:, form_name:, value:, original: nil, locale: nil, errors: [], id_prefix: nil, placeholder: nil)
        @field = field
        @form_name = form_name
        @value = value
        @original = original
        @locale = locale
        @errors = errors
        @id_prefix = id_prefix || Admin::Ui::FieldComponent.dom_id_prefix(form_name)
        @placeholder = placeholder
      end

      private

      attr_reader :field, :form_name, :value, :original, :locale, :errors, :id_prefix, :placeholder

      def input_name = "#{form_name}[#{field.name}]"

      def input_id = "#{id_prefix}-#{field.name}"

      # The id of the help line `Admin::Ui::FieldComponent` draws under a
      # field whose type gives one (`help:`), for the input's `aria-describedby`.
      def help_id = field.help ? "#{input_id}-help" : nil
```

(Add one sentence to the class comment: "`placeholder:` is what the caller hands a field that shows one (`Admin::Fields::StringField`); every other type ignores it.")

Replace `app/components/admin/fields/string_field.rb`:

```ruby
module Admin
  module Fields
    # A single-line text input (spec §4.3), for `:string` fields.
    #
    # `placeholder` is what the block card hands over (`BlockCardComponent
    # #placeholder_for`): `text:`, and for a field whose type says
    # `placeholder_from:` the input name of that select (`source:`) and its
    # value-to-label Hash (`labels:`), which `admin--ui--placeholder-from`
    # reads to follow a choice before it is saved. A field with `help:` is
    # described by the line `Admin::Ui::FieldComponent` draws under it.
    class StringField < Base
      def placeholder_text = placeholder&.dig(:text)

      def placeholder_data
        return {} unless placeholder&.dig(:source)

        { controller: "admin--ui--placeholder-from",
          admin__ui__placeholder_from_source_value: placeholder[:source],
          admin__ui__placeholder_from_labels_value: placeholder[:labels].to_json }
      end
    end
  end
end
```

Replace `app/components/admin/fields/string_field.html.erb`:

```erb
<%= tag.input type: "text", name: input_name, id: input_id, value: value, class: setup_input_class, required: field.required?,
      placeholder: placeholder_text, aria: { describedby: help_id }, data: placeholder_data %>
```

`app/components/admin/ui/field_component.rb`: add `placeholder: nil` to `initialize` (stored as `@placeholder`, added to the private `attr_reader` list), pass it on, and name the help line:

```ruby
      def input_component
        "Admin::Fields::#{field.type.to_s.camelize}Field".constantize.new(
          field: field, form_name: form_name, value: value, original: original, locale: locale, errors: errors, id_prefix: id_prefix, placeholder: placeholder
        )
      end

      # The help line under the input, named for its `aria-describedby`.
      def help_id = "#{input_id}-help"
```

In `app/components/admin/ui/field_component.html.erb`, directly after `<%= render input_component %>`:

```erb
    <% if field.help %>
      <p id="<%= help_id %>" class="mt-1 text-sm text-meta"><%= field.help %></p>
    <% end %>
```

`app/components/admin/editor_screen/block_card_component.rb`, a public method beside `value_for`:

```ruby
      # What a schema field that takes its placeholder from a select
      # (`placeholder_from:`, the Note block's title) shows: the label of the
      # choice stored now, which is the same in every language and so read
      # from the default one, and the select's input name and labels, for
      # `admin--ui--placeholder-from` to follow a new choice before it is
      # saved. Nil for every other field. A translation tab draws no input
      # for the select, so there the placeholder stays the stored choice's.
      def placeholder_for(field)
        source = field.options[:placeholder_from] or return nil
        choice = definition.fields.find { |candidate| candidate.name == source.to_s } or return nil
        options = choice.options[:options]
        labels = options.is_a?(Hash) ? options.transform_keys(&:to_s) : Array(options).to_h { |option| [ option.to_s, option.to_s ] }
        { text: labels[default_settings_object&.public_send(choice.name).to_s], source: "block[settings][#{choice.name}]", labels: labels }
      end
```

In `app/components/admin/editor_screen/block_card_component.html.erb`, in the `other_schema_fields.each` loop, add the keyword:

```erb
          <%= render Admin::Ui::FieldComponent.new(
                field: field, form_name: "block[settings]",
                value: value_for(field), original: original_for(field), locale: locale,
                errors: field_errors(field), id_prefix: error_prefix, placeholder: placeholder_for(field), **translation(field.name)
              ) %>
```

Create `app/javascript/controllers/admin/ui/placeholder_from_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"

// The placeholder of a text field that shows the label of another field's
// choice (`placeholder_from:` in a type's schema; the Note block's title
// shows the kind's word, design answer B3). The server draws the placeholder
// of the choice stored; this follows a new choice before its save, from the
// labels the server handed over, so the script holds no words.
//
// It only reads: it listens for `change` on the field's own form (a radio
// and a select both bubble one) and writes nothing but the placeholder, so
// it has nothing to tell autosave and is no action of a held form (it uses
// no `data-action`). At connect it reads the choice the form holds now, so
// a page drawn again from Turbo's copy is right; where the form holds no
// such control (a translation tab, where the choice is a shared field) it
// leaves the server's placeholder alone.
export default class extends Controller {
  static values = { source: String, labels: Object }

  connect() {
    this.form = this.element.form
    this.follow = this.follow.bind(this)
    this.form?.addEventListener("change", this.follow)
    const control = this.form?.elements.namedItem(this.sourceValue)
    if (control) this.show(control.value)
  }

  disconnect() {
    this.form?.removeEventListener("change", this.follow)
  }

  follow(event) {
    if (event.target.name === this.sourceValue) this.show(event.target.value)
  }

  show(value) {
    this.element.placeholder = this.labelsValue[value] ?? ""
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `PGGSSENCMODE=disable bin/rails test test/models/content_model/field_options_test.rb test/models/content_model/field_set_test.rb test/models/content_model/code_field_test.rb test/components/admin/fields test/components/admin/ui/field_component_test.rb test/components/admin/editor_screen/block_card_component_test.rb test/components/admin/editor_screen/block_samples_card_test.rb test/lib/source_layout_test.rb test/lib/inline_handlers_test.rb test/lib/admin_i18n_test.rb test/models/content_block_test.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/models/content_model app/components/admin/fields app/components/admin/ui/field_component.rb app/components/admin/ui/field_component.html.erb app/components/admin/editor_screen/block_card_component.rb app/components/admin/editor_screen/block_card_component.html.erb app/javascript/controllers/admin/ui/placeholder_from_controller.js test/models/content_model/field_options_test.rb test/components/admin/fields/string_field_test.rb test/components/admin/ui/field_component_test.rb test/components/admin/editor_screen/block_card_component_test.rb
git commit -m "$(cat <<'EOF'
feat: a string field takes max:, a help line, and a placeholder that follows a select

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT
EOF
)"
```

---

### Task 3: a block type's icon may follow its block (`icon … for_block:`)

**Files:**
- Modify: `app/models/content_model/block_type_definition.rb` (`ICONS`, `#icon`, `#icon_follows_block?`, `#icon_for`, `#refuse_outside!`)
- Modify: `app/views/admin/shared/_icon.html.erb`
- Modify: `app/components/admin/editor_screen/block_icon_component.rb`
- Modify: `app/components/admin/editor_screen/block_card_component.html.erb` (the icon's line), `app/components/admin/editor_screen/block_tile_component.rb` (`block_icon`)
- Modify: `app/controllers/admin/content_blocks_controller.rb` (`#update`, `#block_icon_streams`)
- Test: `test/models/content_model/block_type_definition_test.rb`, `test/components/admin/editor_screen/block_icon_component_test.rb`, `test/integration/admin/content_blocks_test.rb`

**Interfaces:**
- Consumes: the contrast branch's block icons (`BlockTypeDefinition::ICONS`, `t.icon`, `BlockIconComponent` with `PLACES` `picker`, `card`, `tile`), merged before Task 1.
- Produces: `ContentModel::BlockTypeDefinition::ICONS` ending `… columns_2 info lightbulb circle_alert triangle_alert`; `#icon(name = nil, for_block: nil)` (`for_block:` a callable taking one block, answering a name from `ICONS`); `#icon_follows_block?` (Boolean); `#icon_for(block)` (the block's name where the type's icon follows it and a block is handed in, else the type's; a name off the list raises `ArgumentError` naming the list); `Admin::EditorScreen::BlockIconComponent.new(definition:, place:, block: nil)` and `.dom_id(block, place)` (`"block-<id>-icon-<place>"`), the span carrying that id only for a type whose icon follows its block; the card's head and the tile hand their block; `Admin::ContentBlocksController#block_icon_streams(block)`, replacing `block-<id>-icon-card` and `block-<id>-icon-tile` in every answer to a save that went through, for such a type only. Icon names `:info`, `:lightbulb`, `:circle_alert`, `:triangle_alert` in `admin/shared/_icon`. `TileSummaryComponent` is unchanged (plan ruling 12).

- [ ] **Step 1: Write the failing tests**

In `test/models/content_model/block_type_definition_test.rb`, in "a block type's icon is one CS Studio draws, or none", replace the message assertion:

```ruby
    assert_match(/\Ax: icon is one of pilcrow, image, code_xml, posts, columns_2, info, lightbulb, circle_alert, triangle_alert/, error.message)
```

and add after that test:

```ruby
  # Note block plan, ruling 12: the Note's icon in the picker is its type's
  # (`info`), and on a block's card and tile its kind's. A callable answers
  # it for each block, from the same closed list.
  test "a block type's icon may follow its block: the callable answers one of the list for each block, and the type's own stands where there is no block" do
    definition = ContentModel::BlockTypeDefinition.new("x")
    definition.icon :info, for_block: ->(block) { block.settings["tone"] == "loud" ? "triangle_alert" : "info" }

    assert_equal "info", definition.icon
    assert definition.icon_follows_block?
    assert_equal "triangle_alert", definition.icon_for(ContentBlock.new(settings: { "tone" => "loud" }))
    assert_equal "info", definition.icon_for(ContentBlock.new(settings: {}))
    assert_equal "info", definition.icon_for(nil), "the picker has no block"

    plain = ContentModel::BlockTypeDefinition.new("y").tap { |type| type.icon :pilcrow }
    assert_not plain.icon_follows_block?
    assert_equal "pilcrow", plain.icon_for(ContentBlock.new(settings: { "tone" => "loud" }))
    assert_nil ContentModel::BlockTypeDefinition.new("z").icon_for(ContentBlock.new), "a type with no icon has none for its blocks"

    error = assert_raises(ArgumentError) { ContentModel::BlockTypeDefinition.new("x").icon :info, for_block: "triangle_alert" }
    assert_includes error.message, "callable"
  end

  test "a block's icon off the list raises, naming the list, and never reaches the page as markup" do
    definition = ContentModel::BlockTypeDefinition.new("x")
    definition.icon :info, for_block: ->(_block) { "<svg onload=x>" }

    error = assert_raises(ArgumentError) { definition.icon_for(ContentBlock.new) }
    assert_match(/\Ax: its icon for a block is one of pilcrow, .*, triangle_alert/, error.message)
  end

  # An outside type's callable would be asked on every card and tile of the
  # editor, where a raise is a 500: not yet (plan ruling 12).
  test "a block type from outside names one icon for all its blocks: for_block is refused at registration" do
    definition = ContentModel::BlockTypeDefinition.new("gallery/flag")
    definition.icon :info, for_block: ->(_block) { "info" }

    error = assert_raises(ArgumentError) { definition.finalize! }
    assert_match(/\Agallery\/flag: a block type from outside names one icon/, error.message)
  end
```

Add to `test/components/admin/editor_screen/block_icon_component_test.rb`, before the final `end`:

```ruby
  # Note block plan, ruling 12: a type whose icon follows its block.
  def with_flag_type
    BlockTypes.register(:test_flag) do |t|
      TestTypes.declare(t)
      t.label "Flag"
      t.field :tone, :select, options: %w[calm loud], default: "calm"
      t.icon "info", for_block: ->(block) { block.settings["tone"] == "loud" ? "triangle_alert" : "info" }
    end
    yield BlockTypes.fetch(:test_flag)
  ensure
    Rails.application.reloader.prepare!
  end

  test "a type whose icon follows its block draws the block's own on its card and its tile, under an id a save's answer replaces, and the type's in the picker" do
    with_flag_type do |flag|
      block = root_page.content_blocks.create!(block_type: "test_flag", position: 0, settings: { "tone" => "loud" })

      render_inline Admin::EditorScreen::BlockIconComponent.new(definition: flag, place: :card, block: block)
      assert_selector "span#block-#{block.id}-icon-card[data-block-icon=triangle_alert][aria-hidden=true][class~='text-dim'] svg[class~='size-3.5']"

      render_inline Admin::EditorScreen::BlockIconComponent.new(definition: flag, place: :tile, block: block)
      assert_selector "span#block-#{block.id}-icon-tile[data-block-icon=triangle_alert][class~='text-meta'] svg[class~='size-3']"

      render_inline Admin::EditorScreen::BlockIconComponent.new(definition: flag, place: :picker)
      assert_selector "span[data-block-icon=info]:not([id])"
      assert_equal "block-#{block.id}-icon-tile", Admin::EditorScreen::BlockIconComponent.dom_id(block, :tile)
    end
  end

  test "a type whose icon does not follow its block draws it with no id, also when it is handed a block" do
    block = root_page.content_blocks.create!(block_type: "code", position: 0)
    render_inline Admin::EditorScreen::BlockIconComponent.new(definition: BlockTypes.fetch(:code), place: :card, block: block)

    assert_selector "span[data-block-icon=code_xml]:not([id])", count: 1
  end

  test "a built-in's icon for a block that is not on the list raises, naming the list" do
    with_flag_type do |flag|
      flag.icon "info", for_block: ->(_block) { "<svg onload=x>" }
      block = root_page.content_blocks.create!(block_type: "test_flag", position: 0)

      error = assert_raises(ArgumentError) { render_inline Admin::EditorScreen::BlockIconComponent.new(definition: flag, place: :card, block: block) }
      assert_includes error.message, "info, lightbulb, circle_alert, triangle_alert"
    end
  end
```

Add to `test/integration/admin/content_blocks_test.rb`, before the final `end`:

```ruby
  # Note block plan, ruling 12: neither a card's head nor a tile's face is
  # re-rendered by a save, so an icon that follows its block is replaced by
  # id in the save's answer; any other type's answer carries no icon.
  test "a save of a block whose icon follows it redraws the icon on its card and its tile; another type's save redraws none" do
    BlockTypes.register(:test_flag) do |t|
      TestTypes.declare(t)
      t.label "Flag"
      t.field :tone, :select, options: %w[calm loud], default: "calm"
      t.icon "info", for_block: ->(block) { block.settings["tone"] == "loud" ? "triangle_alert" : "info" }
    end
    flag = @page.content_blocks.create!(block_type: "test_flag", position: 0)

    patch "#{blocks_path}/#{flag.id}", params: { block: { settings: { tone: "loud" } }, base_updated_at: flag.reload.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[action='replace'][target='block-#{flag.id}-icon-card'] template span#block-#{flag.id}-icon-card[data-block-icon='triangle_alert']"
    assert_select "turbo-stream[action='replace'][target='block-#{flag.id}-icon-tile'] template span#block-#{flag.id}-icon-tile[data-block-icon='triangle_alert']"

    code = @page.content_blocks.create!(block_type: "code", position: 1)
    patch "#{blocks_path}/#{code.id}", params: { block: { settings: { filename: "a.rb" } }, base_updated_at: code.reload.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[target^='block-#{code.id}-icon-']", count: 0
  ensure
    Rails.application.reloader.prepare!
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `PGGSSENCMODE=disable bin/rails test test/models/content_model/block_type_definition_test.rb test/components/admin/editor_screen/block_icon_component_test.rb test/integration/admin/content_blocks_test.rb`
Expected: FAIL: "unknown keyword: :for_block", `NoMethodError: undefined method 'icon_for'`, "unknown keyword: :block", the message without the four new names, and no icon stream in the answer.

- [ ] **Step 3: Implement the declaration**

In `app/models/content_model/block_type_definition.rb`, replace the `ICONS` comment and constant:

```ruby
    # The icons a block type may name (contrast and buttons spec, C2 and
    # Ruling 6): each is a branch of CS Studio's icon partial
    # (`app/views/admin/shared/_icon.html.erb`, Lucide, spelt as the
    # partial's symbol: `code_xml` for Lucide's `code-xml`), which a model
    # may not name; `block_icon_component_test.rb` draws every one. A type
    # names one or none; an outside type picks from the same list. The last
    # four are the Note block's kinds (note block plan, rulings 11 and 12),
    # which its blocks' cards and tiles draw through `for_block:`.
    ICONS = %w[pilcrow image code_xml posts columns_2 info lightbulb circle_alert triangle_alert].freeze
```

Replace `#icon` and add the two readers after it:

```ruby
    # The icon CS Studio draws for the type in the picker, on a card's head
    # and on a section's tile: one of `ICONS`, or none. `for_block:` is a
    # callable taking one block and answering one of `ICONS`: a block's card
    # and tile draw what it answers for that block, in place of the type's
    # (the Note block's kind; note block plan, ruling 12). The picker, which
    # has no block, draws the type's, so the type's should be the icon of
    # the value a new block starts with.
    def icon(name = nil, for_block: nil)
      return @icon if name.nil?
      refuse "icon is one of #{ICONS.join(", ")} (the icons CS Studio draws for a block type): #{name.inspect}" unless ICONS.include?(name.to_s)
      refuse "`icon for_block:` is a callable taking the block and answering one of #{ICONS.join(", ")}" unless for_block.nil? || for_block.respond_to?(:call)

      @icon_for_block = for_block
      @icon = name.to_s
    end

    # Whether a block's card and tile draw an icon of the block's own
    # (`for_block:`), which a save then has to redraw
    # (`Admin::ContentBlocksController#block_icon_streams`).
    def icon_follows_block? = !@icon_for_block.nil?

    # The icon one block of the type is drawn with: what `for_block:`
    # answers for it, else the type's own (nil for a type with none). A name
    # off the list raises, naming the list: only a built-in may declare
    # `for_block:` (`refuse_outside!`), so a wrong answer is this
    # repository's fault, and the name reaches the icon partial as a symbol,
    # never as markup.
    def icon_for(block)
      return @icon unless icon_follows_block? && block

      name = @icon_for_block.call(block).to_s
      refuse "its icon for a block is one of #{ICONS.join(", ")}: #{name.truncate(40).inspect}" unless ICONS.include?(name)

      name
    end
```

In `#refuse_outside!`, directly after the `read_only_actions` refusal:

```ruby
      # A gem's callable would be asked on every card and tile of the editor,
      # where one that raised is a 500; the tile's rescue for a gem's
      # `summary` is not repeated for an icon until a gem asks for one.
      if icon_follows_block?
        refuse "a block type from outside names one icon for all its blocks: `icon for_block:` is the CMS's own yet, " \
               "because a callable that raised would fail every editor page holding a block of the type"
      end
```

and add to the class comment on `refuse_outside!`, after "so any action it named would be one of the CMS's, kept alive in every held form.": "Nor `icon … for_block:`, for the reason written at its refusal."

- [ ] **Step 4: Implement the drawing and the save's answer**

In `app/views/admin/shared/_icon.html.erb`, after the `:columns_2` branch and before `<% else`:

```erb
<%# The Note block's four kinds (note block spec, decision 2; plan ruling 11), Lucide, drawn by
    `Admin::EditorScreen::BlockIconComponent` on a note's card and tile (`icon for_block:`), and
    `info` in the picker as the Note type's own. %>
<% when :info %>
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class="<%= local_assigns.fetch(:size, "size-5") %> shrink-0" aria-hidden="true" focusable="false"><circle cx="12" cy="12" r="10" /><path stroke-linecap="round" stroke-linejoin="round" d="M12 16v-4M12 8h.01" /></svg>
<% when :lightbulb %>
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class="<%= local_assigns.fetch(:size, "size-5") %> shrink-0" aria-hidden="true" focusable="false"><path stroke-linecap="round" stroke-linejoin="round" d="M15 14c.2-1 .7-1.7 1.5-2.5 1-.9 1.5-2.2 1.5-3.5A6 6 0 0 0 6 8c0 1 .2 2.2 1.5 3.5.7.7 1.3 1.5 1.5 2.5M9 18h6M10 22h4" /></svg>
<% when :circle_alert %>
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class="<%= local_assigns.fetch(:size, "size-5") %> shrink-0" aria-hidden="true" focusable="false"><circle cx="12" cy="12" r="10" /><path stroke-linecap="round" stroke-linejoin="round" d="M12 8v4M12 16h.01" /></svg>
<% when :triangle_alert %>
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class="<%= local_assigns.fetch(:size, "size-5") %> shrink-0" aria-hidden="true" focusable="false"><path stroke-linecap="round" stroke-linejoin="round" d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3M12 9v4M12 17h.01" /></svg>
```

Replace `app/components/admin/editor_screen/block_icon_component.rb`:

```ruby
module Admin
  module EditorScreen
    # A block type's icon where the editor names the type (contrast and
    # buttons spec, C2): 16px dim before the name in the picker, 14px dim
    # between a card's handle and its name, 12px meta before a tile's
    # summary, where it stands in for the name. Decoration: the name is
    # always beside it, on the tile as `sr-only` text. A type that names no
    # icon draws nothing (Ruling 7).
    #
    # A TYPE WHOSE ICON FOLLOWS ITS BLOCK (`icon … for_block:`, the Note
    # block's kind; note block plan, ruling 12) is drawn with the block's own
    # on its card and its tile, which hand their block in, and with the
    # type's in the picker, which has none. Only such an icon carries an id
    # (`dom_id`): a save's answer replaces it
    # (`Admin::ContentBlocksController#block_icon_streams`), because neither
    # the card's head nor the tile's face is re-rendered by a save.
    class BlockIconComponent < AdminComponent
      PLACES = { picker: %w[size-4 text-dim], card: %w[size-3.5 text-dim], tile: %w[size-3 text-meta] }.freeze

      def self.dom_id(block, place) = "#{Admin::EditorScreen::BlockCardComponent.error_prefix(block)}-icon-#{place}"

      def initialize(definition:, place:, block: nil)
        raise ArgumentError, "unknown place #{place.inspect}" unless PLACES.key?(place)

        @definition = definition
        @place = place
        @block = block
      end

      def render? = icon_name.present?

      def call
        size, colour = PLACES.fetch(@place)
        # `strip`: the partial's own line breaks would land in a button's text.
        tag.span(helpers.render("admin/shared/icon", name: icon_name.to_sym, size: size).strip.html_safe,
          id: (self.class.dom_id(@block, @place) if @block && @definition.icon_follows_block?),
          class: "inline-flex shrink-0 #{colour}", aria: { hidden: true }, data: { block_icon: icon_name })
      end

      private

      # The block's own where the type's icon follows it, else the type's;
      # always a name from `BlockTypeDefinition::ICONS` (`icon_for` raises
      # for any other).
      def icon_name = @icon_name ||= @definition&.icon_for(@block)
    end
  end
end
```

In `app/components/admin/editor_screen/block_card_component.html.erb`, the icon's line hands over the block:

```erb
    <%= render Admin::EditorScreen::BlockIconComponent.new(definition: definition, place: :card, block: block) unless unavailable? %>
```

In `app/components/admin/editor_screen/block_tile_component.rb`, `block_icon` hands over the block (and its comment gains one sentence: "A type whose icon follows its block (the Note's kind) shows the block's own."):

```ruby
      def block_icon = @block_icon ||= Admin::EditorScreen::BlockIconComponent.new(definition: block.definition, place: :tile, block: block)
```

In `app/controllers/admin/content_blocks_controller.rb`, `#update`, directly after `streams << tile_summary_stream(result) if block.section_id`:

```ruby
      streams.concat(block_icon_streams(result.record)) if result.ok? && block.definition&.icon_follows_block?
```

and, as a private method directly after `#tile_summary_stream`:

```ruby
    # A type whose icon follows its block (`icon … for_block:`, the Note
    # block's kind; note block plan, ruling 12) has the icon redrawn on the
    # card's head and on the tile with every answer to a save that went
    # through, as the tile's line is: neither is re-rendered by a save
    # otherwise, and a kind chosen and saved would keep the old kind's icon
    # until a reload. Only the icon's span is replaced, never the head or the
    # face around it (the face may hold the focus). Replacing an id that is
    # not on the page (a block at the top level has no tile) does nothing.
    def block_icon_streams(block)
      %i[card tile].map do |place|
        turbo_stream.replace(Admin::EditorScreen::BlockIconComponent.dom_id(block, place),
          Admin::EditorScreen::BlockIconComponent.new(definition: block.definition, place: place, block: block))
      end
    end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `PGGSSENCMODE=disable bin/rails test test/models/content_model/block_type_definition_test.rb test/components/admin/editor_screen test/integration/admin/content_blocks_test.rb test/lib/admin_design_rules_test.rb test/lib/dependency_direction_test.rb test/lib/content_spiel/plugins_test.rb`
Expected: PASS ("every icon a block type may name is drawn by the icon partial" now draws the four new names too).

- [ ] **Step 6: Commit**

```bash
git add app/models/content_model/block_type_definition.rb app/views/admin/shared/_icon.html.erb app/components/admin/editor_screen/block_icon_component.rb app/components/admin/editor_screen/block_card_component.html.erb app/components/admin/editor_screen/block_tile_component.rb app/controllers/admin/content_blocks_controller.rb test/models/content_model/block_type_definition_test.rb test/components/admin/editor_screen/block_icon_component_test.rb test/integration/admin/content_blocks_test.rb
git commit -m "$(cat <<'EOF'
feat: a block type's icon may follow its block on the card and the tile (icon for_block:)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT
EOF
)"
```

---

### Task 4: the Note type, its public component and its tile

**Files:**
- Generate, then modify: `app/models/block_types/note.rb`, `config/initializers/types.rb`, `app/components/blocks/note_component.rb`, `app/components/blocks/note_component.html.erb`, `app/assets/tailwind/themes/default/note.css` (generated, left as is until Task 5 except its GENERATED line), `config/locales/public.en.yml`, `config/locales/admin/editor_screen.en.yml`, `test/components/previews/blocks/note_component_preview.rb`, `test/models/block_types/note_test.rb`, `test/components/blocks/note_component_test.rb`
- Modify: `test/support/contract_ledger.rb` (`COMPONENTS`), `docs/reference/theming.md` (the Components table)
- Modify: `test/values/theme/contract_test.rb`, `test/components/admin/editor_screen/tile_summary_component_test.rb`, `test/components/admin/editor_screen/block_tile_component_test.rb`, `test/components/admin/editor_screen/block_icon_component_test.rb` ("every built-in block type declares its icon")

**Interfaces:**
- Consumes: `control: :segmented` (Task 1); `max:`, `help:`, `placeholder_from:` (Task 2); `icon … for_block:`, `#icon_for`, `BlockIconComponent.new(…, block:)` and `.dom_id` (Task 3).
- Produces: `BlockTypes::Note::KINDS` (`{ "note" => "Note", "tip" => "Tip", "important" => "Important", "warning" => "Warning" }`), `BlockTypes::Note::ICONS` (Lucide's names: `{ "note" => "info", "tip" => "lightbulb", "important" => "circle-alert", "warning" => "triangle-alert" }`), `BlockTypes::Note::DEFAULT = "note"`, `BlockTypes::Note::TITLE_LENGTH = 80`, `BlockTypes::Note.kind_of(value) -> String`, `BlockTypes::Note.studio_icon(block) -> String` (the partial's spelling: `info`, `lightbulb`, `circle_alert`, `triangle_alert`), `BlockTypes::Note.summary(block, locale:) -> Array` (text parts only); the type's icon `info`, following the block's kind on its card and tile; `Blocks::NoteComponent` (private `kind`, `heading`, `titled?`, `word`, `icon`, `body`); markup `aside.content-block.content-block--note.content-block--note-<kind>[aria-labelledby=note-<id>-heading]` > `h3.note-head#note-<id>-heading` (`svg.note-icon[data-icon]` + `span`, which holds `span.note-kind` with "<word>: " only when `titled?`, then `heading`) + `div.note-body.cs-prose`; keys `public.blocks.note.kinds.<kind>` and `admin.components.editor_screen.tile_summary.types.note.empty`.

- [ ] **Step 1: Generate the skeleton**

Run: `PGGSSENCMODE=disable bin/rails generate block_type note`
Expected: it writes the seven files and the three inserted lines the reference lists ("1. Generate"); `git status` shows them.

Then move the inserted line in `config/initializers/types.rb` (plan ruling 9) so the block reads:

```ruby
    BlockTypes::RichText.register
    BlockTypes::Image.register
    BlockTypes::Code.register
    BlockTypes::Note.register
    BlockTypes::PostList.register
    BlockTypes::Section.register
    # bin/rails generate block_type adds a built-in's line above this one.
```

- [ ] **Step 2: Write the failing tests**

Replace `test/models/block_types/note_test.rb`:

```ruby
require "test_helper"

# The Note block's declaration (note block spec, "The data"): a kind in the
# settings, a translated title, the body column; the eight names of its
# template, its sixteen tokens and its stylesheet are the theme contract's;
# its icon in CS Studio is `info`, and its kind's on a card and a tile.
class BlockTypes::NoteTest < ActiveSupport::TestCase
  test "a note is a kind, a translated title and a text, nothing required, the kind a segmented choice of four that starts as a Note" do
    note = BlockTypes.fetch(:note)

    assert_equal "Note", note.label
    assert_equal [ %w[kind select], %w[title string] ], note.fields.map { |field| [ field.name, field.type.to_s ] }
    kind, title = note.fields
    assert_equal BlockTypes::Note::KINDS, kind.options[:options]
    assert_equal({ "note" => "Note", "tip" => "Tip", "important" => "Important", "warning" => "Warning" }, BlockTypes::Note::KINDS)
    assert_equal "note", kind.options[:default]
    assert kind.segmented?
    assert_not kind.translated?
    assert title.translated?
    assert_equal 80, title.options[:max]
    assert_equal :kind, title.options[:placeholder_from]
    assert title.help.present?
    assert note.fields.none?(&:required?)
    assert_equal %w[body], note.uses_columns
    assert_empty note.capabilities
    assert_empty note.read_only_actions
    assert_equal %w[block page kind heading titled? word icon body], note.theme_methods
    assert_equal "note.css", note.stylesheet
    assert_equal Blocks::NoteComponent, note.component
    assert_equal({ "note" => "info", "tip" => "lightbulb", "important" => "circle-alert", "warning" => "triangle-alert" }, BlockTypes::Note::ICONS)
    assert_equal "info", note.icon, "the picker's icon is the Note's, the kind a new block starts with"
    assert note.icon_follows_block?
  end

  # Plan rulings 11 and 12: a note's card and tile show its kind's icon, in
  # the icon partial's spelling, from CS Studio's closed list.
  test "CS Studio draws a note's card and tile with its kind's icon, an unknown kind's as a Note's, each on the closed list" do
    note = BlockTypes.fetch(:note)
    { "note" => "info", "tip" => "lightbulb", "important" => "circle_alert", "warning" => "triangle_alert", "gone" => "info" }.each do |kind, icon|
      block = ContentBlock.new(block_type: "note", settings: { "kind" => kind })
      assert_equal icon, BlockTypes::Note.studio_icon(block), kind
      assert_equal icon, note.icon_for(block), kind
    end
    BlockTypes::Note::ICONS.each_value { |name| assert_includes ContentModel::BlockTypeDefinition::ICONS, name.tr("-", "_") }
  end

  test "Note stands after Code in the picker, and the containers stay last" do
    assert_equal %w[rich_text image code note post_list section], BlockTypes.built_in_names
  end

  test "a new block is a Note, and an unknown stored kind reads as one" do
    block = root_page.content_blocks.create!(block_type: :note, position: 0)

    assert_equal({ "kind" => "note" }, block.settings)
    assert_equal "note", BlockTypes::Note.kind_of("gone")
    assert_equal "tip", BlockTypes::Note.kind_of("tip")
    assert_equal "note", BlockTypes::Note.kind_of(nil)
  end

  # Plan ruling 4: the sample's body is Markdown in the default language.
  test "the sample is a Tip with a title in three languages and a text" do
    sample = BlockTypes.fetch(:note).sample

    assert_equal({ "kind" => "tip" }, sample.settings)
    assert_equal %w[en de es], sample.translations.keys
    assert_equal "Before you publish", sample.translations.dig("en", :title)
    assert sample.body.present?
    assert_includes sample.shows, "Before you publish"
  end
end
```

Replace `test/components/blocks/note_component_test.rb`:

```ruby
require "test_helper"

# `Blocks::NoteComponent` (note block spec, "The public side"): an aside
# named by its heading (an h3), the kind's icon and word or the editor's
# title after the kind's word hidden for a screen reader (decision 6), and
# the text; nothing for a note without text.
class Blocks::NoteComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper

  def note_block(kind: "tip", title: nil, body: "Mind the **gap**.", titles: {})
    block = root_page.content_blocks.new(block_type: :note, position: 0, settings: { "kind" => kind })
    block.assign_settings({ "title" => title }, locale: "en") if title
    titles.each { |locale, text| block.assign_settings({ "title" => text }, locale: locale) }
    block.assign_body(rich_doc(body), locale: :en) if body
    block.save!
    block
  end

  def draw(block) = render_inline(Blocks::NoteComponent.new(block: block, page: root_page))

  def heading(block) = page.find("#note-#{block.id}-heading")

  # What a screen reader reads of the heading: every text in it, the hidden
  # word included, with its white space collapsed.
  def said(block) = heading(block).text(:all).squish

  test "each kind is an aside named by its heading, with its own word, icon and class, and never an alert" do
    { "note" => %w[Note info], "tip" => %w[Tip lightbulb], "important" => %w[Important circle-alert], "warning" => %w[Warning triangle-alert] }.each do |kind, (word, icon)|
      block = note_block(kind: kind)
      draw(block)

      assert_selector "aside.content-block.content-block--note.content-block--note-#{kind}[aria-labelledby='note-#{block.id}-heading']", count: 1
      assert_selector "aside > h3.note-head#note-#{block.id}-heading", count: 1
      assert_equal word, said(block)
      assert_selector "#note-#{block.id}-heading svg.note-icon[data-icon='#{icon}'][aria-hidden='true'][width='16'][height='16']", visible: :all
      assert_selector "aside .note-body.cs-prose strong", text: "gap"
      assert_no_selector "[role='alert'], [aria-live]"
    end
  end

  # Spec decision 6 (Claude Design D4c): under an editor's title the kind is
  # still heard, once, before the title and inside the heading, so it is in
  # a list of headings too; it is not seen.
  test "an editor's title replaces the word on screen, the word is heard once before it, hidden, and the icon and the kind stay" do
    block = note_block(kind: "warning", title: "Before you publish")
    draw(block)

    assert_equal "Warning: Before you publish", said(block)
    assert_selector "#note-#{block.id}-heading .note-kind", count: 1, text: /\AWarning:\s*\z/, visible: :all
    assert_equal 1, said(block).scan("Warning").size, "the kind is said once"
    assert_selector "aside.content-block--note-warning svg[data-icon='triangle-alert']", visible: :all
  end

  test "without a title the heading is the kind's word alone, said once, and there is no hidden word" do
    block = note_block(kind: "tip")
    draw(block)

    assert_equal "Tip", said(block)
    assert_no_selector ".note-kind", visible: :all
  end

  # Review focus 1.
  test "a title of only white space is no title: the heading is the kind's word, said once" do
    block = note_block(kind: "tip", title: "   ")
    draw(block)

    assert_equal "Tip", said(block)
    assert_no_selector ".note-kind", visible: :all
    assert_empty block.reload.translated_settings, "nothing is stored for it"
  end

  # Review focus 6: "Tip: Tip" would say the kind twice.
  test "a title that is only the kind's word is no title: the word is said once" do
    block = note_block(kind: "tip", title: "tip")
    draw(block)

    assert_equal "Tip", said(block)
    assert_no_selector ".note-kind", visible: :all
  end

  # Review focus 2.
  test "a stored kind that is not on the list is drawn as a Note" do
    block = note_block(kind: "tip")
    block.update_columns(settings: { "kind" => "danger" }) # version: none (a test writes a kind around the services, as a console would)
    draw(block.reload)

    assert_selector "aside.content-block--note-note"
    assert_equal "Note", said(block)
    assert_selector "svg[data-icon='info']", visible: :all
    assert_no_selector ".content-block--note-danger"
  end

  # Spec decision 5, and review focus 3.
  test "a note without text draws nothing, whatever its title" do
    draw(note_block(title: "A title alone", body: nil))
    assert_equal "", rendered_content.strip

    draw(note_block(body: ""))
    assert_equal "", rendered_content.strip
  end

  # Review focus 4.
  test "a visitor of another language reads the text with the site's fallback, the title in their language where there is one, and the word in English where their language has no words" do
    with_locales(%w[en de es], default: "en") do
      titled = note_block(kind: "tip", title: "Before you publish", titles: { "de" => "Vor dem Veröffentlichen" })
      plain = note_block(kind: "tip")

      I18n.with_locale(:de) do
        draw(titled)
        assert_equal "Tip: Vor dem Veröffentlichen", said(titled), "German has no words file: the hidden word is English"
        assert_selector ".note-body strong", text: "gap"
        draw(plain)
        assert_equal "Tip", said(plain)
      end
      I18n.with_locale(:es) do
        draw(titled)
        assert_equal "Tip: Before you publish", said(titled), "no Spanish title: the default language's"
      end
    end
  end

  # The text is the rich-text renderer's, whose escaping is held in
  # test/models/rich_text; the title is what this component prints.
  test "a title that looks like markup is text" do
    block = note_block(title: %(<script>alert(1)</script><b>x</b>), body: "Words.")
    draw(block)

    assert_no_selector "script, b", visible: :all
    assert_includes said(block), "<script>alert(1)</script><b>x</b>"
  end
end
```

Add to `test/values/theme/contract_test.rb`, after "each method the Code block's template may call answers…":

```ruby
  # What the reference promises of the Note block's eight names: each
  # answers for a block with nothing in it, so a theme's template needs no
  # guard; and the component draws nothing without text.
  test "each method the Note block's template may call answers for an empty block" do
    page = root_page
    component = Blocks::NoteComponent.new(block: ContentBlock.new(owner: page, block_type: "note"), page: page)
    render_inline(component)

    assert_equal [ "note", "Note", false, "Note", "info" ], %i[kind heading titled? word icon].map { |name| component.send(name) }
    assert_equal "", component.send(:body).to_s.strip
    assert_equal false, component.render?
  end
```

and, in "a default component template calls no method of its component that its line does not name", after the Code assertion:

```ruby
    assert_equal %w[block body heading icon kind titled? word], component_methods_called("blocks/note_component").sort,
      "the reading sees what the Note block's template calls (and so could fail)"
```

Add to `test/components/admin/editor_screen/tile_summary_component_test.rb`, after the Code block's tests:

```ruby
  # Note block spec, "CS Studio": the kind's word or the editor's title,
  # " · " and the start of the text; an empty text says "Empty" in the meta
  # colour. Plan ruling 6: the tile only. The kind's icon is not a part of
  # the line: the tile draws it before the line (plan ruling 12,
  # block_tile_component_test.rb), and the summary draws none.
  test "a note is its word or its title and the start of its text; one without text says Empty" do
    note = block("note", settings: { "kind" => "tip" })
    note.assign_body(rich_doc("First words of the note.\n\nA second paragraph."), locale: :en)
    note.save!
    render_summary note
    assert_no_selector ".admin-block-tile__summary svg", visible: :all
    assert_equal "Tip · First words of the note.", page.find(line).text

    note.assign_settings({ "title" => "Before you publish" }, locale: "en")
    note.save!
    render_summary note
    assert_equal "Before you publish · First words of the note.", page.find(line).text

    empty = block("note")
    render_summary empty
    assert_equal "Note · Empty", page.find(line).text
    assert_selector "#{line} > span.text-meta", exact_text: "Empty"
  end

  test "a note's title that looks like markup is text on its tile, and an unknown kind reads as a Note" do
    note = block("note", settings: { "kind" => "tip" })
    note.assign_settings({ "title" => "<i>x</i> & <script>y</script>" }, locale: "en")
    note.save!
    note.update_columns(settings: { "kind" => "gone" }) # version: none (a test writes a kind around the services)
    render_summary note.reload

    assert_equal "<i>x</i> & <script>y</script> · Empty", page.find(line).text
    assert_no_selector "#{line} i, #{line} script", visible: :all
  end

  test "a note whose kind is not on the list says Note on its tile" do
    note = block("note", settings: { "kind" => "tip" })
    note.update_columns(settings: { "kind" => "gone" }) # version: none (a test writes a kind around the services)
    render_summary note.reload

    assert_equal "Note · Empty", page.find(line).text
  end
```

Add to `test/components/admin/editor_screen/block_tile_component_test.rb`, after "the tile shows the type's icon in place of its name, and the face is still named by the type":

```ruby
  # Plan ruling 12: a note's tile shows its kind's icon, under the id a
  # save's answer replaces, one icon only, and the face still says "Note".
  test "a note's tile shows its kind's icon in place of the type's name, once, and the face is still named Note" do
    block = @editor_page.content_blocks.create!(block_type: "note", section: @section, section_column: 2, position: 0, settings: { "kind" => "warning" })
    render_tile(block)

    assert_selector ".admin-block-tile__face span#block-#{block.id}-icon-tile[data-block-icon=triangle_alert][class~='text-meta'] svg[class~='size-3']"
    assert_selector ".admin-block-tile__face [data-block-icon]", count: 1
    assert_selector ".admin-block-tile__face .sr-only", text: "Note"
    assert_selector ".admin-block-tile__face", text: /Warning · Empty/
  end
```

In `test/components/admin/editor_screen/block_icon_component_test.rb`, "every built-in block type declares its icon" names the Note's:

```ruby
    assert_equal({ "rich_text" => "pilcrow", "image" => "image", "code" => "code_xml", "note" => "info", "post_list" => "posts", "section" => "columns_2" },
      BlockTypes.all.to_h { |type| [ type.name, type.icon ] }.slice(*BuiltInBlockTypes.names))
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `PGGSSENCMODE=disable bin/rails test test/models/block_types/note_test.rb test/components/blocks/note_component_test.rb test/values/theme/contract_test.rb test/components/admin/editor_screen/tile_summary_component_test.rb test/components/admin/editor_screen/block_tile_component_test.rb test/components/admin/editor_screen/block_icon_component_test.rb test/values/theme/contract_ledger_test.rb`
Expected: FAIL: the generated definition has one `text` field and no icon; `Blocks::NoteComponent` has no `kind`; the ledger test names `blocks/note_component`.

- [ ] **Step 4: Write the definition**

Replace `app/models/block_types/note.rb` (the GENERATED line goes: the type is ours):

```ruby
module BlockTypes
  # A highlighted note in the flow of a page (note block spec): a kind, an
  # optional title of the editor's own and a short text. The design is
  # Claude Design's (B1 to B3, 2026-10-13).
  #
  # WHERE EACH VALUE LIVES. The kind is the same in every language and is a
  # setting; the title is translated, the first translated schema field of a
  # built-in type (`translated_settings`); the text is the block's ordinary
  # rich-text `body`. So no column, no migration and no service, as for the
  # Code block. Nothing is required: the picker makes an empty Note first,
  # and the public component draws nothing until there is text.
  #
  # THE KINDS are four and closed. `KINDS` is what CS Studio's segmented
  # control says (a literal, as a select's choices are); the visitor's word
  # is the public site's key `public.blocks.note.kinds.<kind>`; `ICONS` are
  # the Lucide names the default template draws, which CS Studio draws on a
  # note's card and tile in its icon partial's spelling (`studio_icon`,
  # `t.icon … for_block:`; note block plan, rulings 11 and 12). They live
  # here, not on the component, because the tile's line (`summary`) and the
  # icon need them and a model names a component only to register it (note
  # block plan, ruling 1). A kind that is stored and not on the list reads as
  # a Note (`kind_of`), everywhere.
  module Note
    KINDS = { "note" => "Note", "tip" => "Tip", "important" => "Important", "warning" => "Warning" }.freeze
    ICONS = { "note" => "info", "tip" => "lightbulb", "important" => "circle-alert", "warning" => "triangle-alert" }.freeze
    DEFAULT = "note"
    # A title is a heading of one line.
    TITLE_LENGTH = 80
    # The text on the tile is cut at the length the tile cuts every line at.
    SUMMARY_LENGTH = ContentModel::BlockTypeDefinition::SUMMARY_LENGTH

    def self.kind_of(value) = KINDS.key?(value.to_s) ? value.to_s : DEFAULT

    # CS Studio's icon of one note, on its card's head and its tile: its
    # kind's, spelt as `BlockTypeDefinition::ICONS` and the icon partial
    # spell it (`circle_alert` for Lucide's `circle-alert`). Read from the
    # rows' settings: CS Studio draws the rows, never a published copy.
    def self.studio_icon(block) = ICONS.fetch(kind_of(block.settings.to_h["kind"])).tr("-", "_")

    def self.register
      BlockTypes.register :note do |t|
        t.label "Note"
        # The picker's icon is the Note's own, the kind a new block starts
        # with; a block's card and tile show its kind's (plan ruling 12).
        t.icon "info", for_block: ->(block) { Note.studio_icon(block) }
        t.field :kind, :select, options: KINDS, default: DEFAULT, control: :segmented
        t.field :title, :string, translated: true, max: TITLE_LENGTH, placeholder_from: :kind,
                help: "Leave it empty to head the note with its kind."
        t.uses :body
        t.component Blocks::NoteComponent
        # `kind` is one of the four (an unknown stored kind is "note");
        # `heading` the editor's title in the language shown, else the
        # CMS's word for the kind in it; `titled?` whether the heading is the
        # editor's; `word` the CMS's word for the kind, titled or not (the
        # hidden word before a title, spec decision 6; plan ruling 13);
        # `icon` the kind's Lucide name; `body` the text, rendered.
        t.theme_methods :block, :page, :kind, :heading, :titled?, :word, :icon, :body
        t.stylesheet "note.css"
        t.summary ->(block, locale:) { Note.summary(block, locale: locale) }
        # The guide's own example (a Tip with a title of its own), with the
        # title in the canary's three languages and a text the canary reads.
        t.sample settings: { "kind" => "tip" },
                 translations: { "en" => { title: "Before you publish" }, "de" => { title: "Note title de" }, "es" => { title: "Note title es" } },
                 body: "Check the **address** of the page first.",
                 shows: [ "Before you publish", "Check the", "content-block--note-tip" ]
      end
    end

    # The tile's line of a closed Note, as parts (note block spec, "CS
    # Studio"): the editor's title or the kind's label as CS Studio says it,
    # " · ", and the start of the text, or "Empty" in the meta colour for a
    # note with no text in this language. The kind's icon is not a part: the
    # tile draws it before the line, in place of the type's (`t.icon …
    # for_block:`; plan ruling 12).
    def self.summary(block, locale:)
      settings = block.settings_object(locale: locale)
      kind = kind_of(settings&.kind)
      word = settings&.title.presence || KINDS.fetch(kind)
      first = block.body_document(locale: locale).plain_paragraphs.first.to_s.truncate(SUMMARY_LENGTH).presence

      [ [ :text, "#{word} · " ], (first ? [ :text, first ] : [ :hint, :empty ]) ]
    end
  end
end
```

The sixteen tokens are declared in Task 5, together with their values: a token declared without its value in `tokens.css` is red in "every declared token is defined" (`test/values/theme/contract_test.rb`). `t.stylesheet "note.css"` stays: the generated file is a valid, empty stylesheet until Task 5 fills it.

- [ ] **Step 5: Write the component, its template, the strings and the preview**

Replace `app/components/blocks/note_component.rb`:

```ruby
module Blocks
  # The Note block on the public site (`BlockTypes::Note`, note block spec,
  # "The public side"). Built like `Blocks::CodeComponent`: it reads the
  # block it is handed (a published view on the site, the rows in a preview)
  # and nothing else.
  #
  # Its template is promised eight names and no other (`theme_methods`):
  # `block`, `page`, `kind`, `heading`, `titled?`, `word`, `icon`, `body`.
  # `word` is promised beside `heading` because under an editor's title the
  # template still says the kind, visually hidden, before the title (spec
  # decision 6; note block plan, ruling 13). `settings` and `title` are
  # private help for those and no promise.
  #
  # AN EMPTY NOTE DRAWS NOTHING (decision 5): no text in the visitor's
  # language and none along the site's fallback, whatever its title.
  class NoteComponent < ApplicationComponent
    def initialize(block:, page:)
      @block = block
      @page = page
    end

    def render? = !::Locales.read(block, :body).blank?

    private

    attr_reader :block, :page

    # The settings in the visitor's language, with the site's fallback for
    # the translated title (the kind is the same in every language).
    def settings = @settings ||= block.settings_object(fallback: true)

    # One of the four; a kind stored and not on the list is a Note.
    def kind = ::BlockTypes::Note.kind_of(settings&.kind)

    # The editor's title, stripped; nil for none, and for one that is only
    # the kind's word in the language shown ("Tip" on a Tip), which would
    # otherwise be heard twice after the hidden word ("Tip: Tip"; review
    # focus 6).
    def title
      text = settings&.title.to_s.strip
      text.empty? || text.casecmp?(word) ? nil : text
    end

    def titled? = !title.nil?

    # The editor's title, else the CMS's word for the kind.
    def heading = title || word

    # The kind's Lucide name: info, lightbulb, circle-alert, triangle-alert.
    def icon = ::BlockTypes::Note::ICONS.fetch(kind)

    # The text, rendered, in the visitor's language with the fallback.
    def body = rich_text(block)

    # The kind's word in the visitor's language where
    # `config/locales/public.<locale>.yml` has it, in English otherwise;
    # titled or not.
    def word
      key = "public.blocks.note.kinds.#{kind}"
      I18n.t(key, locale: I18n.exists?(key, I18n.locale) ? I18n.locale : :en)
    end
  end
end
```

Replace `app/components/blocks/note_component.html.erb`:

```erb
<%# The Note block (note block spec, "The public side"): an `aside` named by its heading, never an
    alert, since a note is part of the page and not an event. The heading is an h3 (plan ruling 14), so
    it is in a list of headings too. It holds the kind's icon, which is decoration (`aria-hidden`: the
    word says the kind), and `heading`, the editor's title or the CMS's word. Under an editor's title
    (`titled?`) the kind's `word` and a colon stand first, visually hidden (`note-kind`, note.css), so a
    screen reader hears "Tip: Before you publish"; without a title there is none, and "Tip" is never
    said twice (decision 6). The icon is drawn here inline by its Lucide name (`icon`); a theme's template
    draws its own. The class names are the default theme's own (note.css), not a promise; the heading's
    id is written from `block`. Everything printed goes through ERB's own escaping. %>
<aside class="content-block content-block--note content-block--note-<%= kind %>" aria-labelledby="note-<%= block.id %>-heading">
  <h3 class="note-head" id="note-<%= block.id %>-heading">
    <svg class="note-icon" data-icon="<%= icon %>" xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">
      <% if icon == "lightbulb" %>
        <path d="M15 14c.2-1 .7-1.7 1.5-2.5 1-.9 1.5-2.2 1.5-3.5A6 6 0 0 0 6 8c0 1 .2 2.2 1.5 3.5.7.7 1.3 1.5 1.5 2.5"/><path d="M9 18h6"/><path d="M10 22h4"/>
      <% elsif icon == "circle-alert" %>
        <circle cx="12" cy="12" r="10"/><path d="M12 8v4"/><path d="M12 16h.01"/>
      <% elsif icon == "triangle-alert" %>
        <path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/>
      <% else %>
        <circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>
      <% end %>
    </svg>
    <span><% if titled? %><span class="note-kind"><%= word %>: </span><% end %><%= heading %></span>
  </h3>
  <div class="note-body cs-prose"><%= body %></div>
</aside>
```

In `config/locales/public.en.yml`, replace the generated `      note: {}` line with:

```yaml
      # The Note block's heading where the editor typed no title: the
      # kind's word (`Blocks::NoteComponent`).
      note:
        kinds:
          note: "Note"
          tip: "Tip"
          important: "Important"
          warning: "Warning"
```

In `config/locales/admin/editor_screen.en.yml`, replace the generated `            note: {}` line with:

```yaml
            note:
              empty: "Empty"
```

Replace `test/components/previews/blocks/note_component_preview.rb`:

```ruby
require_relative "../preview_fixtures"

module Blocks
  # `Blocks::NoteComponent`: the type's sample, then each of the four kinds
  # with no title, headed by its word.
  class NoteComponentPreview < ViewComponent::Preview
    def sample
      sample = BlockTypes.fetch(:note).sample
      render component(sample.settings, title: sample.translations.dig("en", :title), body: sample.body)
    end

    BlockTypes::Note::KINDS.each_key do |kind|
      define_method(kind) { render component({ "kind" => kind }, body: "A #{kind} with a [link](https://example.com) and `inline code`.") }
    end

    private

    def component(settings, body:, title: nil)
      page = PreviewFixtures.page(title: "Note preview")
      block = page.content_blocks.new(block_type: :note, position: 0, settings: settings)
      block.assign_settings({ "title" => title }, locale: "en") if title
      block.assign_body(RichText::Document.from_markdown(body).first, locale: "en")
      block.save!

      Blocks::NoteComponent.new(block: block, page: page)
    end
  end
end
```

In `app/assets/tailwind/themes/default/note.css`, take out the two lines of the comment that say "Written by bin/rails generate block_type…" (the stylesheet is ours; Task 5 fills it).

- [ ] **Step 6: Write the ledger line and the reference's row**

In `test/support/contract_ledger.rb`, `COMPONENTS`, after the Code line (registration order):

```ruby
    "blocks/note_component" => %w[block page kind heading titled? word icon body],
```

In `docs/reference/theming.md`, "### Components", after the `blocks/code_component` row:

```markdown
| `blocks/note_component` | `block`, `page`, `kind`, `heading`, `titled?`, `word`, `icon`, `body` |
```

- [ ] **Step 7: Run the tests to verify they pass**

Run first (the public integration tests read the built stylesheet, and the entry now imports `note.css`): `bin/rails tailwindcss:build && bin/rails theme_css:build`
Then: `PGGSSENCMODE=disable bin/rails test test/models/block_types/note_test.rb test/models/built_in_types_test.rb test/components/blocks/note_component_test.rb test/values/theme/contract_test.rb test/values/theme/contract_ledger_test.rb test/lib/theming_reference_test.rb test/components/admin/editor_screen/tile_summary_component_test.rb test/components/admin/editor_screen/block_tile_component_test.rb test/components/admin/editor_screen/block_icon_component_test.rb test/components/admin/editor_screen/block_picker_component_test.rb test/integration/block_samples_test.rb test/components/admin/editor_screen/block_samples_card_test.rb test/lib/generators/block_type_generator_test.rb test/lib/dependency_direction_test.rb test/lib/source_layout_test.rb test/lib/admin_i18n_test.rb test/lib/admin_namespace_shadow_test.rb`
Expected: PASS. (`test/values/theme/scaffold_test.rb` and the canary are run in Task 5, after the stylesheet.)

- [ ] **Step 8: Commit**

```bash
git add app/models/block_types/note.rb config/initializers/types.rb app/components/blocks/note_component.rb app/components/blocks/note_component.html.erb app/assets/tailwind/themes/default/note.css config/locales/public.en.yml config/locales/admin/editor_screen.en.yml test/components/previews/blocks/note_component_preview.rb test/models/block_types/note_test.rb test/components/blocks/note_component_test.rb test/support/contract_ledger.rb docs/reference/theming.md test/values/theme/contract_test.rb test/components/admin/editor_screen/tile_summary_component_test.rb test/components/admin/editor_screen/block_tile_component_test.rb test/components/admin/editor_screen/block_icon_component_test.rb
git commit -m "$(cat <<'EOF'
feat: the Note block type, its public component and its tile

Release note: the theme contract gains blocks/note_component (block, page,
kind, heading, titled?, word, icon, body).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT
EOF
)"
```

---

### Task 5: the Note's stylesheet, its sixteen tokens, the reference's section and a theme of its own

**Files:**
- Modify: `app/models/block_types/note.rb` (the `t.tokens` line)
- Modify: `app/assets/tailwind/themes/default/note.css`, `app/assets/tailwind/themes/default/tokens.css`
- Modify: `test/support/contract_ledger.rb` (`THEMED_TOKENS`), `docs/reference/theming.md` (Tokens table, "### The Note block", "In tests")
- Create: `test/fixtures/themes/note/components/blocks/note_component.html.erb`, `test/fixtures/themes/note/assets/stylesheets/theme.css`
- Modify: `test/support/theme_test_helper.rb`
- Test: `test/integration/design_tokens_test.rb`, `test/lib/theming_reference_test.rb`, `test/integration/theme_pages_test.rb`

**Interfaces:**
- Consumes: `Blocks::NoteComponent` and its markup (Task 4).
- Produces: the sixteen `--th-note-*` tokens in both blocks of `tokens.css`; note.css's rules (per-kind local properties `--note-ground`, `--note-line`, `--note-ink`, `--note-border`); `ThemeTestHelper::NOTE`, `#note_theme`, `#with_note_theme`; the section "### The Note block" of `docs/reference/theming.md`.

- [ ] **Step 1: Declare the tokens and write the failing tests**

In `app/models/block_types/note.rb`, after `t.theme_methods`:

```ruby
        # Four per kind, in the order of `KINDS`; their values are the default
        # theme's (`tokens.css`, defined from the base tokens), and a strong
        # band re-values them (`sections.css`).
        t.tokens themed: KINDS.keys.flat_map { |kind| %W[note-#{kind}-ground note-#{kind}-line note-#{kind}-ink note-#{kind}-border] }
```

and in `test/models/block_types/note_test.rb`, in the first test, after the `stylesheet` assertion:

```ruby
    assert_equal %w[note tip important warning].flat_map { |kind| %W[note-#{kind}-ground note-#{kind}-line note-#{kind}-ink note-#{kind}-border] }, note.themed_tokens
    assert_empty note.fixed_tokens
```

Add to `test/integration/design_tokens_test.rb`, after the Code block's stylesheet tests:

```ruby
  NOTE_KINDS = BlockTypes::Note::KINDS.keys.freeze

  # Note block spec, "The public side": plain rules on tokens; each kind's
  # four tokens drawn in one place; the text, links and inline code the
  # theme's own.
  test "the note's stylesheet is declared by the type, holds no colour of its own, and draws each kind by its four tokens" do
    css = Rails.root.join("app/assets/tailwind/themes/default/note.css").read
    rule = ->(selector) { css.gsub(%r{/\*.*?\*/}m, "")[/(?:^|\})\s*#{Regexp.escape(selector)}\s*\{([^}]*)\}/m, 1].to_s }

    assert_equal Rails.root.join("app/assets/tailwind/themes/default/note.css"), BlockTypes.fetch(:note).stylesheet_path
    refute_match(/#\h{3,8}\b|\brgba?\(|\bhsla?\(|\boklch\(/, css)
    NOTE_KINDS.each do |kind|
      %w[ground line ink border].each do |part|
        assert_match(/--note-#{part}:\s*var\(--th-note-#{kind}-#{part}\);/, rule.(".content-block--note-#{kind}"), "#{kind}'s #{part}")
      end
    end
    box = rule.(".content-block--note")
    assert_match(/background:\s*var\(--note-ground\);/, box)
    assert_match(/border:\s*1px solid var\(--note-border\);/, box)
    assert_match(/border-left:\s*3px solid var\(--note-line\);/, box)
    head = rule.(".content-block--note .note-head")
    assert_match(/color:\s*var\(--note-ink\);/, head)
    assert_match(/font-size:\s*inherit;/, head, "the h3 is the body's size, whatever the theme's h3 is (plan ruling 14)")
    assert_match(/clip-path:\s*inset\(50%\);/, rule.(".content-block--note .note-kind"), "the kind's word before a title is heard, not seen (decision 6)")
    assert_no_match(/color:/, rule.(".content-block--note .note-body"), "the text is the theme's ink, from .cs-prose")
    code = rule.(".content-block--note .note-body :not(pre) > code")
    assert_match(/background:\s*var\(--th-surface\);/, code)
    assert_match(/border:\s*1px solid var\(--th-line\);/, code)
  end

  # Spec decision 9 (Claude Design D4a): Note neutral, Tip the ok green,
  # Important the accent blue, Warning the warn amber; red is for errors.
  NOTE_HUES = { "note" => "--th-line-strong", "tip" => "--th-ok", "important" => "--th-accent", "warning" => "--th-warn" }.freeze

  test "the sixteen note tokens are defined from the theme's base tokens in both schemes, never a literal, each kind in its hue and none in red" do
    theme_tokens.each do |theme, tokens|
      NOTE_KINDS.each do |kind|
        %w[ground line ink border].each do |part|
          value = tokens.fetch("--th-note-#{kind}-#{part}") { flunk("--th-note-#{kind}-#{part} is not defined for #{theme}") }
          assert_match(/\A(?:var\(--th-[\w-]+\)|color-mix\(in srgb, var\(--th-[\w-]+\) \d+%, var\(--th-[\w-]+\)\))\z/, value, "#{theme} --th-note-#{kind}-#{part} is #{value}")
          assert_no_match(/danger/, value, "#{theme} --th-note-#{kind}-#{part}: red is kept for errors and destructive actions")
        end
        assert_equal "var(#{NOTE_HUES.fetch(kind)})", tokens.fetch("--th-note-#{kind}-line"), "#{theme}: the #{kind}'s rule is its hue"
      end
      assert_equal "color-mix(in srgb, var(--th-ink) 4%, var(--th-paper))", tokens.fetch("--th-note-note-ground"), "#{theme}: a Note is a 4% tint of the text colour"
    end
  end
```

Add to `test/lib/theming_reference_test.rb`, after the Code block's test:

```ruby
  # The Note block's section: what its template is handed, held to its line
  # of the ledger, and its sixteen tokens named.
  test "the Note block's table names exactly the methods of its entry, and the section names its tokens" do
    section = section("The Note block")

    assert_equal ContractLedger::COMPONENTS.fetch("blocks/note_component").sort, section.scan(/^\| `([^`]+)` \|/).flatten.sort
    BlockTypes.fetch(:note).themed_tokens.each { |token| assert_includes section, "--th-#{token}" }
    BlockTypes::Note::ICONS.each_value { |icon| assert_includes section, "`#{icon}`" }
  end
```

Add to `test/support/theme_test_helper.rb`, after `with_code_theme`:

```ruby
  # A fourth theme, of two files (`test/fixtures/themes/note`): its own
  # template for the Note block, written from the reference's section alone
  # (docs/reference/theming.md, "The Note block"), and a stylesheet for it.
  NOTE = Rails.root.join("test/fixtures/themes/note")

  def note_theme = Theme.load(ThemeFolder.new(NOTE))

  def with_note_theme(&block) = Theme.with(note_theme, &block)
```

Add to `test/integration/theme_pages_test.rb`, after "the third theme is sound…":

```ruby
  test "a theme replaces the Note block's template from the contract's names alone, and a theme that does not is drawn the default one" do
    guide = create_page(title: "Guide")
    result = ContentBlocks::Save.call(ContentBlock.new(owner: guide), attributes: { block_type: "note", settings: { "kind" => "warning", "title" => "<b>Mind</b>" } },
      translations: { "en" => { body: rich_doc("Check the **address**.") } })
    assert result.ok?, result.errors.to_sentence
    block = result.record
    publish_changes(guide)

    with_note_theme { get "/guide" }

    assert_response :success
    assert_select "section.plain-note[data-kind='warning'][data-icon='triangle-alert'][data-titled='true'][data-block='#{block.id}'][data-page='#{guide.id}'][aria-labelledby='plain-note-#{block.id}']" do
      assert_select "h2#plain-note-#{block.id}", text: "Warning: <b>Mind</b>"
      assert_select "h2#plain-note-#{block.id} .plain-note__kind", text: "Warning:"
      assert_select "div.plain-note__text strong", text: "address"
    end
    assert_select "aside.content-block--note", count: 0
    assert_select "section.plain-note b", count: 0

    with_plain_theme { get "/guide" }

    assert_response :success
    assert_select "div.plain-frame aside.content-block--note-warning h3#note-#{block.id}-heading", text: "Warning: <b>Mind</b>"
    assert_select "section.plain-note", count: 0
  end

  test "the fourth theme is sound, checked deeply too: a Note template of the contract's names" do
    folder = ThemeFolder.new(ThemeTestHelper::NOTE)

    assert_empty Theme::Check.problems(folder, deep: true)
    assert_equal %w[assets/stylesheets/theme.css components/blocks/note_component.html.erb], folder.files
    template = folder.read("components/blocks/note_component.html.erb")
    Theme::Contract.components.fetch("blocks/note_component").each { |name| assert_match(/#{Regexp.escape(name)}/, template, "the template calls #{name}") }
    assert_no_match(/settings|title\b|I18n|\bt\(|html_safe|raw\b|<%==/, template, "nothing the contract does not name (the kind's word is `word`, not a key looked up), and no string marked safe")
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `PGGSSENCMODE=disable bin/rails test test/integration/design_tokens_test.rb test/lib/theming_reference_test.rb test/integration/theme_pages_test.rb test/values/theme/contract_test.rb test/values/theme/contract_ledger_test.rb`
Expected: FAIL: the tokens are declared and not defined ("Listed but not defined"), the ledger's themed tokens differ, no "### The Note block", no fixture theme, note.css has no rules.

- [ ] **Step 3: Write the tokens**

In `app/assets/tailwind/themes/default/tokens.css`, in `:root, [data-theme="light"]`, after `--th-syn-embed`:

```css
  /* The Note block's four kinds (note block spec, decision 9: Claude
     Design's D4a), four tokens each, every one DEFINED from the base tokens
     above, so a theme that re-colours its base re-colours the notes. Note is
     neutral: a 4% tint of the text colour, a --th-line-strong rule, its word
     and icon in the text colour, a --th-line frame. Tip is --th-ok, Important
     the accent, Warning --th-warn: the ground the hue at 8% over the page,
     the rule the hue, the word and icon the hue's ink (the accent is its own
     ink), the frame the hue at 24%. No kind is red: --th-danger is kept for
     errors and destructive actions. The text stays --th-ink. A strong band
     re-values all sixteen (sections.css).
     test/integration/design_tokens_test.rb holds the 72 pairs: the ink, the
     accent and the kind's ink on each kind's ground, on the page, in a
     tinted band and in a strong band, in both themes; the lowest here is
     the accent on the Important ground, 4.88:1. */
  --th-note-note-ground: color-mix(in srgb, var(--th-ink) 4%, var(--th-paper));
  --th-note-note-line: var(--th-line-strong);
  --th-note-note-ink: var(--th-ink);
  --th-note-note-border: var(--th-line);
  --th-note-tip-ground: color-mix(in srgb, var(--th-ok) 8%, var(--th-paper));
  --th-note-tip-line: var(--th-ok);
  --th-note-tip-ink: var(--th-ok-ink);
  --th-note-tip-border: color-mix(in srgb, var(--th-ok) 24%, var(--th-paper));
  --th-note-important-ground: color-mix(in srgb, var(--th-accent) 8%, var(--th-paper));
  --th-note-important-line: var(--th-accent);
  --th-note-important-ink: var(--th-accent);
  --th-note-important-border: color-mix(in srgb, var(--th-accent) 24%, var(--th-paper));
  --th-note-warning-ground: color-mix(in srgb, var(--th-warn) 8%, var(--th-paper));
  --th-note-warning-line: var(--th-warn);
  --th-note-warning-ink: var(--th-warn-ink);
  --th-note-warning-border: color-mix(in srgb, var(--th-warn) 24%, var(--th-paper));
```

In `[data-theme="dark"]`, after `--th-syn-embed`:

```css
  /* The notes again: Note's 4% tint of the text colour, and 12% of the hue
     over the dark page for the other three. The lowest here is the accent
     on the Important ground, 6.9:1. */
  --th-note-note-ground: color-mix(in srgb, var(--th-ink) 4%, var(--th-paper));
  --th-note-note-line: var(--th-line-strong);
  --th-note-note-ink: var(--th-ink);
  --th-note-note-border: var(--th-line);
  --th-note-tip-ground: color-mix(in srgb, var(--th-ok) 12%, var(--th-paper));
  --th-note-tip-line: var(--th-ok);
  --th-note-tip-ink: var(--th-ok-ink);
  --th-note-tip-border: color-mix(in srgb, var(--th-ok) 24%, var(--th-paper));
  --th-note-important-ground: color-mix(in srgb, var(--th-accent) 12%, var(--th-paper));
  --th-note-important-line: var(--th-accent);
  --th-note-important-ink: var(--th-accent);
  --th-note-important-border: color-mix(in srgb, var(--th-accent) 24%, var(--th-paper));
  --th-note-warning-ground: color-mix(in srgb, var(--th-warn) 12%, var(--th-paper));
  --th-note-warning-line: var(--th-warn);
  --th-note-warning-ink: var(--th-warn-ink);
  --th-note-warning-border: color-mix(in srgb, var(--th-warn) 24%, var(--th-paper));
```

(The comment must not contain `content-block`, `content-section` or `cs-prose`: "the default theme's tokens file imports nothing and names no block".)

In `test/support/contract_ledger.rb`, `THEMED_TOKENS`, after the `syn-*` line:

```ruby
    note-note-ground note-note-line note-note-ink note-note-border
    note-tip-ground note-tip-line note-tip-ink note-tip-border
    note-important-ground note-important-line note-important-ink note-important-border
    note-warning-ground note-warning-line note-warning-ink note-warning-border
```

In `docs/reference/theming.md`, "### Tokens", after the `--th-syn-embed` row, sixteen rows:

```markdown
| `--th-note-note-ground` | a Note's ground |
| `--th-note-note-line` | a Note's rule on the left |
| `--th-note-note-ink` | a Note's word and icon |
| `--th-note-note-border` | a Note's frame |
| `--th-note-tip-ground` | a Tip's ground |
| `--th-note-tip-line` | a Tip's rule on the left |
| `--th-note-tip-ink` | a Tip's word and icon |
| `--th-note-tip-border` | a Tip's frame |
| `--th-note-important-ground` | an Important note's ground |
| `--th-note-important-line` | an Important note's rule on the left |
| `--th-note-important-ink` | an Important note's word and icon |
| `--th-note-important-border` | an Important note's frame |
| `--th-note-warning-ground` | a Warning's ground |
| `--th-note-warning-line` | a Warning's rule on the left |
| `--th-note-warning-ink` | a Warning's word and icon |
| `--th-note-warning-border` | a Warning's frame |
```

- [ ] **Step 4: Write the stylesheet**

Replace `app/assets/tailwind/themes/default/note.css`:

```css
/* The Note block (note block spec, "The public side"; `Blocks::NoteComponent`).
   Plain rules on tokens, not utilities. A tinted box with a 3px rule on the
   left in the kind's colour, a 1px frame, and a heading line (an h3, at the
   body's size whatever the theme's h3 is) of the kind's icon and word (or
   the editor's title) in the kind's ink at weight 600. Under an editor's
   title the kind's word stands first in `.note-kind`, visually hidden: it
   is heard and not seen (decision 6). The text is the theme's own:
   `.cs-prose` draws it in --th-ink with links in --th-accent, and a band
   re-values those for what is inside it.

   Each kind hands its four tokens to four local names, so the box's rules
   are written once. The tokens are the theme's (`tokens.css`, defined from
   the base tokens); a strong band re-values all sixteen (`sections.css`).

   Inline code inside a note stands on --th-surface with a 1px line, so it
   is told from the tint (design answer B2). */
.content-block--note {
  margin-block: 2rem;
  padding: var(--th-sp-3) var(--th-sp-4);
  background: var(--note-ground);
  border: 1px solid var(--note-border);
  border-left: 3px solid var(--note-line);
  border-radius: var(--th-radius);
}
.content-block--note-note { --note-ground: var(--th-note-note-ground); --note-line: var(--th-note-note-line); --note-ink: var(--th-note-note-ink); --note-border: var(--th-note-note-border); }
.content-block--note-tip { --note-ground: var(--th-note-tip-ground); --note-line: var(--th-note-tip-line); --note-ink: var(--th-note-tip-ink); --note-border: var(--th-note-tip-border); }
.content-block--note-important { --note-ground: var(--th-note-important-ground); --note-line: var(--th-note-important-line); --note-ink: var(--th-note-important-ink); --note-border: var(--th-note-important-border); }
.content-block--note-warning { --note-ground: var(--th-note-warning-ground); --note-line: var(--th-note-warning-line); --note-ink: var(--th-note-warning-ink); --note-border: var(--th-note-warning-border); }
.content-block--note .note-head {
  display: flex;
  align-items: center;
  gap: var(--th-sp-2);
  margin: 0 0 var(--th-sp-2);
  font-family: inherit;
  font-size: inherit;
  line-height: inherit;
  letter-spacing: normal;
  text-transform: none;
  font-weight: 600;
  color: var(--note-ink);
}
.content-block--note .note-icon { width: 1rem; height: 1rem; flex: none; }
.content-block--note .note-kind {
  position: absolute;
  width: 1px;
  height: 1px;
  margin: -1px;
  padding: 0;
  overflow: hidden;
  clip-path: inset(50%);
  white-space: nowrap;
  border: 0;
}
.content-block--note .note-body > :first-child { margin-top: 0; }
.content-block--note .note-body :not(pre) > code {
  background: var(--th-surface);
  border: 1px solid var(--th-line);
  border-radius: var(--th-radius);
  padding: 0 0.25em;
}
```

- [ ] **Step 5: Write the reference's section and the fourth theme**

In `docs/reference/theming.md`, after the Code block's section (before `## What a template may ask`):

````markdown
### The Note block

A highlighted note in the flow of a page: a kind (Note, Tip, Important, Warning), an optional title of the editor's own and a short rich text (note block spec; the block itself is in `docs/reference/content-blocks-and-types.md`, "The Note block"). What a theme can do with it, from the least work to the most:

1. **Re-colour it: re-colour the base tokens**, or declare the sixteen `--th-note-*` again under both selectors. Each is defined from the base in the default theme (Note is neutral, a 4% tint of `--th-ink` with a `--th-line-strong` rule; Tip is `--th-ok`, Important `--th-accent`, Warning `--th-warn`; none is `--th-danger`, which is kept for errors), so a theme that changes its base changes its notes. The text is `--th-ink`, its links `--th-accent`, inline code `--th-surface` with a `--th-line` frame. `--th-note-note-ground`, `--th-note-note-line`, `--th-note-note-ink`, `--th-note-note-border`, and the same four for `tip`, `important` and `warning`.
2. **Restyle it: rules of its own** under `.content-block--note`. The default template's class names (`content-block--note-<kind>`, `note-head`, `note-icon`, `note-kind`, `note-body`) are the default theme's own, not on a list.
3. **Replace its template**: `components/blocks/note_component.html.erb`.

**What the template is handed** (`Theme::Contract.components`). The component draws nothing for a note without text in the language shown or along the site's fallback (`render?`), so a template never meets one, and each method answers for an empty block all the same.

| Method | What it answers |
|---|---|
| `block` | the block: a published view on the site, the rows in a preview. `block.id` tells two notes of a page apart (an `id` for `aria-labelledby`) |
| `page` | the page the block is drawn on |
| `kind` | `"note"`, `"tip"`, `"important"` or `"warning"`; a kind stored and not on the list is `"note"` |
| `heading` | the editor's title in the language shown, with the site's fallback; without one (or with one that is only the kind's word), the CMS's word for the kind ("Tip") |
| `titled?` | whether `heading` is the editor's title |
| `word` | the CMS's word for the kind ("Tip"), titled or not, in the language shown where `config/locales/public.<locale>.yml` has it and in English otherwise |
| `icon` | the kind's Lucide name: `info`, `lightbulb`, `circle-alert` or `triangle-alert` |
| `body` | the text, rendered (the same HTML `rich_text(block)` answers) |

**What a template should keep.** The default draws an `aside` named by its heading (`aria-labelledby`), an `h3`, and never `role="alert"`: a note is part of the page, not an event. The icon is decoration (`aria-hidden`), since the heading says the kind. **Under an editor's title the kind is still said**: when `titled?`, the default puts `word` and a colon first inside the heading, visually hidden, so a screen reader hears "Tip: Before you publish", in a list of headings too; without a title it adds nothing, because `heading` is then the word and "Tip" would be heard twice. A theme's template should do the same. Print `heading` and `word` through ERB's escaping (`<%= heading %>`) and never mark them safe: the title is what an editor typed.

**On a section's bands** (`sections.css`): a tinted band changes nothing of a note. **On a strong band a note shares the band's ground and each kind keeps its colour** (spec decision 10): every ground is `--th-band-strong`, every frame the band's `--th-line`, the text the band's text, and each kind's rule and ink (its word and icon) a colour of its own that reads on the band: Note the band's dim and text, Important the band's accent (`--th-on-band-strong-accent`), Tip and Warning their hue mixed 60% with the band's text (`color-mix(in srgb, var(--th-ok) 60%, var(--th-on-band-strong))`). The band is a dark ground in both schemes, so these are light inks in both. A theme's own `--th-note-*` therefore do not reach a note in a strong band; a theme that wants other colours there, or that draws its strong band light, declares them in a rule of its own for `.content-section--strong` and answers for their contrast.

**Contrast is computed, for the default theme's values only.** `test/integration/design_tokens_test.rb` holds 72 pairs at 4.5:1 or better: `--th-ink`, `--th-accent` and the kind's ink on each kind's ground, on the page, in a tinted band and in a strong band, in both schemes ("every note's text, link and word are readable on its ground…"); and 16 at 3:1 or better: each kind's rule and ink against a strong band, in both schemes ("on a strong band a note shares the band's ground and each kind keeps its colour…"). Nothing measures a theme's values.

The fourth theme (`test/fixtures/themes/note`, "In tests") is a template written from this section alone: `test/integration/theme_pages_test.rb` ("a theme replaces the Note block's template from the contract's names alone, and a theme that does not is drawn the default one", "the fourth theme is sound, checked deeply too: a Note template of the contract's names").
````

In "## In tests" of the same file, after the sentence that names the third theme, add: "A fourth, `test/fixtures/themes/note` (`with_note_theme`), is a Note template written from \"The Note block\" alone and a stylesheet for it."

Create `test/fixtures/themes/note/components/blocks/note_component.html.erb` (written from the section above alone):

```erb
<%# A theme's own Note block, written from what `Theme::Contract` gives the template (`block`, `page`,
    `kind`, `heading`, `titled?`, `word`, `icon`, `body`; docs/reference/theming.md, "The Note block"): a
    section named by its heading, the kind's word said first, hidden, under an editor's title only, the
    heading printed through ERB's own escaping, the text as handed over. %>
<section class="plain-note" data-kind="<%= kind %>" data-icon="<%= icon %>" data-titled="<%= titled? %>" data-block="<%= block.id %>" data-page="<%= page.id %>" aria-labelledby="plain-note-<%= block.id %>">
  <h2 id="plain-note-<%= block.id %>"><% if titled? %><span class="plain-note__kind"><%= word %>:</span> <% end %><%= heading %></h2>
  <div class="plain-note__text"><%= body %></div>
</section>
```

Create `test/fixtures/themes/note/assets/stylesheets/theme.css`:

```css
/* The fourth theme's stylesheet: its own Note template's rules, on the
   default theme's note tokens, which this theme does not change. */
.plain-note { border-left: 3px solid var(--th-note-note-line); background: var(--th-note-note-ground); padding: var(--th-sp-3); }
.plain-note[data-kind="tip"] { border-left-color: var(--th-note-tip-line); background: var(--th-note-tip-ground); }
.plain-note[data-kind="important"] { border-left-color: var(--th-note-important-line); background: var(--th-note-important-ground); }
.plain-note[data-kind="warning"] { border-left-color: var(--th-note-warning-line); background: var(--th-note-warning-ground); }
.plain-note__kind { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
```

- [ ] **Step 6: Build and run the tests to verify they pass**

Run: `bin/rails tailwindcss:build && bin/rails theme_css:build`
Then: `PGGSSENCMODE=disable bin/rails test test/integration/design_tokens_test.rb test/lib/theming_reference_test.rb test/integration/theme_pages_test.rb test/values/theme test/models/block_types/note_test.rb test/lib/theme_css_test.rb test/integration/public_canary_test.rb test/integration/block_samples_test.rb test/services/translation_state_parity_test.rb`
Expected: PASS (the contrast test of Task 7 does not exist yet).

- [ ] **Step 7: Commit**

```bash
git add app/models/block_types/note.rb test/models/block_types/note_test.rb app/assets/tailwind/themes/default/note.css app/assets/tailwind/themes/default/tokens.css test/support/contract_ledger.rb docs/reference/theming.md test/fixtures/themes/note test/support/theme_test_helper.rb test/integration/design_tokens_test.rb test/lib/theming_reference_test.rb test/integration/theme_pages_test.rb
git commit -m "$(cat <<'EOF'
feat: the Note block's stylesheet and sixteen tokens, defined from the theme's base

Release note: sixteen themed tokens join the contract,
--th-note-{note,tip,important,warning}-{ground,line,ink,border}.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT
EOF
)"
```

---

### Task 6: the translated title, end to end

**Files:**
- Test: `test/services/translation_state_parity_test.rb`, `test/services/ai/translate_test.rb`, `test/integration/public_blocks_test.rb`, `test/models/audit/snapshot_test.rb`, `test/components/admin/editor_screen/block_card_component_test.rb`
- Modify: production code only if a test shows a gap (none is expected; the mechanism exists and `test/quote` walks it from outside)

**Interfaces:**
- Consumes: the Note type (Tasks 4, 5) and its card's icon (Task 3); `ContentBlocks::Save.call(block, attributes: { settings: … }, translations: { locale => { settings: { "title" => … }, body: … } })`.
- Produces: tests only.

- [ ] **Step 1: Write the tests**

Add to `test/services/translation_state_parity_test.rb`, after the Code block's test:

```ruby
  # Plan ruling 5: no block's text makes its page missing, and a title is
  # optional, so a Note never does; its title and its text are tracked for
  # outdated. A change of the kind changes no state.
  test "a note's title is tracked like a caption: never missing, outdated when the original changes, and a change of the kind changes no state" do
    as_owner do
      page = create_page(title: "Guide", translations: { "de" => { title: "Leitfaden" }, "es" => { title: "Guía" } })
      block = ContentBlocks::Save.call(page.content_blocks.new, attributes: { block_type: "note", settings: { "kind" => "tip", "title" => "Before you publish" } },
        translations: { "en" => { body: rich_doc("Mind the address.") } }).record
      assert_parity page
      assert_equal "complete", stored_state(page, "de"), "a title and a text left untranslated are a choice, not a gap"

      assert ContentBlocks::Save.call(block, translations: { "de" => { settings: { "title" => "Vor dem Veröffentlichen" } } }).ok?
      assert ContentBlocks::Save.call(block, attributes: { settings: { "title" => "Before you go live" } }).ok?
      assert_parity page
      assert_equal "outdated", stored_state(page, "de")
      assert_equal :outdated, block.reload.translation_state(:title, "de")
      assert_equal "complete", stored_state(page, "es")

      assert ContentBlocks::Save.call(block, attributes: { settings: { "kind" => "warning" } }).ok?
      assert_parity page
      assert_equal "outdated", stored_state(page, "de")
      assert_equal "complete", stored_state(page, "es")
    end
  end
```

Add to `test/services/ai/translate_test.rb`, after "a block needs its owner's edit right":

```ruby
  test "a note's title goes to the provider as plain text and its text as Markdown, and its kind is not offered" do
    page = as_owner { create_page(title: "Guide") }
    block = as_owner do
      ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "note", settings: { "kind" => "tip", "title" => "Before you publish" } },
        translations: { "en" => { body: rich_doc("Mind the address.") } }).record
    end

    service, result = translate(block, %w[title body])

    assert result.ok?, result.errors.to_sentence
    assert_equal "[de] Before you publish", service.suggestions["title"]
    assert_equal "[de] Mind the address.", service.suggestions["body"].to_h.dig("content", 0, "content", 0, "text")
    assert_equal [ :plain, :markdown ], StubProvider.calls.map { |call| call[:format] }
    assert_nil block.reload.settings_object(locale: "de").title, "nothing is saved"

    _, refused = translate(block, %w[kind])
    assert_not refused.ok?
    assert_equal [ "Kind can't be translated" ], refused.errors
  end
```

Add to `test/integration/public_blocks_test.rb`, before the final `end`:

```ruby
  # Drafts of live content: a visitor reads a live page's note from its
  # published copy, its title in each language included, until the page's
  # changes are published. Under a title the heading starts with the kind's
  # hidden word, from the copy's kind; German has no words file, so it is
  # English there.
  test "a note on a live page is read from its published copy: its kind, its title in each language and its text change only when published" do
    with_locales(%w[en de es], default: "en") do
      page = create_page(title: "Guide")
      block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "note", settings: { "kind" => "tip", "title" => "Before you publish" } },
        translations: { "en" => { body: rich_doc("Mind the address.") }, "de" => { settings: { "title" => "Vor dem Veröffentlichen" } } }).record
      publish_changes(page)

      assert ContentBlocks::Save.call(block, attributes: { settings: { "kind" => "warning", "title" => "Changed" } },
        translations: { "en" => { body: rich_doc("New words.") }, "de" => { settings: { "title" => "Geändert" } } }).ok?

      get PublicSite::Urls.new.path_for(page, "en")
      assert_select "aside.content-block--note-tip #note-#{block.id}-heading", text: "Tip: Before you publish"
      assert_select "aside .note-body", text: /Mind the address/
      get PublicSite::Urls.new.path_for(page, "de")
      assert_select "#note-#{block.id}-heading", text: "Tip: Vor dem Veröffentlichen"

      publish_changes(page)
      get PublicSite::Urls.new.path_for(page, "en")
      assert_select "aside.content-block--note-warning #note-#{block.id}-heading", text: "Warning: Changed"
      assert_select "aside .note-body", text: /New words/
      get PublicSite::Urls.new.path_for(page, "de")
      assert_select "#note-#{block.id}-heading", text: "Warning: Geändert"
    end
  end

  test "a note at the top level and in a section's column is drawn from the copy, in the column once" do
    page = create_page(title: "Guide")
    section = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "section", settings: { "layout" => "two" } }).record
    [ nil, section ].each do |holder|
      placement = holder ? { section_id: holder.id, section_column: 2 } : {}
      assert ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "note", settings: { "kind" => "important" } }.merge(placement),
        translations: { "en" => { body: rich_doc("Words #{holder ? "inside" : "outside"}.") } }).ok?
    end
    publish_changes(page)

    get PublicSite::Urls.new.path_for(page, "en")
    assert_select "aside.content-block--note-important", count: 2
    assert_select ".content-section aside.content-block--note", count: 1, text: /Words inside/
  end
```

Add to `test/models/audit/snapshot_test.rb`, after the Code block's tests:

```ruby
  # The first translated schema field of a built-in type: the snapshot holds
  # the title in each language as `translated_settings`, and a changes row
  # holds the column's old and new value (no Mobility column, no code field).
  test "a note's translated title is in the snapshot per language, and its change is the column's old and new value" do
    with_locales(%w[en de], default: "en") do
      saved = ContentBlocks::Save.call(create_page(title: "With a note").content_blocks.new, attributes: { block_type: "note", settings: { "kind" => "tip", "title" => "Before" } })
      assert saved.ok?, saved.errors.to_sentence
      block = saved.record

      assert ContentBlocks::Save.call(block, translations: { "de" => { settings: { "title" => "Vorher" } } }).ok?

      changes = Audit::Snapshot.field_changes_for(block)
      assert_equal [ { "en" => { "title" => "Before" } }, { "en" => { "title" => "Before" }, "de" => { "title" => "Vorher" } } ], changes["translated_settings"]
      assert_equal({ "en" => { "title" => "Before" }, "de" => { "title" => "Vorher" } }, Audit::Snapshot.for(block.reload)["translated_settings"])
      assert_equal({ "kind" => "tip" }, Audit::Snapshot.for(block)["settings"])
    end
  end
```

Add to `test/components/admin/editor_screen/block_card_component_test.rb`, before the final `end`:

```ruby
  def note_block(page, kind: "tip", title: "Before you publish")
    block = page.content_blocks.new(block_type: "note", position: 0, settings: { "kind" => kind })
    block.assign_settings({ "title" => title }, locale: "en")
    block.save!
    block
  end

  # Note block spec, "CS Studio": the kind's icon in the head (plan ruling
  # 12), the kind's four buttons, the title with the kind's word as its
  # placeholder and its help line, then the text.
  test "a note's card: its kind's icon in the head, the kind's four buttons, the stored one checked, then the title with the kind's word as placeholder and its help, then the text" do
    page = create_page(title: "Note card")
    block = note_block(page)

    render_card(block, page: page)

    assert_selector ".admin-block-card__head span#block-#{block.id}-icon-card[data-block-icon=lightbulb]", count: 1
    assert_selector ".admin-block-card__head [data-block-icon]", count: 1
    assert_selector "fieldset#block-#{block.id}-kind legend", exact_text: "Kind"
    assert_equal %w[Note Tip Important Warning], self.page.all("fieldset#block-#{block.id}-kind label").map { |label| label.text.strip }
    assert_selector "input#block-#{block.id}-kind-tip[type=radio][checked]"
    title = self.page.find("input#block-#{block.id}-title")
    assert_equal "Before you publish", title.value
    assert_equal "Tip", title[:placeholder]
    assert_selector "p#block-#{block.id}-title-help", text: "kind"
    order = rendered_content.index("block-#{block.id}-kind") < rendered_content.index("block-#{block.id}-title") && rendered_content.index("block-#{block.id}-title") < rendered_content.index("admin-rich-text")
    assert order, "kind, then title, then the text"
  end

  test "on a translation tab a note's title is an input beside its English original, and its kind is a shared field" do
    with_locales(%w[en de], default: "en") do
      page = create_page(title: "Note tab")
      block = note_block(page)

      render_inline Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "de")

      assert_selector "input[name='block[settings][title]']:not([readonly]):not([disabled])"
      assert_selector "[data-original-for='title']", text: "Before you publish"
      assert_equal "Tip", self.page.find("input[name='block[settings][title]']")[:placeholder]
      assert_no_selector "input[type=radio]", visible: :all
      assert_selector "details[data-shared-fields] dd", text: "Tip", visible: :all
    end
  end
```

(`render_card` names its local `page`; inside these tests `page` is the site page and `self.page` the Capybara node, as in the test file's other cases. If a selector above does not match the card's real markup, e.g. the rich-text container's class, read `block_card_component.html.erb` and correct the selector, not the card.)

- [ ] **Step 2: Run the tests**

Run: `PGGSSENCMODE=disable bin/rails test test/services/translation_state_parity_test.rb test/services/ai/translate_test.rb test/integration/public_blocks_test.rb test/models/audit/snapshot_test.rb test/components/admin/editor_screen/block_card_component_test.rb`
Expected: PASS. A failure here is a gap in the path no built-in type has walked (spec, "Risks"): fix it in the code the failure names, add the fix's reason as a comment there, and name it in the spec's "As built" (Task 10).

- [ ] **Step 3: Commit**

```bash
git add test/services/translation_state_parity_test.rb test/services/ai/translate_test.rb test/integration/public_blocks_test.rb test/models/audit/snapshot_test.rb test/components/admin/editor_screen/block_card_component_test.rb
git commit -m "$(cat <<'EOF'
test: a note's translated title through the translation state, AI translation, the published copy, the audit snapshot and the card

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT
EOF
)"
```

---

### Task 7: contrast, 72 pairs and 16 on the strong band, and the strong band's look

**Files:**
- Modify: `app/assets/tailwind/themes/default/sections.css`, `test/support/contrast_measure.rb`
- Test: `test/integration/design_tokens_test.rb`

**Interfaces:**
- Consumes: the sixteen tokens (Task 5); `ContrastMeasure#resolve_colour`, `#mix`, `#contrast` (`test/support/contrast_measure.rb`, the contrast branch's shared measuring) and `DesignTokensTest#theme_tokens`, `#band_values`.
- Produces: `ContrastMeasure#resolve_colour` reads `color-mix(in srgb, var(a) N%, var(b))`; the strong band's sixteen re-values (every ground `var(--th-band-strong)`, every frame `var(--th-line)`, each kind's rule and ink its own colour).

- [ ] **Step 1: Write the failing tests**

In `test/support/contrast_measure.rb`, add a branch to `resolve_colour`, directly after the `color-mix(… transparent)` branch:

```ruby
    when /\Acolor-mix\(in srgb, var\((#{TOKEN})\) ([\d.]+)%, var\((#{TOKEN})\)\)\z/o
      top, share, bottom = $1, $2.to_f / 100, $3
      mix(resolve_colour(tokens, top, under: under, inside: inside), resolve_colour(tokens, bottom, under: under, inside: inside), share)
```

and amend the method's comment, after "…which a caller that expects one hands in.": "A colour mixed of two tokens with `color-mix(in srgb, var(a) N%, var(b))` (the Note block's tokens) is the two mixed, each read where the mix is."

Add to `test/integration/design_tokens_test.rb`, after the Note stylesheet tests of Task 5:

```ruby
  # Note block spec, "Contrast": the text, the link colour and the kind's
  # ink, each at 4.5:1 on the kind's ground, on the page, in a tinted band
  # and in a strong band, in both schemes. 4 kinds x 3 x 3 grounds x 2 = 72.
  # A note's ground is computed where it is declared: on the page and in a
  # tinted band it is the page's tint; a strong band re-values it to the
  # band's own ground.
  test "every note's text, link and word are readable on its ground, on the page, in a tinted band and in a strong band, in both themes" do
    pairs = 0
    theme_tokens.each do |theme, tokens|
      { "the page" => [ {}, "--th-paper" ], "a tinted band" => [ band_values("tinted"), "--th-band-tinted" ],
        "a strong band" => [ band_values("strong"), "--th-band-strong" ] }.each do |place, (inside, around)|
        outside = resolve_colour(tokens, around, inside: inside)
        NOTE_KINDS.each do |kind|
          ground = resolve_colour(tokens, "--th-note-#{kind}-ground", inside: inside, under: outside)
          [ "--th-ink", "--th-accent", "--th-note-#{kind}-ink" ].each do |token|
            ratio = contrast(ground, resolve_colour(tokens, token, inside: inside))
            assert_operator ratio, :>=, 4.5, "#{token} on the #{kind} ground in #{place} (#{theme}) is #{ratio.round(2)}:1"
            pairs += 1
          end
        end
      end
    end
    assert_equal 72, pairs
  end

  # Spec decision 10 (Claude Design D4b), plan ruling 8: on a strong band a
  # note shares the band's ground and its text is the band's, but each kind
  # keeps its colour on its rule and its icon (the ink, which colours the
  # word too): Note the band's dim and text, Important the band's accent,
  # Tip and Warning their hue mixed with the band's text. The band is a dark
  # ground in both schemes, so these are light inks in both, each at 3:1 or
  # better against the band (the ink is held at 4.5:1 above, as text).
  test "on a strong band a note shares the band's ground and each kind keeps its colour: its rule and its icon at 3:1 against the band in both themes; a tinted band leaves the notes alone" do
    strong = band_values("strong")
    expected = {
      "note" => %w[var(--th-on-band-strong-dim) var(--th-on-band-strong)],
      "tip" => [ "color-mix(in srgb, var(--th-ok) 60%, var(--th-on-band-strong))" ] * 2,
      "important" => %w[var(--th-on-band-strong-accent)] * 2,
      "warning" => [ "color-mix(in srgb, var(--th-warn) 60%, var(--th-on-band-strong))" ] * 2
    }
    expected.each do |kind, (line, ink)|
      assert_equal "var(--th-band-strong)", strong["--th-note-#{kind}-ground"], "#{kind}: the band's ground"
      assert_equal line, strong["--th-note-#{kind}-line"], "#{kind}'s rule"
      assert_equal ink, strong["--th-note-#{kind}-ink"], "#{kind}'s word and icon"
      assert_equal "var(--th-line)", strong["--th-note-#{kind}-border"], "#{kind}: the band's line"
    end
    assert_no_match(/danger/, strong.select { |name, _| name.start_with?("--th-note-") }.values.join(" "), "no kind is red on the band either")
    assert_empty band_values("tinted").keys.grep(/--th-note-/)

    pairs = 0
    theme_tokens.each do |theme, tokens|
      band = resolve_colour(tokens, "--th-band-strong")
      inks = NOTE_KINDS.map { |kind| resolve_colour(tokens, "--th-note-#{kind}-ink", inside: strong) }
      assert_equal 4, inks.uniq.size, "#{theme}: four kinds, four colours on the band"
      NOTE_KINDS.each do |kind|
        %w[line ink].each do |part|
          ratio = contrast(band, resolve_colour(tokens, "--th-note-#{kind}-#{part}", inside: strong))
          assert_operator ratio, :>=, 3.0, "the #{kind}'s #{part} against a strong band (#{theme}) is #{ratio.round(2)}:1"
          pairs += 1
        end
      end
    end
    assert_equal 16, pairs
  end

  test "the measuring reads a colour mixed of two tokens as the two mixed" do
    tokens = { "--th-paper" => "#ffffff", "--th-ink" => "#000000", "--th-x" => "color-mix(in srgb, var(--th-ink) 50%, var(--th-paper))" }

    assert_equal mix(resolve_colour(tokens, "--th-ink"), resolve_colour(tokens, "--th-paper"), 0.5), resolve_colour(tokens, "--th-x")
    assert_operator contrast(resolve_colour(tokens, "--th-x"), resolve_colour(tokens, "--th-paper")), :<, 4.5, "a half-way grey on white is under 4.5"
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `PGGSSENCMODE=disable bin/rails test test/integration/design_tokens_test.rb test/lib/admin_contrast_test.rb`
Expected: FAIL: the strong band's pairs ("--th-ink on the tip ground in a strong band (light) is 1.0x:1": the page's light tint under the band's light text) and the band test (no `--th-note-*` in `sections.css`). `admin_contrast_test.rb` passes: the new branch only adds a notation.

- [ ] **Step 3: Implement**

In `app/assets/tailwind/themes/default/sections.css`, inside `.content-section--strong { … }`, after the seven `--th-syn-*` lines:

```css
  /* A note on this band (note block spec, decision 10; plan ruling 8)
     shares the band's ground and its text is the band's, as code's is; left
     alone its ground would stay the page's light tint, computed on the page,
     under the band's light text. Each kind keeps its colour on its rule and
     its icon (the ink, which colours the word too): the band is a dark
     ground in both schemes, so the inks are light in both, a kind's hue
     mixed with the band's text, and Important the band's own accent. The
     lowest is Tip's ink in dark, 6.6:1 against the band
     (test/integration/design_tokens_test.rb). */
  --th-note-note-ground: var(--th-band-strong);
  --th-note-note-line: var(--th-on-band-strong-dim);
  --th-note-note-ink: var(--th-on-band-strong);
  --th-note-note-border: var(--th-line);
  --th-note-tip-ground: var(--th-band-strong);
  --th-note-tip-line: color-mix(in srgb, var(--th-ok) 60%, var(--th-on-band-strong));
  --th-note-tip-ink: color-mix(in srgb, var(--th-ok) 60%, var(--th-on-band-strong));
  --th-note-tip-border: var(--th-line);
  --th-note-important-ground: var(--th-band-strong);
  --th-note-important-line: var(--th-on-band-strong-accent);
  --th-note-important-ink: var(--th-on-band-strong-accent);
  --th-note-important-border: var(--th-line);
  --th-note-warning-ground: var(--th-band-strong);
  --th-note-warning-line: color-mix(in srgb, var(--th-warn) 60%, var(--th-on-band-strong));
  --th-note-warning-ink: color-mix(in srgb, var(--th-warn) 60%, var(--th-on-band-strong));
  --th-note-warning-border: var(--th-line);
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails theme_css:build && PGGSSENCMODE=disable bin/rails test test/integration/design_tokens_test.rb test/lib/admin_contrast_test.rb test/values/theme/contract_test.rb`
Expected: PASS. Computed beforehand with the contrast branch's values: the lowest of the 72 is 4.88:1 (the accent on the light Important ground); on the strong band the lowest is Tip's ink and rule in dark, 6.64:1 (light: 7.06:1), and Important's 7.05:1 in dark. If a pair falls under its floor, lower that scheme's ground share in `tokens.css` (12% to 10% in the dark block, 8% to 6% in the light) or the band's mix share (60% to 50% of the hue), and say the new lowest figure in the comment beside it.

- [ ] **Step 5: Commit**

```bash
git add app/assets/tailwind/themes/default/sections.css test/support/contrast_measure.rb test/integration/design_tokens_test.rb
git commit -m "$(cat <<'EOF'
feat: a note on a strong band shares its ground and keeps its kind's colour, and its 72 and 16 contrast pairs are held

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT
EOF
)"
```

---

### Task 8: the Note in CS Studio: saves, refusals, a browser file

**Files:**
- Test: `test/integration/admin/content_blocks_test.rb`, `test/components/admin/editor_screen/held_fields_test.rb`
- Create: `test/system/admin/note_block_test.rb`

**Interfaces:**
- Consumes: everything above; `blocks_path`, `sign_in_as`, `travel` (integration); `sign_in_via_form`, `await_admin_controllers`, `await_notes_live`, `assert_writes_settled`, `press`, `using_session` (system).
- Produces: tests only.

- [ ] **Step 1: Write the integration and held-form tests**

Add to `test/integration/admin/content_blocks_test.rb`, before the final `end`:

```ruby
  # --- the Note block (note block spec, "CS Studio") ---

  def note_block(**attributes) = @page.content_blocks.create!(block_type: "note", position: 0, **attributes)

  def save_note(block, settings, base: block.reload.updated_at.iso8601(6), tab: nil, locale: nil, **more)
    path = "#{blocks_path}/#{block.id}#{"?locale=#{locale}" if locale}"
    patch path, params: { block: { settings: settings, **more }, base_updated_at: base }, as: :turbo_stream, headers: { "X-Notes-Tab" => tab }.compact
  end

  test "adding a Note streams its card with the kind's four buttons, Note checked, and its kind and title are saved, the card's icon following the kind" do
    post blocks_path, params: { block: { block_type: "note" } }, as: :turbo_stream
    assert_response :success
    block = @page.content_blocks.last
    assert_equal({ "kind" => "note" }, block.settings)
    assert_select "turbo-stream template input[type=radio][name='block[settings][kind]']", count: 4
    assert_select "turbo-stream template input[type=radio][value='note'][checked]"
    assert_select "turbo-stream template .admin-block-card__head span#block-#{block.id}-icon-card[data-block-icon='info']"

    save_note(block, { kind: "tip", title: "  Before you publish  " })

    assert_response :success
    assert_equal({ "kind" => "tip" }, block.reload.settings)
    assert_equal({ "en" => { "title" => "Before you publish" } }, block.translated_settings)
    assert_select "turbo-stream[action='replace'][target='block-#{block.id}-icon-card'] template span[data-block-icon='lightbulb']"
  end

  # Review focus 2: a kind stored around the services checks no button and
  # is refused as it stands; picking one saves.
  test "a note whose stored kind is not on the list is refused as it stands, and picking a kind saves" do
    block = note_block
    block.update_columns(settings: { "kind" => "danger" }) # version: none (a test writes a kind around the services)

    save_note(block, { title: "x" })
    assert_response :unprocessable_entity
    assert_select "turbo-stream[target='block-#{block.id}-kind-errors'] template", text: /Kind is not included in the list/

    save_note(block, { kind: "warning", title: "x" })
    assert_response :success
    assert_equal "warning", block.reload.settings["kind"]
  end

  # Review focus 5, plan ruling 2.
  test "a note's title over 80 characters is refused on the German tab too, and nothing is written" do
    with_locales(%w[en de], default: "en") do
      block = note_block
      stamp = block.reload.updated_at

      assert_no_difference -> { Audit::Event.count } do
        save_note(block, { title: "x" * 81 }, locale: "de")
      end
      assert_response :unprocessable_entity
      assert_select "turbo-stream[target='block-#{block.id}-title-errors'] template", text: /Title is too long \(maximum is 80 characters\)/
      assert_equal({}, block.reload.translated_settings)
      assert_equal stamp, block.updated_at

      save_note(block, { title: "x" * 81 })
      assert_response :unprocessable_entity

      save_note(block, { title: "x" * 80 }, locale: "de")
      assert_response :success
      assert_equal "x" * 80, block.reload.translated_settings.dig("de", "title")
    end
  end

  test "a Note's save is refused when it is stale and when another tab holds it, like any block's" do
    block = note_block
    base = block.updated_at.iso8601(6)

    save_note(block, { kind: "tip" }, base: base, tab: "tab-aaaaaaaa")
    assert_response :success
    travel 1.minute do
      save_note(block, { kind: "warning" }, base: base, tab: "tab-aaaaaaaa")
    end
    assert_response :conflict
    assert_equal "tip", block.reload.settings["kind"]

    sign_in_as users(:two)
    save_note(block, { kind: "important" }, tab: "tab-bbbbbbbb")
    assert_response :conflict
    assert_equal "tip", block.reload.settings["kind"]
  end

  test "a Note in a column says its kind and text on its tile, is duplicated with its title and text, and is deleted" do
    section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "two" })
    post blocks_path, params: { block: { block_type: "note", section_id: section.id, column: 2 } }, as: :turbo_stream
    assert_response :success
    block = @page.content_blocks.find_by!(block_type: "note")
    assert_equal [ section.id, 2 ], [ block.section_id, block.section_column ]

    save_note(block, { kind: "important", title: "Read this" })
    assert_response :success
    assert_select "turbo-stream[target='block-#{block.id}-tile-summary'] template", text: /Read this · Empty/
    assert_select "turbo-stream[target='block-#{block.id}-tile-summary'] template svg", count: 0
    assert_select "turbo-stream[action='replace'][target='block-#{block.id}-icon-tile'] template span[data-block-icon='circle_alert']"
    assert_select "turbo-stream[action='replace'][target='block-#{block.id}-icon-card'] template span[data-block-icon='circle_alert']"

    post "#{blocks_path}/#{block.id}/duplicate", as: :turbo_stream
    assert_response :success
    copy = @page.content_blocks.where(block_type: "note").where.not(id: block.id).sole
    assert_equal [ { "kind" => "important" }, { "en" => { "title" => "Read this" } } ], [ copy.settings, copy.translated_settings ]

    delete "#{blocks_path}/#{copy.id}", as: :turbo_stream
    assert_response :success
    assert_not ContentBlock.exists?(copy.id)
  end
```

(Check the duplicate and delete routes against the existing Code block test "a Code block in a column says its file name on its tile, is duplicated…" in the same file and copy its calls if they differ.)

Add to `test/components/admin/editor_screen/held_fields_test.rb`, before the final `end`:

```ruby
  # Plan ruling 10: a note's card held by someone else keeps its stored
  # kind checked and disables every button, the title is read-only with its
  # text, and its placeholder script reads only, so it is no action to keep.
  test "a note's card, rewritten; held by someone else its kind's buttons are disabled with the stored one checked, its title read-only, and no save is wired" do
    page = create_page(title: "Held note")
    block = page.content_blocks.new(block_type: "note", position: 0, settings: { "kind" => "warning" })
    block.assign_settings({ "title" => "Mind" }, locale: "en")
    block.save!
    as_owner { render_inline Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en", editable: true) }
    assert_survives(rendered_content)

    reserve(block, page, users(:two), "tab-bbbbbbbb")
    as_viewer(users(:one), tab: "tab-aaaaaaaa") { render_inline Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en") }
    held = Nokogiri::HTML5.fragment(rendered_content)

    assert_equal [ "disabled" ] * 4, held.css("fieldset.admin-held input[type=radio]").map { |radio| radio["disabled"] }
    assert_equal [ "warning" ], held.css("input[type=radio][checked]").map { |radio| radio["value"] }
    assert_selector "fieldset.admin-held input[name='block[settings][title]'][readonly][value='Mind']"
    assert_no_selector "[data-controller~='admin--saving--autosave']"
    assert_empty held.css("fieldset.admin-held [data-action]").flat_map { |node| node["data-action"].split }.grep(/placeholder-from/),
      "the placeholder script listens without an action, so there is nothing of it to keep"
  end
```

- [ ] **Step 2: Run them**

Run: `PGGSSENCMODE=disable bin/rails test test/integration/admin/content_blocks_test.rb test/components/admin/editor_screen/held_fields_test.rb`
Expected: PASS.

- [ ] **Step 3: Write the browser file**

Create `test/system/admin/note_block_test.rb`:

```ruby
require "application_system_test_case"

# The Note block's card in the page editor, in a browser (note block spec,
# "CS Studio"): the kind chosen from the keyboard on a segmented control,
# the title's placeholder following the kind before the save, the card's
# icon following it after the save (plan ruling 12), the title and
# the text typed and saved by themselves and back after a reload; and a
# second person's card read-only while the first holds it.
class Admin::NoteBlockSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    users(:one).update!(name: "Olga Braun")
    @page = create_page(title: "Guide", published: false)
    sign_in_via_form(users(:one))
  end

  def open_editor
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    await_notes_live
  end

  def kind(block, value) = find("#block-#{block.id}-kind-#{value}", visible: :all)

  def title_field(block) = find("#block-#{block.id}-title")

  test "a Note added from the picker is a Note; its kind is chosen with the arrow keys, the title's placeholder follows it, and all of it is saved and back after a reload" do
    open_editor
    within("#block-picker-end") { press "Note" }
    # wait: the card is the answer to the request that creates the block, on a runner with two slow cores.
    assert_selector ".admin-block-card fieldset input[type=radio][name='block[settings][kind]']", visible: :all, count: 4, wait: 8
    block = @page.content_blocks.sole
    await_admin_controllers

    assert kind(block, "note").checked?
    assert_equal "Note", title_field(block)[:placeholder]

    assert_selector "#block-#{block.id}-icon-card[data-block-icon=info]"
    find("label[for='block-#{block.id}-kind-note']").click
    kind(block, "note").send_keys(:right)
    assert_selector "#block-#{block.id}-kind-tip:checked", visible: :all
    assert_equal "Tip", title_field(block)[:placeholder], "the placeholder follows the kind before the save"
    # Plan ruling 12: the card's icon follows the kind once the save's answer is here.
    assert_selector "#block-#{block.id}-icon-card[data-block-icon=lightbulb]"

    title_field(block).set("Before you publish")
    find("#content_block_#{block.id} .ProseMirror").send_keys("Mind the address.")
    assert_writes_settled
    block.reload
    assert_equal "tip", block.settings["kind"]
    assert_equal({ "en" => { "title" => "Before you publish" } }, block.translated_settings)
    assert_equal [ "Mind the address." ], block.body_document(locale: :en).plain_paragraphs

    open_editor
    assert kind(block, "tip").checked?
    assert_equal "Before you publish", title_field(block).value
    assert_equal "Tip", title_field(block)[:placeholder]
    assert_selector "#block-#{block.id}-icon-card[data-block-icon=lightbulb]", count: 1
  end

  test "while one person types a note's title, a second person's card is read-only: every kind's button disabled, the title read-only with the same text" do
    block = @page.content_blocks.create!(block_type: "note", position: 0, settings: { "kind" => "warning" })
    open_editor
    title_field(block).set("Mind the gap")
    assert_writes_settled
    assert_equal "Mind the gap", block.reload.settings_object(locale: "en").title

    using_session(:dana) do
      sign_in_via_form(users(:two))
      open_editor

      assert_selector "#content_block_#{block.id}[data-editing-held=true] [data-editing-kind=held]", text: "Olga Braun is editing this block"
      assert_selector "#block-#{block.id}-title[readonly]"
      assert_equal "Mind the gap", title_field(block).value
      BlockTypes::Note::KINDS.each_key { |value| assert kind(block, value).disabled?, value }
      assert kind(block, "warning").checked?
    end
  end
end
```

- [ ] **Step 4: Build and run the browser file**

Run: `sysctl -n vm.loadavg` (a load near the core count is not quiet: wait), then `bin/rails tailwindcss:build && bin/rails theme_css:build`, then `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/admin/note_block_test.rb`
Expected: PASS, no JavaScript error. If the keyboard step fails because the radio is not focused by the label's click, focus it with `kind(block, "note").execute_script("this.focus()") # focus: an sr-only radio has no box a click lands on` and keep `send_keys(:right)`; do not set the radio's state by script.

- [ ] **Step 5: Commit**

```bash
git add test/integration/admin/content_blocks_test.rb test/components/admin/editor_screen/held_fields_test.rb test/system/admin/note_block_test.rb
git commit -m "$(cat <<'EOF'
test: the Note block in CS Studio: saves, refusals, the held card and a browser file

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT
EOF
)"
```

---

### Task 9: the Note on the public site, in a browser, in both schemes

**Files:**
- Create: `test/system/note_block_test.rb`
- Test: `test/integration/public_javascript_test.rb` (one case)

**Interfaces:**
- Consumes: the public component, `note.css`, the tokens and the strong band (Tasks 4, 5, 7).
- Produces: tests only.

- [ ] **Step 1: Write the browser file**

Create `test/system/note_block_test.rb`:

```ruby
require "application_system_test_case"

# The Note block on the public site, as the browser computes it (note block
# spec, "The public side"): each kind in its own four tokens in both schemes,
# the text, links and inline code in the theme's; on a strong band the
# band's ground with the kind's own colour on its rule and word (decision
# 10); and an editor's title seen alone and heard after the kind's word
# (decision 6).
class NoteBlockSystemTest < ApplicationSystemTestCase
  KINDS = BlockTypes::Note::KINDS.keys.freeze
  TEXT = "Read [the guide](https://example.com/guide) and run `bin/setup` first.".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Guide")
  end

  def add_note(kind, title: nil, **attributes)
    settings = { "kind" => kind, "title" => title }.compact
    result = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "note", settings: settings }.merge(attributes),
      translations: { "en" => { body: rich_doc(TEXT) } })
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def open_page
    publish_changes(@page)
    visit PublicSite::Urls.new.path_for(@page, "en")
    assert_selector "aside.content-block--note"
  end

  def with_theme(theme)
    page.execute_script("document.documentElement.dataset.theme = arguments[0]", theme)
    yield
  ensure
    page.execute_script("document.documentElement.dataset.theme = 'light'")
  end

  # What a note is drawn in, and what its tokens are THERE: a probe span is
  # put inside the note, so a band's values are what it reads.
  def probe(block)
    page.evaluate_script(<<~JS, "note-#{block.id}-heading")
      (() => {
        const head = document.getElementById(arguments[0])
        const note = head.closest("aside")
        const kind = [...note.classList].find((name) => /^content-block--note-/.test(name)).replace("content-block--note-", "")
        const token = (name, property = "color") => { const span = document.createElement("span"); span.style[property] = `var(${name})`; note.append(span); const value = getComputedStyle(span)[property]; span.remove(); return value }
        const style = getComputedStyle(note)
        const code = note.querySelector(".note-body code")
        return {
          ground: style.backgroundColor, groundToken: token(`--th-note-${kind}-ground`, "backgroundColor"),
          rule: [style.borderLeftWidth, style.borderLeftColor], line: token(`--th-note-${kind}-line`),
          frame: [style.borderTopWidth, style.borderTopColor], border: token(`--th-note-${kind}-border`),
          word: getComputedStyle(head).color, ink: token(`--th-note-${kind}-ink`),
          text: getComputedStyle(note.querySelector(".note-body")).color, textToken: token("--th-ink"),
          link: getComputedStyle(note.querySelector(".note-body a")).color, accent: token("--th-accent"),
          code: [getComputedStyle(code).backgroundColor, getComputedStyle(code).borderTopWidth], surface: token("--th-surface", "backgroundColor"),
          icon: [head.querySelector("svg").getBoundingClientRect().width, head.querySelector("svg").getAttribute("aria-hidden")],
          named: note.getAttribute("aria-labelledby") === head.id, heading: head.textContent.trim(), bandInk: token("--th-on-band-strong"),
          band: token("--th-band-strong", "backgroundColor"), element: head.tagName
        }
      })()
    JS
  end

  test "each kind is drawn in its own tokens in both schemes: its ground, its 3px rule, its frame and its word, with the text, links and inline code the theme's" do
    notes = KINDS.map { |kind| add_note(kind) }
    open_page

    %w[light dark].each do |theme|
      with_theme(theme) do
        seen = notes.map { |block| probe(block) }
        seen.zip(KINDS).each do |found, kind|
          where = "#{theme}, #{kind}"
          assert_equal found["groundToken"], found["ground"], "#{where}: ground"
          assert_equal [ "3px", found["line"] ], found["rule"], "#{where}: rule"
          assert_equal [ "1px", found["border"] ], found["frame"], "#{where}: frame"
          assert_equal found["ink"], found["word"], "#{where}: word"
          assert_equal found["textToken"], found["text"], "#{where}: text"
          assert_equal found["accent"], found["link"], "#{where}: link"
          assert_equal [ found["surface"], "1px" ], found["code"], "#{where}: inline code"
          assert_equal [ 16, "true" ], found["icon"], "#{where}: icon"
          assert found["named"], "#{where}: the aside is named by its heading"
          assert_equal "H3", found["element"], "#{where}: the heading is a heading"
          assert_equal BlockTypes::Note::KINDS.fetch(kind), found["heading"]
        end
        assert_equal 4, seen.map { |found| found["ground"] }.uniq.size, "#{theme}: four kinds, four grounds"
      end
    end
  end

  test "in a strong band a note shares the band's ground in both schemes, its text the band's, its rule and word its kind's own colour" do
    section = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "section", settings: { "layout" => "one", "background" => "strong" } }).record
    inside = add_note("tip", section_id: section.id, section_column: 1)
    outside = add_note("tip")
    open_page
    assert_selector ".content-section--strong aside.content-block--note", count: 1

    %w[light dark].each do |theme|
      with_theme(theme) do
        banded = probe(inside)
        plain = probe(outside)
        assert_equal banded["band"], banded["ground"], "#{theme}: the band's ground"
        assert_equal banded["groundToken"], banded["ground"], "#{theme}: the note's ground token is the band's there"
        assert_equal banded["bandInk"], banded["text"], "#{theme}: the text is the band's ink"
        assert_equal banded["ink"], banded["word"], "#{theme}: the word is the kind's ink there"
        assert_equal [ "3px", banded["line"] ], banded["rule"], "#{theme}: the rule is the kind's line there"
        assert_not_equal banded["bandInk"], banded["word"], "#{theme}: the kind keeps a colour of its own on the band"
        assert_not_equal plain["ground"], banded["ground"], "#{theme}: not the page's tint"
      end
    end
  end

  # Spec decision 6: the kind's word before an editor's title is in the
  # heading's text, so a screen reader reads it, and takes no room on screen.
  test "an editor's title is seen alone and heard after the kind's word, in both schemes" do
    block = add_note("tip", title: "Before you publish")
    open_page

    %w[light dark].each do |theme|
      with_theme(theme) do
        found = page.evaluate_script(<<~JS, "note-#{block.id}-heading")
          (() => {
            const head = document.getElementById(arguments[0])
            const box = head.querySelector(".note-kind").getBoundingClientRect()
            return { said: head.textContent.replace(/\s+/g, " ").trim(), width: box.width, height: box.height }
          })()
        JS
        assert_equal "Tip: Before you publish", found["said"], theme
        assert_operator found["width"], :<=, 1, "#{theme}: the word takes no room"
        assert_operator found["height"], :<=, 1, "#{theme}: the word takes no room"
      end
    end
  end
end
```

Add to `test/integration/public_javascript_test.rb`, beside "a public page with a Code block carries the copy controller and no admin script":

```ruby
  test "a public page with a Note block needs no script: it carries no controller of its own and no admin script" do
    page = create_page(title: "Guide")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "note", settings: { "kind" => "tip" } },
      translations: { "en" => { body: rich_doc("Words.") } }).ok?
    publish_changes(page)

    get PublicSite::Urls.new.path_for(page, "en")

    assert_select "aside.content-block--note-tip:not([data-controller])"
    assert_no_match(%r{controllers/admin/}, response.body)
  end
```

(If the file's other cases assert the absence of admin scripts another way, use that way.)

- [ ] **Step 2: Build and run**

Run: `sysctl -n vm.loadavg`, then `bin/rails tailwindcss:build && bin/rails theme_css:build`, then `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test test/system/note_block_test.rb` and `PGGSSENCMODE=disable bin/rails test test/integration/public_javascript_test.rb`
Expected: PASS, no JavaScript error.

- [ ] **Step 3: Commit**

```bash
git add test/system/note_block_test.rb test/integration/public_javascript_test.rb
git commit -m "$(cat <<'EOF'
test: the Note block on the public site in a browser, both schemes and a strong band

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT
EOF
)"
```

---

### Task 10: the documents, and the whole check

**Files:**
- Modify: `docs/reference/content-blocks-and-types.md`, `docs/reference/theming.md` (if Task 5 left anything), `docs/reference/i18n.md`, `docs/reference/design-system.md`, `docs/reference/translations.md`, `CLAUDE.md`, `docs/roadmap.md`, `docs/superpowers/specs/2026-10-13-note-block-design.md` ("As built")
- Test: the whole suite

**Interfaces:**
- Consumes: everything above.
- Produces: documents; the text for the pull request.

- [ ] **Step 1: `docs/reference/content-blocks-and-types.md`**

- The "Describes:" line: add "and for the Note block `app/models/block_types/note.rb`, `app/components/blocks/note_component.rb` and its template, `app/assets/tailwind/themes/default/note.css`, `app/javascript/controllers/admin/ui/placeholder_from_controller.js`".
- "## Content blocks": the type list reads `rich_text` / `image` / `code` / `note` / `post_list` / `section`.
- A section "## The Note block" after "## The Code block", in the file's own voice: what it is (spec, design answers B1 to B3); where each value is stored (kind in `settings`, title in `translated_settings`, the first translated schema field of a built-in type, text in `body`; no column, no migration, no service); "Four things the schema learned for it": `control: :segmented` (Task 1, its refusals, `HeldFields`, never on a translation tab), `max:` on a string in every language (ruling 2), `help:` and `placeholder_from:` with `admin--ui--placeholder-from` (ruling 3, and its limit: only the block card hands a placeholder over); the public component (the eight names and why `word` is one, ruling 13; `render?`; the aside and its `h3`, ruling 14; the hidden kind word under a title and a title that is only the word; the icon inline; `kind_of`); the stylesheet, the hues (ruling 7) and the strong band (ruling 8); the card, the tile and the icon that follows the kind (`t.icon "info", for_block:`, rulings 6, 11 and 12, and why the spec's `[:icon, name]` part was not built), the translation tab (ruling 10); the translation state (ruling 5); limits as built (each a roadmap row: the four words are English until the public site is translated; a post type's field with `placeholder_from:` has no placeholder; an outside type's icon cannot follow its block). Name each test by its title in quotes, as the Code block's section does.
- "## Adding a block type": in step 2's first bullet, the options list reads `required`, `default`, `min`, `max`, `translated`, `options`, `of`, `blank`, `label`, `control`, `help` and `placeholder_from`; in step 2's declarations table, the `icon "<name>"` row names the four new icons in its list and adds "`, for_block: ->(block) { … }` (a built-in's only): the icon of each block on its card and tile, one of the same list; the picker draws the type's"; in step 8's icon bullet, add "A type whose icon follows a value of its block declares `for_block:` (the Note block's kind); its icon then carries an id and every save's answer redraws it (`Admin::ContentBlocksController#block_icon_streams`); an outside type may not, yet"; in step 3's last paragraph, after `blank:`, `label:`, add `control:`, `help:`, `placeholder_from:` as the Note block's options.

- [ ] **Step 2: the other reference files**

- `docs/reference/theming.md`: check that "The Note block", the sixteen token rows, the component row and "In tests" are in (Task 5); add, under "### The Code block"'s neighbour "The types' stylesheets, and their order" if it lists the declared stylesheets by name, `note.css`.
- `docs/reference/i18n.md`, "A string of the public site": the Note block's four words (`public.blocks.note.kinds.*`, read by `Blocks::NoteComponent#word` with English as the explicit fallback) beside the Code block's four.
- `docs/reference/design-system.md`: one paragraph on the segmented control (`Admin::Fields::SelectField::SEGMENT_CLASS`, a field's `control: :segmented`, the posts list's scope toggle as its look) and on a field's help line (`help:`, `aria-describedby`).
- `docs/reference/translations.md`: one sentence that a block type's translated schema field is tracked, translated by AI (as plain text, `TRANSLATABLE_TYPES`) and copied like a column, the Note block's title being the first built-in one, with the test names of Task 6.

- [ ] **Step 3: `CLAUDE.md`**

- In the reference index's content-blocks bullet, after the Code block's files: "or the Note block, a schema field's `control:`, `help:` or `placeholder_from:`, or a block type's icon that follows its block (`icon … for_block:`) (`app/models/block_types/note.rb`, `app/components/blocks/note_component.*`, `app/assets/tailwind/themes/default/note.css`, `app/components/admin/fields/select_field.*`, `string_field.*`, `app/javascript/controllers/admin/ui/placeholder_from_controller.js`, `app/models/content_model/block_type_definition.rb`, `app/components/admin/editor_screen/block_icon_component.rb`)".
- One rule under "Rules a change can break silently", after the Code block's rules:

  "- The Note block's sixteen `--th-note-*` tokens are defined in `tokens.css` from the base tokens (`var()` and `color-mix(in srgb, …)` of them, never a literal; Note neutral, Tip `--th-ok`, Important `--th-accent`, Warning `--th-warn`, none `--th-danger`), and a strong band re-values all sixteen in `sections.css`, because a note's ground is computed on the page and would stay a light tint under the band's light text: the band's ground, the band's text, and each kind's rule and ink a light colour of its own, since the band is dark in both schemes; a new kind, or a new ground a note can stand on, is four tokens, a ledger line with its release note and its pairs in the contrast test (`test/integration/design_tokens_test.rb`: \"every note's text, link and word are readable on its ground, on the page, in a tinted band and in a strong band, in both themes\", 72 pairs; \"on a strong band a note shares the band's ground and each kind keeps its colour…\", 16 pairs at 3:1; \"the sixteen note tokens are defined from the theme's base tokens in both schemes, never a literal, each kind in its hue and none in red\"). A note's heading is an `h3` and text, its icon `aria-hidden`, and under an editor's title it starts with the kind's `word`, visually hidden, which it never has without one (`test/components/blocks/note_component_test.rb`: \"a title that looks like markup is text\", \"an editor's title replaces the word on screen, the word is heard once before it, hidden, and the icon and the kind stay\", \"without a title the heading is the kind's word alone, said once, and there is no hidden word\"). A block type's icon that follows its block (`icon … for_block:`) answers a name from `BlockTypeDefinition::ICONS` and is redrawn by id with every save (`test/components/admin/editor_screen/block_icon_component_test.rb`: \"a type whose icon follows its block draws the block's own on its card and its tile, under an id a save's answer replaces, and the type's in the picker\"; `test/integration/admin/content_blocks_test.rb`: \"a save of a block whose icon follows it redraws the icon on its card and its tile; another type's save redraws none\"). **No guard** that a theme's own Note template says the kind to a screen reader under an editor's title."

- [ ] **Step 4: `docs/roadmap.md` and the spec**

- "## Shipped": a row "The Note block: a sixth block type … (four kinds by word and icon, an optional translated title, a rich text; a segmented control for the kind; sixteen tokens from the theme's base; 72 contrast pairs)" | `2026-10-13-note-block-design.md`.
- "## Next, in order", item 2: "6 block types (rich text, image, code, note, post list, section)"; item 9's Note sentences say it shipped and that the documentation theme's `--th-note-line` gives way to `--th-note-note-line` in its own repository; the "Note and Table block types" entry: Note shipped (date), Table next.
- New rows where the file keeps gaps (under the Code block's or "Content model and extension"): a post type's field with `placeholder_from:` shows no placeholder; the four words are English until the public site's strings are translated (item 7); an outside type's icon cannot follow its block (`for_block:` is a built-in's, ruling 12); nothing checks that a theme's own Note template says the kind under an editor's title.
- The spec: an "## As built" section listing plan rulings 1 to 14 in one line each (13, `word` as an eighth name, and 12, `icon … for_block:` in place of the `[:icon, name]` part, are departures from "The data", "The public side" and "CS Studio" and say so), the files, and any fix Task 6 needed.

- [ ] **Step 5: The whole check**

Run each, in this order, and read every result (a run that took twice its usual time on a busy machine is not a result: `sysctl -n vm.loadavg` first):

```bash
bin/rubocop
bin/brakeman
bin/bundler-audit
bin/importmap audit
PGGSSENCMODE=disable bin/rails zeitwerk:check
PGGSSENCMODE=disable bin/rails test
bin/rails tailwindcss:build && bin/rails theme_css:build
PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test:system
bin/theme-build-check
```

Expected: every command exits 0; `bin/theme-build-check` is run alone, with no test run and no `bin/dev` beside it.

- [ ] **Step 6: Commit**

```bash
git add docs/reference CLAUDE.md docs/roadmap.md docs/superpowers/specs/2026-10-13-note-block-design.md
git commit -m "$(cat <<'EOF'
docs: the Note block in the reference, CLAUDE.md, the roadmap and the spec's As built

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT
EOF
)"
```

- [ ] **Step 7: The pull request's text (do not push; the owner opens the PR)**

The body's "Documentation" and release-note parts, for whoever opens the pull request:

```markdown
## Release note (theme contract)

- New component line `blocks/note_component`: `block`, `page`, `kind`, `heading`, `titled?`, `word`, `icon`, `body`.
- Sixteen new themed tokens: `--th-note-{note,tip,important,warning}-{ground,line,ink,border}`, defined in the default theme from the base tokens (Note neutral, Tip ok, Important accent, Warning warn); on a strong band a note takes the band's ground and keeps each kind's colour on its rule and icon.

## Documentation

In `contentspiel-docs`, before this is released:

- `editors/pages/build-a-page-with-blocks.md`: the Note block (the four kinds, the optional title and that an empty one uses the kind's word, the text, that a note without text is not shown, and the kind's icon on the card and the tile).
- `integrators/theming/the-theme-contract.md`: the Note block's line (and that `word` is said, hidden, before an editor's title) and its sixteen tokens, with what a strong band does to them; the documentation theme renames its own `--th-note-line` to `--th-note-note-line` when it adopts the block.
- `integrators/how-it-works/adding-a-block-type.md`: `t.icon … for_block:`.
- The loader (`bin/load`): writes a real Note block in place of bold text in a paragraph; "To confirm" becomes a Warning with that title.
```

---

## Self-review

1. **Spec coverage.** Four kinds and default (Task 4); word and icon per kind (Tasks 3, 4); heading rule and translated words (Task 4); rich text body (Task 4); empty note draws nothing (Task 4); aside named by its heading, an `h3`, no alert (Tasks 4, 9; ruling 14); the hidden kind word before an editor's title only, never twice, a title that is only the word (decision 6: Tasks 4, 5, 6, 9; review focus 6); hues Note neutral, Tip ok, Important accent, Warning warn, none red (decision 9: Tasks 5, 7); on a strong band the band's ground, the band's text, each kind's colour on its rule and icon at 3:1 (decision 10: Tasks 7, 9; ruling 8); segmented control, radios, keyboard, no script needed (Tasks 1, 8); theme can restyle and replace (Task 5); generator and declarations, no capability (Task 4); ledger (Tasks 4, 5); unknown kind as Note (Tasks 4, 8); translated title through pair, state, AI, copy, snapshot (Task 6); component's names (Task 4: eight, ruling 13); inline SVG `aria-hidden` (Task 4); `note.css` tokens only (Task 5); sixteen tokens from the base, light and dark (Task 5); contrast 72 pairs, and 16 rule-and-icon pairs on the strong band (Task 7); inline code on surface with a line (Tasks 5, 9); card order, placeholder following the kind and help line (Tasks 2, 6, 8); segmented control read-only on a translation tab and held (Tasks 1, 6, 8); the kind's icon at 12px in `text-meta` on the tile and on the card's head, from a closed list, never markup, the tile's type name kept for a screen reader, one icon per place (Tasks 3, 4, 6, 8; rulings 11, 12); strings as keys (Task 4); recipe's shared tests from `sample`, at the top level and in a column (Tasks 4, 5, 6); one browser file for the editor and one for the site in both schemes (Tasks 8, 9); fixture theme from the reference alone (Task 5); documentation text (Task 10). **Two spec points are built differently, each a ruling and an open question for the owner:** the theme line's seven names become eight (`word`, ruling 13), and the `[:icon, name]` summary part becomes `icon … for_block:` (ruling 12). Decision 10's "dark-scheme kind inks" are derived as the kind's hue mixed with the band's text, because the strong band is dark in both schemes and a light-scheme page cannot read a dark-scheme token (ruling 8).
2. **Placeholders.** None: every code step carries its code; the two "if the file does it another way" notes in Task 8 and Task 9 name the file to copy from and keep the assertions. The contrast figures (4.88:1 lowest of the 72, 6.64:1 lowest on the strong band) were computed with the contrast branch's token values and `contrast_measure.rb`'s arithmetic before writing them.
3. **Type consistency.** `BlockTypes::Note::KINDS`, `ICONS` (Lucide spelling), `DEFAULT`, `TITLE_LENGTH`, `kind_of`, `studio_icon` (partial spelling), `summary` (text parts only); `BlockTypeDefinition::ICONS` (nine names), `#icon(name, for_block:)`, `#icon_follows_block?`, `#icon_for`; `BlockIconComponent.new(definition:, place:, block:)`, `.dom_id(block, place)`, ids `block-<id>-icon-card` and `block-<id>-icon-tile`; `ContentBlocksController#block_icon_streams`; `Field#segmented?`, `#help`; `Base#placeholder`, `#help_id`; `BlockCardComponent#placeholder_for`; `admin--ui--placeholder-from` with `source` and `labels`; theme names `block page kind heading titled? word icon body` in the definition, the ledger, the reference table, the contract test and the fixture theme; ids `block-<id>-kind`, `block-<id>-kind-<value>`, `block-<id>-title`, `block-<id>-title-help`, `note-<id>-heading` and class `note-kind` are used the same way in every task. No task names `TileSummaryComponent::ICONS`, `data-tile-icon`, an `[:icon, …]` part or a `--th-danger` note token any more.
4. **Review Focus.** Each of the six lines has its test in Task 4 or Task 8, named there.
