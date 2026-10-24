# The Note block

Status: approved (2026-10-13; corrected 2026-10-15 with Claude Design's D4 answers: hues, strong band, the hidden kind word; and for the block types build: declarations instead of a `:note` capability, `--th-ink` for the body text, tokens defined from the base). The design is Claude Design's, 2026-10-13 (B1 to B3). The owner agreed to the block and to the order "Note, then Table" the same day. The Table block is a spec of its own.

## Why

The guide has callouts ("Tip", "Warning", "To confirm") and the CMS has no block for one. The documentation site's loader writes them as bold text in a paragraph until a Note block exists; the roadmap names Note and Table as the fast follow of the Code block (item 9, 2026-10-12).

## What a person gets

**A visitor** reads a highlighted box in the flow of a page: a tinted ground, a coloured rule on the left, and at the top a small icon and a word that says what kind of note it is ("Tip"). Under it, the note's text.

**An editor** adds a "Note" block from the picker, chooses one of four kinds with four small buttons, may type a title of their own, and writes a short text. The text is translated like any other; so is a title.

## Decisions

1. **Four kinds: Note, Tip, Important, Warning.** Stored as `note`, `tip`, `important`, `warning`. A new block is a Note.
2. **The kind never depends on colour alone**: each has its own word and its own icon (`info`, `lightbulb`, `circle-alert`, `triangle-alert` from Lucide, 16px).
3. **The heading is the CMS's word unless the editor types a title.** The word is translated by the CMS into the visitor's language (`public.blocks.note.kinds.*` in `config/locales/public.en.yml`, English as the fallback, as the Code block's four words are). An editor's title replaces the word; the icon and the kind stay.
4. **The text is the block's ordinary rich text** (`body`): bold, italic, code, links, lists. Nothing is switched off in the editor for a note. A heading or an image inside a note is possible and is the editor's to avoid.
5. **An empty note draws nothing** on the site (no text in the visitor's language and none in the default one).
6. **It is an `aside` named by its heading**, never `role="alert"`: a note is part of the page, not an event. When an editor's title replaces the kind word, a visually hidden kind word stands before the title inside the heading ("Tip: Before you publish"), so a screen reader hears the kind, also in a list of headings; it is added only then, so "Tip" is never read twice (Claude Design D4c, 2026-10-15).
9. **The kinds' hues (Claude Design D4a, 2026-10-15):** Note is neutral (a 4% tint of the text colour with a `--th-line-strong` rule), Tip the ok green, Important the accent blue, Warning the warn amber. The danger red is kept for errors and destructive actions: a red Important read like an error next to Warning.
10. **On a strong band (D4b):** a note shares the band's ground, as the Code block does, but each kind keeps its colour on the left rule and the icon: the dark scheme's kind inks on a dark band, the light scheme's on a light band, each at 3:1 against the band; the body text is the band's text colour.
7. **The kind is chosen with a segmented control**, a new look for a `:select` field (`control: :segmented` in a type's schema), available to any type. It is a group of radio buttons underneath, so it works from the keyboard and without a script.
8. **A theme may restyle and replace the template**, through the contract: the component's line, sixteen tokens and the reference's section.

## The data

No column, no migration, no service (the recipe's step 0, `docs/reference/content-blocks-and-types.md`). The block is the first built the new way (block types spec, 2026-10-13): `bin/rails generate block_type note` writes its skeleton, and the type declares what it brings in its own definition. It has no capability (owner's answer 2 of that spec): the tile asks its `summary`.

```ruby
BlockTypes.register :note do |t|
  t.label "Note"
  t.field :kind, :select, options: Blocks::NoteComponent::KINDS, default: "note", control: :segmented
  t.field :title, :string, translated: true, max: 80
  t.uses :body
  t.component Blocks::NoteComponent
  t.theme_methods :block, :page, :kind, :heading, :titled?, :icon, :body
  t.tokens themed: %w[note tip important warning].flat_map { |k| %W[note-#{k}-ground note-#{k}-line note-#{k}-ink note-#{k}-border] }
  t.stylesheet "note.css"
  t.summary ->(block, locale:) { Note.summary(block, locale: locale) }
  t.sample settings: { "kind" => "tip" }, translations: { "en" => { title: "Before you publish", body: "…" }, "de" => { … }, "es" => { … } }, shows: [ "Before you publish", … ]
end
```

The contract's line and the sixteen tokens are also written into the ledger (`test/support/contract_ledger.rb`), the deliberate act a new promise to themes takes. `read_only_actions`: none (the segmented control is radios and writes through the form).

- `kind` is the same in every language and lives in `settings`. An unknown stored kind is drawn as a Note.
- `title` is the first translated schema field of a built-in type (`translated_settings`). The mechanism exists and no built-in type has used it, so this build proves it: the translation pair, the translation state ("missing" in a language only for the body, never for an empty title), the AI translation, the published copy and the audit snapshot each get a test with a translated title.

## The public side

- `Blocks::NoteComponent` with `initialize(block:, page:)`; its template is promised these names and no other: `block`, `page`, `kind`, `heading` (the editor's title, else the CMS's word), `titled?` (whether the heading is the editor's), `icon` (the kind's icon name), `body`.
- The icon is inline SVG written in the default template (four small paths), `aria-hidden`. A theme's template draws its own.
- `app/assets/tailwind/themes/default/note.css`, tokens only.
- **Tokens, four per kind, themed (light and dark):** `--th-note-{kind}-ground`, `--th-note-{kind}-line`, `--th-note-{kind}-ink`, `--th-note-{kind}-border`, for `note`, `tip`, `important`, `warning`. As a built-in type, their defaults are in `tokens.css`, and each is DEFINED from the theme's base tokens (`color-mix()` of `--th-accent`, `--th-ink`, `--th-surface` and a hue of the kind's), so a theme that re-colours its base re-colours the notes (owner's answer 1 of the block types spec). Body text stays `--th-ink`.
- **Contrast, computed in the tokens test for each kind, on the page and inside a tinted band, in both schemes:** the body text (`--th-ink`), the link colour (`--th-accent`) and the kind's ink each at 4.5:1 against the kind's ground. Inside a strong band: the kind's rule and icon at 3:1 against the band (decision 10).
- Inline code inside a note has the `--th-surface` ground with a 1px `--th-line` border, so it is told from the tint.

## CS Studio

- **The card:** the kind's four buttons, then "Title" (placeholder: the kind's word, which follows the kind; a help line says an empty title uses the word), then the text. The fields are the schema's, drawn by the card as every type's are.
- **The segmented control** is `Admin::Fields::SelectField` drawing radios when the field says `control: :segmented`: a new schema option (`OPTIONS`, refused on any type but `:select` and on a select with `blank:`), read-only on a translation tab as a select is.
- **The tile and the collapsed card** (the type's `summary`, as parts): the kind's icon at 12px in `text-meta`, then "Tip · first words of the text…", or the editor's title in place of the word.
- **The icon is a new part kind of a summary,** `[:icon, name]`, drawn by `TileSummaryComponent` as the 12px icon in `text-meta`, `aria-hidden`. `LOOKS` is a closed set today (`text`, `word`, `mono`, `hint`), so this is the one change to the tile's own code, and `:icon` takes only a name from a fixed list (the four kinds' icons), never markup.
- Strings are keys (`config/locales/admin/fields.en.yml`, `editor_screen.en.yml`).

## What this does not do

- No kind of the site's own, and no colour picker per note.
- No "collapsible" note.
- The documentation theme's own `--th-note-line` is not kept as an alias in the CMS: the theme changes its name in its own repository when it adopts the block.
- The Table block.

## Risks

- **Sixteen tokens are sixteen promises** to themes from the day they ship. Fewer would be three per kind (the border could be the line); the designer asked for four and this follows it.
- **The translated title** is the first use of a path no built-in type has walked.
- **Contrast on three grounds in two schemes** is 4 kinds x 3 pairs x 3 grounds x 2 = 72 computed pairs; a tint that passes on the page can fail inside a band.

## Testing

By the recipe ("Adding a block type", steps 0 to 11). The canary, the theme scaffold, the public smoke test, the editor card smoke test and the translation parity test build the Note from its `sample`, also inside a section's column; no hand-written row is added to them. What is this block's own: the declaration; `control: :segmented` (the option, its refusals, the markup, the keyboard); the component (each kind's word and icon, an editor's title, an unknown kind, an empty note, text that looks like markup); the public page at the top level and in a section's column, from the published copy; the canary; the 72 contrast pairs; the card, the tile, a translation tab with a title; the translated title through the translation state, the AI translation's field list, the copy and the audit snapshot; one browser file for the editor (choose a kind by keyboard, type, autosave, reload; a second person's read-only card) and one for the site in both schemes; a fixture theme that replaces the template from the reference alone.

## Documentation

In `contentspiel-docs`, after the block ships: `editors/pages/build-a-page-with-blocks.md` (the Note block), the integrators' theming pages (the tokens and the template), and the loader's switch (`bin/load` writes a real Note block; "To confirm" becomes a Warning with that title).

## As built

Built by `docs/superpowers/plans/2026-10-15-note-block.md` in ten tasks on the branch `note-block`; the reference is `docs/reference/content-blocks-and-types.md`, "The Note block", and `docs/reference/theming.md`, "The Note block". Where the code differs from this spec it is below, with what the departure costs if it is wrong.

**The plan's fourteen rulings**, one line each (the plan's "Plan rulings" holds them whole):

1. **`KINDS` and `ICONS` live on `BlockTypes::Note`, not on `Blocks::NoteComponent`** (the spec wrote `options: Blocks::NoteComponent::KINDS`): the tile's line and the icon need them and a model names a component only to register it. Cost if wrong: none for a site; a model referencing a component trips `dependency_direction_test`.
2. **`max:` on a `:string` was read by nothing**, so the schema now reports `:too_long` for it, in every language a translated string is stored in, with no `maxlength`. Cost if wrong: a German title of any length is saved, since the block validates the default language only.
3. **`help:` and `placeholder_from:` are two new schema options** with the `admin--ui--placeholder-from` script, because the card draws every field generically. Limit: only the block card hands a placeholder over, so a post type's field with `placeholder_from:` has the help line and no placeholder (a roadmap row). Cost if wrong: the title says "Note" while "Tip" is pressed.
4. **The sample's text is `body:` (Markdown), not a key of `translations`**; the spec's `translations: { "en" => { title:, body: } }` would be refused at registration.
5. **No block's text makes a page "missing"** (the spec said "missing in a language only for the body"): `Translations::Status.missing_count` counts the page's title and required translated schema fields, never a rich-text body; a Note's title and text are tracked for "outdated" and pinned by a test. Cost if wrong: none, it is what every block type does.
6. **The tile's line only**: a collapsed card of the page's own list shows its type's label for every type (a roadmap row from the Code block); the Note's line is on the tile.
7. **The kinds' hues are base tokens, as Claude Design's D4a names them** (Note neutral, Tip `--th-ok`, Important `--th-accent`, Warning `--th-warn`, none `--th-danger`), mixed with `color-mix(in srgb, …)` in forms the contrast test resolves. Lowest pair of the 72 is 4.88:1. Cost if wrong: a theme with unusual base colours has to re-declare the sixteen.
8. **On a strong band a note shares the band's ground and each kind keeps its colour** (`sections.css` re-values all sixteen). The dark-scheme inks themselves were not used: the strong band is a dark ground in both schemes since the contrast work, so Tip and Warning are their hue mixed 60% with the band's text, Important the band's accent, Note the band's dim and text; measured 6.64:1 or better. Cost if wrong: a theme that colours its strong band light gets light inks on it and answers for the sixteen itself.
9. **Note stands after Code in the picker** (the generator writes it above its marker; Task 4 moved it), so the picker reads Rich text, Image, Code, Note, Post list, Section.
10. **On a translation tab the segmented control is not drawn**: an untranslated field is listed read-only under "Shared fields" with its label; in a held form every radio is disabled.
11. **The four kind icons joined CS Studio's closed list** (`info`, `lightbulb`, `circle_alert`, `triangle_alert`; the partial's spelling of Lucide's `circle-alert`), while the public template keeps Lucide's own spelling.
12. **DEPARTURE from "CS Studio": the spec's `[:icon, name]` summary part was not built; a type's icon may follow its block** (`t.icon "info", for_block: ->(block) { … }`, `BlockTypeDefinition#icon_for`, `BlockIconComponent` with a block, redrawn by id after every save by `ContentBlocksController#block_icon_streams`). Reason: the contrast work draws one icon per type in the picker, on the card's head and on the tile, so a summary part would have drawn a second icon on the tile and none on the card. An outside type may not declare `for_block:` yet. Cost if wrong: a kind changed in another tab shows its new icon on this tab's card only after the live refresh (which replaces a clean card whole) or a reload; and a fourth declaration keyword is one more thing the generator's commented `t.icon` line does not mention.
13. **DEPARTURE from "The data" and "The public side": the theme contract's Note line has eight names, not seven.** `word` joins `block`, `page`, `kind`, `heading`, `titled?`, `icon`, `body`, because decision 6 asks the template to say the kind, hidden, before an editor's title and a template may call only the names its line promises. Cost if wrong: a template looks the key up itself and a locale key becomes a promise nobody tests; removing `word` later is a breaking change said in the release notes.
14. **The heading is an `h3`** (D4c asks for the kind in a heading list). Cost if wrong: a note at the very top of a page skips a level in the outline, a checker's warning and not an error; a theme's template chooses its own element.

**Two questions for the owner**, told in plain words on 2026-10-16 with the build's choice stated, and not objected to: the eight names with `word` (13), and `icon … for_block:` in place of the `[:icon, name]` part (12). They stand as built; either can be reversed before the release note goes out.

**Also built, not in the spec.** Each working folder has its own test database (`ContentSpiel::TestDatabase`, `lib/content_spiel/test_database.rb`; the first commit of the branch, and the second corrected a parallel worker's name to `<db>_N`), so two worktrees can run tests at once. The reading script for a placeholder, `placeholder_from_controller.js`, is the third script under `admin/ui` (Task 2). `test/support/contrast_measure.rb` learned `color-mix(in srgb, A N%, B)` so the sixteen tokens can be measured as they are written. A fourth fixture theme, `test/fixtures/themes/note`, is a Note template written from the reference alone.

**The files.** `app/models/block_types/note.rb`; `app/components/blocks/note_component.rb` and `.html.erb`; `app/assets/tailwind/themes/default/note.css`, `tokens.css` (sixteen tokens, light and dark), `sections.css` (the strong band's sixteen); `app/javascript/controllers/admin/ui/placeholder_from_controller.js`; `app/components/admin/fields/select_field.*`, `string_field.*`, `base.rb`; `app/components/admin/ui/field_component.*`; `app/components/admin/editor_screen/block_card_component.*`, `block_icon_component.rb`, `block_tile_component.rb`; `app/controllers/admin/content_blocks_controller.rb` (`block_icon_streams`); `app/models/content_model/definition.rb`, `field_set.rb`, `block_type_definition.rb`; `app/views/admin/shared/_icon.html.erb`; `config/initializers/types.rb`; `config/locales/public.en.yml` and `config/locales/admin/editor_screen.en.yml`; the ledger, `test/support/contrast_measure.rb`, `test/support/theme_test_helper.rb` and the fixture theme; the documents named above.

**Fixes Task 6 needed:** none; its tests passed against the code as built (it was interrupted once by the container engine hanging, and re-run).

**Left as known gaps** (`docs/roadmap.md`, "Known gaps", "Note block"): the four words are English until the public site is translated; a post type's field with `placeholder_from:` has no placeholder; an outside type's icon cannot follow its block; nothing checks that a theme's own template says the kind under an editor's title; the `h3` at the top of a page; the strong band's sixteen for a theme with a light band. Test-tidiness notes of the reviews (a shared `SEGMENT_CLASS`, the `help_id` built in two places, one rule for "a title that is only the kind's word" on the tile and the site, an independent literal in the colour-mix measure test, the hidden word measured by size only) stay in the branch's ledger and are not roadmap rows.

**For the documentation theme (work in `contentspiel-docs`):** its `--th-note-line` gives way to the contract's `--th-note-note-line` and the other fifteen names when it adopts the block; its `note_component` template calls only the eight names; the loader writes a real Note block where it wrote bold text in a paragraph.
