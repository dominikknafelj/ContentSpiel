# The Note block

Status: for the owner's review (2026-10-13). The design is Claude Design's, 2026-10-13 (B1 to B3). The owner agreed to the block and to the order "Note, then Table" the same day. The Table block is a spec of its own.

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
6. **It is an `aside` named by its heading**, never `role="alert"`: a note is part of the page, not an event.
7. **The kind is chosen with a segmented control**, a new look for a `:select` field (`control: :segmented` in a type's schema), available to any type. It is a group of radio buttons underneath, so it works from the keyboard and without a script.
8. **A theme may restyle and replace the template**, through the contract: the component's line, sixteen tokens and the reference's section.

## The data

No column, no migration, no service (the recipe's step 0, `docs/reference/content-blocks-and-types.md`).

```ruby
BlockTypes.register :note do |t|
  t.label "Note"
  t.field :kind, :select, options: Blocks::NoteComponent::KINDS, default: "note", control: :segmented
  t.field :title, :string, translated: true, max: 80
  t.uses :body
  t.capability :note
  t.component Blocks::NoteComponent
end
```

- `kind` is the same in every language and lives in `settings`. An unknown stored kind is drawn as a Note.
- `title` is the first translated schema field of a built-in type (`translated_settings`). The mechanism exists and no built-in type has used it, so this build proves it: the translation pair, the translation state ("missing" in a language only for the body, never for an empty title), the AI translation, the published copy and the audit snapshot each get a test with a translated title.
- `:note` is the capability the tile asks.

## The public side

- `Blocks::NoteComponent` with `initialize(block:, page:)`; its template is promised these names and no other: `block`, `page`, `kind`, `heading` (the editor's title, else the CMS's word), `titled?` (whether the heading is the editor's), `icon` (the kind's icon name), `body`.
- The icon is inline SVG written in the default template (four small paths), `aria-hidden`. A theme's template draws its own.
- `app/assets/tailwind/themes/default/note.css`, tokens only.
- **Tokens, four per kind, themed (light and dark):** `--th-note-{kind}-ground`, `--th-note-{kind}-line`, `--th-note-{kind}-ink`, `--th-note-{kind}-border`, for `note`, `tip`, `important`, `warning`. Body text stays `--th-fg`.
- **Contrast, computed in the tokens test for each kind, on the page and inside a tinted and a strong band, in both schemes:** the body text, the link colour and the kind's ink each at 4.5:1 against the kind's ground.
- Inline code inside a note has the `--th-surface` ground with a 1px `--th-line` border, so it is told from the tint.

## CS Studio

- **The card:** the kind's four buttons, then "Title" (placeholder: the kind's word, which follows the kind; a help line says an empty title uses the word), then the text. The fields are the schema's, drawn by the card as every type's are.
- **The segmented control** is `Admin::Fields::SelectField` drawing radios when the field says `control: :segmented`: a new schema option (`OPTIONS`, refused on any type but `:select` and on a select with `blank:`), read-only on a translation tab as a select is.
- **The tile and the collapsed card:** the kind's icon at 12px in `text-meta`, then "Tip · first words of the text…", or the editor's title in place of the word.
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

By the recipe's steps 1 to 10, with what is this block's own: the declaration; `control: :segmented` (the option, its refusals, the markup, the keyboard); the component (each kind's word and icon, an editor's title, an unknown kind, an empty note, text that looks like markup); the public page at the top level and in a section's column, from the published copy; the canary; the 72 contrast pairs; the card, the tile, a translation tab with a title; the translated title through the translation state, the AI translation's field list, the copy and the audit snapshot; one browser file for the editor (choose a kind by keyboard, type, autosave, reload; a second person's read-only card) and one for the site in both schemes; a fixture theme that replaces the template from the reference alone.

## Documentation

In `contentspiel-docs`, after the block ships: `editors/pages/build-a-page-with-blocks.md` (the Note block), the integrators' theming pages (the tokens and the template), and the loader's switch (`bin/load` writes a real Note block; "To confirm" becomes a Warning with that title).
