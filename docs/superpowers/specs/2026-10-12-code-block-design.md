# The Code block

Date: 2026-10-12. Status: built (plan `docs/superpowers/plans/2026-10-12-code-block.md`); approved by the owner on 2026-10-12 ("Sounds everything good"). Built as its own pull request on top of theming and relies on the theming contract (`docs/superpowers/specs/2026-10-12-theming-design.md`). **The text below is the design as approved and is not rewritten: the last section, "As built", lists where the code left it, and the documents that describe the code are `docs/reference/content-blocks-and-types.md` ("The Code block") and `docs/reference/theming.md` ("The Code block").**

## Why

The documentation site is the first real integration, and a guide for integrators is half source code. Today code can be shown only as rich text's own code block: no language, no colours, no file name, nothing to copy. The branch `docs-theme-spike` drew a Code block that existed only when a theme folder was set, coloured by a highlighter that came with a development gem. That was evidence. This is the block as an ordinary block type of the CMS.

## What a person gets

- An editor adds a **Code** block to a page, pastes source, picks a language, and may give a file name and a caption.
- A visitor sees the code in a fixed-width face, coloured, with its file name and language above it and a Copy button. Without JavaScript the code is all there; only the button is missing.
- The code is the same in every language of the site. Only the caption is translated.
- A theme changes seven colours by seven tokens, or replaces the block's template.

## Decisions

Decided by the owner (roadmap, "The documentation site", "Decided since", 2026-10-11) and not reopened: plain-text source, a language, an optional file name, a copy button; the same code in every language, the caption translated; coloured on the server; seven syntax roles as theme tokens, light and dark; a block type of the CMS, not of a theme.

Decided here, each with what was rejected. The owner approved all nine on 2026-10-12; the three that were put to the owner as open questions (2, 5 and 8) are marked "confirmed", each as recommended. The smaller points the controller ruled on afterwards are under "Decided by the controller" below, and where one changes a sentence of this document the sentence has been changed.

1. **Rouge colours the code.** It is pure Ruby, has no dependency of its own, and is already in `Gemfile.lock` at 5.1.0 through Lookbook, so the bundle gains nothing; it gets its own line in the `Gemfile` because Lookbook is a development gem. Rejected: a hand-written highlighter. ERB, YAML, shell and Ruby are what the guide shows most, and each is wrong in corners (heredocs, `%w[]`, a `%>` inside a string) that a visitor reads as a mistake in the documentation. A wrong highlighter is worse than a dependency.
2. **A fixed list of 20 languages plus "Plain text"**, a constant of the CMS (confirmed 2026-10-12: the twenty as listed in §2). Rejected: all 234 of Rouge's lexers in a select (nobody finds YAML between Xojo and YANG), and a free-text language (a typo is silently plain).
3. **Source, language and file name are fields of the block's `settings`; the caption is the existing translated `caption` column.** No migration. Rejected: a `code` column on `content_blocks`, which is a column for one block type and a new entry in the published copy's lists for nothing the jsonb does not already do.
4. **A new schema field type, `:code`**, because a `:text` setting is stripped at both ends when stored and the first line of a sample would lose its indentation. Rejected: an option on `:text`, which every reader of a text field would then have to know.
5. **The Tab key leaves the field**, as in every textarea (confirmed 2026-10-12). Rejected: Tab inserts spaces, which traps a keyboard user unless they know an escape key, for the sake of code that is nearly always pasted.
6. **A limit of 20,000 characters, refused by the server and not cut by the browser.** A `maxlength` cuts a paste silently; a refused save says so and keeps the text.
7. **What is cached is the coloured tokens, not HTML**, so a theme's template is never inside the cache.
8. **On a strong section band the code is one colour** (confirmed 2026-10-12): not coloured by role. The band turns the page's colours round; a second set of seven values for it would be fourteen more to keep passing contrast.
9. **The Copy button is a Stimulus controller of the CMS**, `code-copy`. Rejected: leaving it to each theme (the spike's `docs--copy`), which makes every theme write the same twenty lines and get the announcement wrong.

Decided by the controller (2026-10-12, after the approval; not the owner's decisions):

- **The copy script's identifier is `code-copy`**, not `copy`: it names what it copies. The file is `app/javascript/controllers/code_copy_controller.js`, at the top level of `controllers/`, a public controller of the site like `theme` and `password_field`.
- **The four public strings live in a new `config/locales/public.en.yml`.** That file starts ahead of the roadmap's item on translating the public site (item 7 of "Next"), and the roadmap entry says so.
- **The block card's caption handling changes only for a type that uses an image**, as §3 proposes. The Image block's existing tests stay green, and one test pins that an Image block's card is unchanged.
- **The counter of the plain columns is reused for the code field only if it fits without a special case**; otherwise the field gets a small controller of its own in the editor's topic folder (`app/javascript/controllers/admin/editor/`). The plan decides by reading the script.
- **Language and file name are stacked above the code in the card**, each on its own line, in the order the type declares them. No special row.

## 1. The type and its storage

`BlockTypes::Code` (`app/models/block_types/code.rb`), registered in `config/initializers/types.rb` after `Image`, unconditionally:

```ruby
t.label "Code"
t.field :language, :select, options: CodeHighlight::LANGUAGES
t.field :filename, :string
t.field :code, :code, max: CodeHighlight::MAX_CHARACTERS
t.uses :caption
t.capability :code
t.component Blocks::CodeComponent
```

- **Nothing is required.** The picker makes an empty block first, as it does for an image; an empty Code block draws nothing on the public page.
- **`:code`** joins `ContentModel::Definition::SCALAR_TYPES`. `FieldSet#cast` for it: line endings become `\n`, leading and trailing lines that hold only whitespace are dropped, everything else is kept as typed (tabs and the first line's indentation included); only-whitespace is nil. `max:` counts characters and reports `:too_long`. It is never `translated:` (the definition refuses the pair), and `Admin::Ui::FieldComponent::TRANSLATABLE_TYPES` does not list it, so the code is never sent to an AI provider.
- **The field names are the spike's** (`language`, `filename`, `code`), which the documentation theme's template already reads.
- **The published copy** holds `settings` and `caption` already (`Publishing`'s column list, `Publishing::Changes::BLOCK_CONTENT`): a save on a live page sets `unpublished_changes_at` through the page's touch like every block write, the publish dialog counts the block as changed, and a visitor reads the copy. No column is added, so the "every column is in exactly one of the copy, the rows and never stored" test does not move.
- **Translation state.** The caption is the block's only translated field and is optional: a Code block never makes its page "missing" in a language, and a caption translated before the original's caption changed reads "outdated" like an image's. Changing the code changes no translation state.
- **Writes** are the existing `ContentBlocks::Save`, `Duplicate`, `Destroy` and `Reorder`: authorised, audited, under the page's row lock. No new service. The audit snapshot holds the settings, so the code is in it, as a rich-text body is.

## 2. Colouring

`CodeHighlight` (`app/values/code_highlight.rb`) is the one place that names Rouge.

- `LANGUAGES`: Rouge's tag to the label an editor reads. Shell, CSS, Dockerfile, ERB, Go, HTML, INI, JavaScript, JSON, Markdown, nginx, PHP, Python, Ruby, Rust, SQL, TOML, TypeScript, XML and YAML (Rouge has a lexer for each, checked against 5.1.0). Blank is "Plain text", the select's own blank option. The list only grows; a test holds that Rouge finds every tag.
- `lines(code, language)` answers one array per line of `[role, text]` pairs, the role nil for plain text. Rouge's token names are mapped to the seven roles by prefix, most specific first (the spike's table: `Comment.Preproc` is `embed`, so ERB's `<%=` and `%>` stand out; `Comment`, `Keyword`, `Literal.String`, numbers, symbols and constants as `constant`, `Name.Tag`, `Name.Attribute`). Everything else is plain.
- **No language, a stored tag that is not on the list, and a lexer that raises are all plain text, never an error.** The last is logged once with the block's id and no code. A save with an unlisted language is refused by the select's own validation, so the only way to an unlisted stored tag is a list that shrank.
- **Cache.** `Rails.cache.fetch([ "code", sha256 of the code, language, Rouge.version, CodeHighlight::REVISION ])`. It holds data, depends on no locale and no content version, and a changed role table bumps `REVISION`. The page's ETag needs nothing new: the code is content, and the theme's fingerprint is already a key.
- **Cost, measured on this machine:** 20,000 characters of Ruby in 4 ms, of ERB in 10 ms.

## 3. The editor card

The generic block card draws the type; it gains no branch for it.

- `Admin::Fields::CodeField` (`app/components/admin/fields/`) is a `<textarea>` in the monospace face with `wrap="off"`, `spellcheck="false"`, `autocapitalize="off"`, `autocomplete="off"`, 12 rows, scrolling both ways, `tab-size: 2`. No code editor library, no colours in the editor.
- Under it, a counter appears from 18,000 characters ("18,412 of 20,000"), drawn by the counter the plain columns already have (`counter:`), or by one small script of its own if that one cannot be shared: the plan reads it first. Over the limit the save is the form's ordinary 422: the message under the field, the text kept, nothing written.
- Language is the existing select field, File name the existing string field, in that order above the code; Caption is `Admin::Columns::PlainColumnComponent` below it. The card passes `override:` and the library placeholder to a caption only for a type that also uses `image`, since here there is no library text to override.
- On a translation tab the three settings are "Shared fields", read-only: the language's label, the file name, and the code in a scrolling `<pre>` of at most 12 lines (`SharedFieldsComponent.display` gains the `:code` case). Only the caption is edited there.
- Autosave, the base, the stale check, the claim and the hold are the card's own: one form, sent through `saving/queue.js`. Held by someone else, `HeldFields` already makes a textarea `readonly` and a select `disabled`; a counter's action only reads, and joins `ALLOWED_ACTIONS` if it is a new one.
- In a section, `TileSummaryComponent` asks `capability?(:code)` and shows the file name, else the language's label, else the first line of the code, else "No code yet".
- Strings (the counter, "No code yet", the shared-field labels) are keys in `config/locales/admin/editor_screen.en.yml` and `ui.en.yml`. The type's label is a literal in its definition, as every type's is today.

## 4. The public render

`Blocks::CodeComponent` (`app/components/blocks/`), built like `Blocks::ImageComponent`: `initialize(block:, page:)`, reading the block it is handed (a published view on the site, the rows in a preview). Its template:

```html
<figure class="content-block content-block--code" data-controller="code-copy">
  <div class="code-head">
    <span class="code-file" id="code-12-file">config/deploy.yml</span>
    <span class="code-language">YAML</span>
    <button type="button" hidden data-code-copy-target="button" data-action="code-copy#copy"
            aria-label="Copy code" aria-describedby="code-12-file">Copy</button>
    <span class="sr-only" role="status" data-code-copy-target="status"></span>
  </div>
  <pre tabindex="0" data-code-copy-target="source"><code>…<span class="syn-keyword">def</span>…</code></pre>
  <figcaption>…</figcaption>
</figure>
```

- The head is always drawn, since it holds the button; file name and language are each left out when blank, and `aria-describedby` with the file name. The caption is the translated one, with fallback, and left out when blank.
- **Escaping.** The template prints each token's text through ERB's own escaping and wraps it with `tag.span`; nothing in the component or in `CodeHighlight` calls `html_safe` or `raw`, and Rouge's HTML formatters are not used. The code can therefore add no element and no attribute. The file name and caption are escaped text too.
- **Long lines scroll** inside the `<pre>` (`overflow-x: auto`, `white-space: pre`), which is focusable so a keyboard can scroll it. The page never scrolls sideways, in a column of a section as at full width: the figure has `min-width: 0`.
- **Copy** (`app/javascript/controllers/code_copy_controller.js`, identifier `code-copy`, registered with the public site's controllers). The button is `hidden` in the markup and shown on `connect` when `navigator.clipboard` exists, so nobody sees a button that does nothing. A press writes the `source` target's `textContent` (the code exactly as stored, no markup), sets the button's text and the status region to "Copied" for two seconds, or to "Not copied" when the browser refuses. Its words come from the server as values (`data-code-copy-copied-value`, `data-code-copy-failed-value`).
- **Public strings** ("Copy", "Copy code", "Copied", "Not copied") are keys under `public.blocks.code` in a new `config/locales/public.en.yml`, read in the visitor's language with English as the fallback. The public site's other strings are still literals; these four start the file ahead of roadmap item 7, which will fill it, and the roadmap entry says so.
- **Styles** are `app/assets/tailwind/themes/default/code.css`, imported by `theme.css`: plain rules on tokens, because the span classes are built from role names and no utility scan would find them. Background `--th-sunken`, text `--th-ink`, border `--th-line`, face `--th-mono`.

## 5. The seven roles and their tokens

| Role | What it colours | Token | Light | Dark |
|---|---|---|---|---|
| comment | comments | `--th-syn-comment` | `oklch(0.47 0.01 270)` | `oklch(0.68 0.01 270)` |
| keyword | keywords | `--th-syn-keyword` | `oklch(0.45 0.12 250)` | `oklch(0.76 0.10 250)` |
| string | string literals | `--th-syn-string` | `oklch(0.43 0.10 150)` | `oklch(0.78 0.11 150)` |
| constant | numbers, symbols, constants | `--th-syn-constant` | `oklch(0.46 0.10 65)` | `oklch(0.80 0.10 75)` |
| tag | markup tags | `--th-syn-tag` | `oklch(0.42 0.07 200)` | `oklch(0.78 0.07 200)` |
| attribute | markup attributes, keys | `--th-syn-attribute` | `oklch(0.44 0.10 300)` | `oklch(0.76 0.09 300)` |
| embed | template delimiters (`<%`, `%>`) | `--th-syn-embed` | `oklch(0.46 0.15 25)` | `oklch(0.76 0.11 25)` |

The values are the documentation design's, with the chroma of two light ones lowered into sRGB. Computed against `--th-sunken` (and `--th-surface`, which a tinted band puts behind the code) the lowest is the comment: 5.7 to 1 light, 5.5 to 1 dark; a test computes all 28 pairs and fails under 4.5. On a strong band `sections.css` sets the seven to `--th-on-band-strong`, the comment to its dim (decision 8).

**The contract's two entries.** Among the replaceable components: `Blocks::CodeComponent`, template `components/blocks/code_component.html.erb`, receiving `block`, `page`, `lines`, `code`, `language` (the tag), `language_label`, `filename`, `caption`, each safe for an empty block. Among the tokens: the seven names above. With the component's entry the reference describes the `code-copy` controller's markup (the identifier, the targets `button`, `source` and `status`, the action, the two values), since a replaced template has to write it.

**The documentation theme** keeps its values and its classes. `--th-syn-attr` becomes `--th-syn-attribute`; the other six names are the same and stop being the theme's own invention. Its template reads `lines` instead of `helpers.highlighted_lines`, its `docs--copy` controller is deleted for the CMS's `code-copy`, and `--th-note-line` stays the theme's until a Note block exists.

## 6. MCP and Markdown

The MCP server has six tools, for posts and the media library. A post has a body and no blocks, so no tool reads or writes a Code block today and none changes. When page and block tools are built (roadmap item 8) the block's settings travel as the plain strings they are. Rich text is untouched: inline code and rich text's own code block keep their node, their Markdown form (a fence) and their uncoloured render. A fence in a post's Markdown stays rich text; it does not become a Code block.

## What this does not do

A Note block. A Table block. A language on code blocks inside rich text. Line numbers, highlighted lines, diffs as a display mode, a "run" button. Colours in the editor's field. Wrapping long lines as an option. The block reference generated from declarations. Loading the guide's Markdown fences as Code blocks (the documentation's own loading work). The German and Spanish of the four public strings.

## Risks

- **A dependency on the public path.** Rouge was a development gem; now a visitor's request runs it. It is confined to `CodeHighlight`, any failure is plain text, and the cache keys on its version.
- **A slow lexer.** Rouge's lexers are regular expressions; a crafted input could backtrack. The cap bounds it, an editor is the only author, and the result is cached, so a slow one is paid once per change. If one is found, `Regexp.timeout` around the lex with the plain fallback is the fix.
- **Two ways to show code.** Rich text's code block stays and is not coloured. The guide says which is for what: a line or two inside a text, or a sample with a name and colours.
- **The token names are a promise** once in the contract. `attribute` is spelled out to match its role and class; the theme renames one.
- **The settings hold up to 20,000 characters**, and so does each audit snapshot and each published copy of the page. A rich-text body already does.

## Testing

Built and tested the way the Image and Rich text blocks are.

- `CodeHighlight`: every listed tag has a lexer; the role table on one sample per language family (Ruby, ERB, HTML, YAML, shell); no language, an unknown one and a raising lexer are plain; line splitting, an empty last line, tabs kept.
- `ContentModel::FieldSet`: `:code` keeps indentation, normalises line endings, drops blank outer lines, refuses 20,001 characters, refuses `translated: true`.
- `test/components/blocks/code_component_test.rb`: the markup above; nothing drawn for an empty block; a head without file name or language; a source of `</code><script>` and `<%= %>` is text in the output and the document holds one `pre`; the caption in the visitor's language with fallback. A Lookbook preview beside the other blocks'.
- Card and fields (`test/components/admin/`): the textarea's attributes, the shared fields on a translation tab, the caption without the override, the tile's summary; `held_fields_test.rb` gains the code field.
- Integration (`test/integration/blocks_test.rb`, `public_blocks_test.rb`): add, save, refuse over the limit with nothing written, duplicate, delete; in a column of a section; the stale 409 and the claim as for any block. `public_canary_test.rb` gains a Code block: code overwritten on the rows reaches no visitor until published. `public_javascript_test.rb`: the `code-copy` controller is on a public page and no admin script is.
- System: type into the card, autosave, reload, the indentation is there; a second session sees it read-only. Public: the button is hidden without a clipboard and shown with one, a press puts the stored code on the clipboard and the status says "Copied"; a 300-character line scrolls in the block and the page has no horizontal scroll.
- Contract: the seven tokens are in `tokens.css` for light and dark and in `Theme::Contract`; the contrast test; the fixture theme `plain` replaces the Code template in one test and leaves it in the others.

## Documentation

Guide, in `contentspiel-docs` (no guide text here). **New, integrators: "How to add a block type"** (the owner, 2026-10-12: "a great topic to document"): a walk-through that follows this block as it was really built, step by step (the declaration, its fields and where they are stored, the component and its template, the editor card, what is translated, the published copy, the tokens, the tests), written from the finished pull request so it cannot describe steps nobody took. Editors: `pages/build-a-page-with-blocks` (a fifth block type, its fields, the limit, what is translated), `pages/arrange-blocks-in-sections` (one sentence: it works in a column), `pages/the-rich-text-editor` (when to use which code), `translating` (the code is shared, the caption is not). Integrators: `theming/the-token-contract` (seven tokens), `theming/rendering-blocks-and-pages` and the block and template reference (the component's entry, the `code-copy` markup). In this repository: `docs/reference/content-blocks-and-types.md` (the type, the `:code` field), `docs/reference/theming.md` (the two entries), `docs/reference/i18n.md` (the public file), `CLAUDE.md` (the block-type list in "What This Repo Is" stays general; nothing to add unless a rule appears while building).

## As built

Where the code left the text above, and which document now describes it. "The reference" is `docs/reference/content-blocks-and-types.md`, "The Code block"; "theming's reference" is `docs/reference/theming.md`, "The Code block". The designer's answers (C1 to C8, 2026-10-12, asked in the design system's project while the block was being built) arrived after Tasks 2 to 5 and were built as one extra task.

**The order of the build.** The type, the field, the public render, the Copy button and the editor were built on `main` before theming was merged, as the plan allowed; the branch was then rebased onto theming and the contract's entries were added last. Nothing of the design depended on the order.

**§1, the type and its fields.**

- **Two new field options, where the spec has none.** `blank:` names a select's empty choice ("Plain text": the select's own blank option had no words). `label:` names a field where its name humanised reads wrong: the type says `label: "File name"` (design answer C5; the plan had built "Filename" and left it as a wording question). Everything that names a field to a person asks `ContentModel::Definition::Field#label`, the public page's group rows and the validation messages included. The reference, "Three things the schema learned for it".
- **The limit's message is a key of its own**, `errors.messages.code_too_long` in `config/locales/en.yml` (the limit grouped, "20,000"); the error is still `:too_long`.
- Unchanged: no migration, no column, no service; the published copy's column test did not move, and a test reads the code from the copy.

**§2, colouring.**

- **`CodeHighlight.lines(code, language, block_id: nil)`**: a third, optional argument, because the log line of a lexer that raised names the block and the id has to come from the caller. Roles are Strings, not Symbols, so the cached value is the same whatever the cache store's serializer does.
- **A failure is cached for five minutes under a key of its own** (`failure_key`, `FAILURE_TTL`), never under the code's key: the spec's `Rails.cache.fetch` cached whatever the block answered, so one failed lex was plain text until the code changed; caching no failure at all, the second version, made a block that always fails cost every request its timeout (final review I1). The failure is logged once per entry.
- **One whole lex has a deadline** (`LEX_SECONDS`, half a second, checked inside Rouge's regex lexers at every step), which the spec left for "the day a slow input is found": `Regexp.timeout`, which Rails already sets to one second, bounds one match only. Lexers that Rouge's listed lexers hand text to (a Markdown fence names any of Rouge's) run under the same deadline.
- **Two more inputs are plain text**: bytes that are not text are scrubbed to U+FFFD before anything else, and code over `MAX_CHARACTERS` is neither lexed nor cached. Neither is reachable through the services.
- Rouge's tag for a Dockerfile is `docker`; the label is "Dockerfile".

**§3, the editor.**

- **The counter is a controller of its own**, `admin--editor--code-limit` (the controller's ruling: reuse only without a special case; `admin--ui--char-count` is always shown and is a hint about a soft length). Its words carry the unit and, over the limit and in the danger ink, by how much: "18,412 of 20,000 characters", "20,412 of 20,000 characters · 412 over". It is announced twice at most and is the field's description only while it shows (C4).
- **The field grows with the code**, six to twenty-four lines by `field-sizing: content`, and does not wrap (`white-space: pre`); the spec's twelve rows are the fallback of a browser without `field-sizing` (C3).
- **A translation tab** keeps the code's frame and puts one line above it, "Code isn't translated. Edit it on the English tab.", the language's name a link to the default tab (C6).
- **The tile's line** is the file name; else the language's label, " · " and the first line of code in the monospace face; and "Empty" for a block with neither (C7). The spec had "the file name, else the language's label, else the first line, else 'No code yet'". **The collapsed card's line of C7 is not built**: a collapsed card shows its type's label and no content, for every type (roadmap).
- **The strings are in three files**, not in `editor_screen.en.yml` and `ui.en.yml` alone: the counter's in `config/locales/admin/fields.en.yml` (one locale file per component folder), the tile's "Empty" and the translation tab's line in `editor_screen.en.yml`.
- The integration tests are in `test/integration/admin/content_blocks_test.rb` (`test/integration/blocks_test.rb` does not exist).

**§4, the public render.**

- **The head strip is conditional** (C1), where the spec draws it always: with no file name and no language it is `hidden` in the markup and the copy script's `strip` target, shown with the button where there is a clipboard, so a page without the script shows no empty box.
- **The markup has three values and four targets**: `data-code-copy-label-value` (the button's word at rest, which the script writes back and never reads from the page) beside `copied` and `failed`, and the `strip` target beside `button`, `source` and `status`. The status line's class is `code-status`, hidden by the block's own stylesheet, not Tailwind's `sr-only`, which would depend on a theme's scan.
- **The copy script** keeps the elements it needs as fields and takes its words back at `turbo:before-cache` as well as at `disconnect`, leaving `hidden` to `connect` and `disconnect`; the status line is emptied when the word goes back, and "Not copied" is in the same colour as "Copy" (C2). **The plan's Task 4, Step 3 holds a controller that is superseded**: its `disconnect` read a target, which Stimulus no longer finds once the controller is taken off its element. The file is `app/javascript/controllers/code_copy_controller.js`, and its comment and the reference ("The copy script") say why.
- **The figure has no `min-width: 0`**: it is never a flex or grid item in the default theme, and what keeps a block in a column narrow is `sections.css`.
- **`string` answers the four keys only**: any other raises where a theme is written and is an empty string elsewhere.
- Added from C8: a 1px rule under the strip, the selection as the accent pair, and in a strong band `--th-on-accent` re-valued and the block told the opposite `color-scheme`.

**§5, the contract.**

- **The component's line is nine names**, the spec's eight and `string`, which the default template calls for its words. For one review the line also held `head_attributes` and `file_id`; both came off the contract and out of the component, because they were the default template's layout and a theme whose bar also holds the caption would have hidden the caption with them. The default template writes both out itself. `string` is a generic name to have promised to themes: the owner's call, listed in the pull request.
- **Contrast is held for 42 pairs on three grounds**, not 28 on two: the strong band's ground is computed too, and each token is measured as the band values it. The lowest is the comment on the dark sunken ground, 5.5 to 1.
- **The fixture is a third theme, `test/fixtures/themes/code`**, written from theming's reference alone; `plain` does not replace the Code template, so every test of it is also a test of the default block.
- **A theme's `--th-syn-*` do not reach code in a strong band**, since the band's declaration is nearer the code; theming's reference says how a theme sets them there.
- The copy script's markup in theming's reference names three values, not two, and the optional `strip` and `restore`.

**Not this repository, unchanged:** the documentation theme's three changes (`--th-syn-attr` to `--th-syn-attribute`, `lines` in place of its helper, `code-copy` in place of `docs--copy`) and the guide's pages.
