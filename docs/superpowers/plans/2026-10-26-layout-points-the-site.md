# Layout points, part 3: the site — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The default theme's captions read as text, a page's subpages list reads as navigation under "In this section", and a post's tags read as "Tagged rails, ruby".

**Architecture:** Values and class names in the default theme (`code.css`, `prose.css`, the Image block's and the post detail's templates, `pages/show.html.erb`), plus one new public-string helper, `site_string`, so a page template and a post component can say the site's own words in the visitor's language with English as the fallback. `site_string` is the one new name in `Theme::Contract` (Ruling 1).

**Tech Stack:** Rails 8.1 views and ViewComponent, Tailwind 4 (`tailwindcss-rails`) theme build, Minitest.

**Spec:** `docs/superpowers/specs/2026-10-23-layout-points-design.md`, section E, Decisions 16 and 17, Claude Design's answers O7 and O8, Rulings 8; the Testing bullet "Site". Parts 1 and 2 shipped (PRs #85, #91); this plan is part 3 of its "Size, and a suggested split".

## Global Constraints

- Captions (the Code block's, the Image block's, a rich-text figure's): `--th-font`, `--th-t-small` (13px), sentence case as typed (no `text-transform`, no tracking), in `--th-meta`.
- Mono stays for labels: dates, the language label of a code block, the "Tagged" label, the "In this section" label, the footer.
- Subpages: `nav.page-children` gets a mono label "In this section" above it; its links as the header's menu (`--th-dim`, ink on hover, no underline), one per line; hidden on a post's own page; nothing drawn (no label, no rule) without subpages.
- Tags: a mono "Tagged" label, then the tags in the small sans size, lower case as stored (no transform: as stored), joined by ", ", plain text, no links.
- No `--th-` token, template path or component method is added, renamed or removed (Decision 16). The one added contract name is the helper `site_string` (Ruling 1).
- Public strings live in `config/locales/public.en.yml` under `public.`; read in the visitor's language where `public.<locale>.yml` has the key, in English otherwise (no I18n fallbacks are configured; the test environment raises on a missing key).
- Every test command is prefixed `PGGSSENCMODE=disable`. Run `bin/rails tailwindcss:build && bin/rails theme_css:build` before integration and system tests; never build while tests run. One test process per worktree at a time. This worktree needs `bin/rails db:test:prepare` once.

## Rulings (made in this plan)

1. **One helper, `site_string(key)`, on the contract.** Decision 17 left it to the plan. A page template has no component to carry a `string` method, and a template calling Rails' `t` would show "Translation missing" in any language without a file. So `ThemeHelper#site_string` joins `Theme::Contract::HELPERS` and `COMPONENT_HELPERS` (the post detail's template needs it too) and the theming reference's Helpers table. It answers the keys under `public.site` and no other, exactly as `Blocks::CodeComponent#string` answers its four. It is the seam roadmap item 7 (translating the public site) moves the rest of the site's literals into. Cost if wrong: one name to take back with a release note.
2. **The language-or-English lookup is written once**, `PublicStrings.read(full_key)` in `app/values/public_strings.rb`, called by `site_string`, `Blocks::CodeComponent#string` and `Blocks::NoteComponent#word` (today two copies; this would be the third).
3. **The tags are one line of text**, the label then the names joined in the template, not a list: "joined by commas, plain text" is a sentence, and a `ul` read as "list, 2 items" says more than the design.
4. **The subpages nav is named by its label** (`aria-labelledby`), so a screen reader's landmarks list says "In this section" instead of a second unnamed "navigation".
5. **The caption utilities need a `text-small` size**: `--text-small: var(--th-t-small)` joins `theme.css`'s `@theme` (a Tailwind name, not a `--th-` token; Decision 16 holds).

## Review Focus

1. A visitor in a language with no `public.<locale>.yml` (German, Spanish): every new word is English, never "translation missing" — Task 1 and Task 3 tests.
2. A theme author who types `site_string(:in_this_sektion)`: in development and test it raises and names the keys; in production it is no word and one log line per key — Task 1 tests.
3. A post's own page under a listing page that has subpages: no subpages nav — Task 3 test.
4. A tag named `<b>Rails</b>` or `iOS`: drawn as typed and escaped, no upper-casing — Task 4 test.
5. A page whose subpages are all drafts or in the trash: no label and no rule — Task 3 test.

---

### Task 1: `PublicStrings` and the `site_string` helper

**Files:**
- Create: `app/values/public_strings.rb`, `test/values/public_strings_test.rb`
- Modify: `app/helpers/theme_helper.rb`, `app/components/application_component.rb`, `app/values/theme/contract.rb` (`HELPERS`, `COMPONENT_HELPERS`), `app/components/blocks/code_component.rb` (`string`), `app/components/blocks/note_component.rb` (`word`), `config/locales/public.en.yml`, `docs/reference/theming.md` (Helpers table)
- Test: `test/helpers/theme_helper_site_string_test.rb` (create), `test/values/theme/contract_test.rb` and `test/lib/theming_reference_test.rb` (run, not changed)

**Interfaces:**
- Produces: `PublicStrings.read(full_key) -> String` (the key in `I18n.locale` where it exists, else `:en`); `ThemeHelper::SITE_STRINGS = %i[in_this_section tagged]`; `ThemeHelper#site_string(key) -> String`, reachable from a component as `site_string` (delegated in `ApplicationComponent`); locale keys `public.site.in_this_section: "In this section"` and `public.site.tagged: "Tagged"`.

- [ ] **Step 1: Write the failing tests**

`test/values/public_strings_test.rb`:
- "a key the visitor's language has is read in it, and one it lacks is English": `I18n.backend.store_translations(:de, public: { site: { tagged: "Verschlagwortet" } })` (removed again in `teardown` by reloading I18n), then under `I18n.with_locale(:de)` `PublicStrings.read("public.site.tagged") == "Verschlagwortet"` and `PublicStrings.read("public.site.in_this_section") == "In this section"`.

`test/helpers/theme_helper_site_string_test.rb` (an `ActionView::TestCase` with `ThemeHelper`):
- "site_string answers the site's words in English": `site_string(:in_this_section) == "In this section"`, `site_string("tagged") == "Tagged"`.
- "a key that is not the site's raises where a theme is written, and names the keys": `assert_raises(ArgumentError) { site_string(:in_this_sektion) }`, message includes `:in_this_section` and `:tagged`.
- "in production an unknown key is no word and one log line": with `Rails.env` stubbed to production and a captured logger, two calls with `:nope` each return `""`, the log holds exactly one line naming `:nope`; no line holds a translation.

- [ ] **Step 2: Run them, expect failures**

Run: `PGGSSENCMODE=disable bin/rails test test/values/public_strings_test.rb test/helpers/theme_helper_site_string_test.rb`
Expected: NameError for `PublicStrings` and NoMethodError for `site_string`.

- [ ] **Step 3: Implement**

`PublicStrings.read` is the two-line lookup that `CodeComponent#string` and `NoteComponent#word` each write today; both call it afterwards. `site_string` refuses an unknown key as `CodeComponent#unknown_string` does (raise when `Rails.env.local?`, else warn once per key and return `""`), with a once-per-key memo of its own under a `Mutex` (the Code block's memo is that class's). Add the two keys under `public: site:` in `public.en.yml` with a comment saying they are the default templates' words (`pages/show`, `posts/detail_component`). Add `site_string` to `HELPERS`, to `COMPONENT_HELPERS` and to `ApplicationComponent`'s `delegate`. Add its row to the Helpers table in `docs/reference/theming.md`: `` `site_string(key)` | one of the site's own words (`public.site` in `config/locales/public.<locale>.yml`) in the language shown, English where that language has none ``.

- [ ] **Step 4: Run the new tests and the guards**

Run: `PGGSSENCMODE=disable bin/rails test test/values/public_strings_test.rb test/helpers/theme_helper_site_string_test.rb test/values/theme/contract_test.rb test/lib/theming_reference_test.rb test/components/blocks/code_component_test.rb test/components/blocks/note_component_test.rb`
Expected: all pass ("every listed helper is one a template can call" and "the helpers table names exactly the contract's helpers" included).

- [ ] **Step 5: Commit** — `feat: site_string, the site's own words in the visitor's language` (with the session's two attribution lines).

### Task 2: Captions are text

**Files:**
- Modify: `app/assets/tailwind/themes/default/code.css` (`.content-block--code figcaption`), `app/assets/tailwind/themes/default/prose.css` (`.cs-prose figcaption`), `app/assets/tailwind/themes/default/theme.css` (`@theme`: `--text-small`), `app/components/blocks/image_component.html.erb` (the `figcaption`'s classes)
- Test: `test/integration/design_tokens_test.rb`, `test/components/blocks/image_component_test.rb`

- [ ] **Step 1: Write the failing tests**

In `design_tokens_test.rb`, "a caption is text: the Code block's and a rich text's are the sans at the small size in the faint colour, as typed": for each of `code.css`' `.content-block--code figcaption` rule and `prose.css`' `.cs-prose figcaption` rule, the rule's body matches `font-family:\s*var\(--th-font\)`, `font-size:\s*var\(--th-t-small\)`, `color:\s*var\(--th-meta\)`, and does not match `text-transform`, `letter-spacing`, `--th-mono` or `--th-t-label`. And the theme build (`app/assets/builds/theme.css`) carries `.text-small` with `var(--th-t-small)`.

In `image_component_test.rb`, "the caption is the sans at the small size in the faint colour, as typed": a block with caption "A photo of Vienna" renders `figcaption.font-cs.text-small.text-meta` with that exact text, and the figcaption's classes include none of `font-cs-mono`, `uppercase`, `tracking-mono`, `text-label`.

- [ ] **Step 2: Run them, expect failures**

Run: `PGGSSENCMODE=disable bin/rails test test/integration/design_tokens_test.rb test/components/blocks/image_component_test.rb`
Expected: the new tests fail on the mono, uppercase rules.

- [ ] **Step 3: Implement** the values above; the Image caption's classes become `mt-2 font-cs text-small text-meta`; both stylesheets keep their `margin-top`.

- [ ] **Step 4: Build and run**

Run: `bin/rails tailwindcss:build && bin/rails theme_css:build && PGGSSENCMODE=disable bin/rails test test/integration/design_tokens_test.rb test/components/blocks/image_component_test.rb test/values/theme/scaffold_test.rb test/values/theme/contract_ledger_test.rb`
Expected: all pass (the scaffold and the ledger unchanged show no promise moved).

- [ ] **Step 5: Commit** — `style: captions in the default theme are text, not labels`.

### Task 3: The subpages list is navigation

**Files:**
- Modify: `app/views/pages/show.html.erb` (the `nav.page-children` part)
- Test: `test/integration/public_subpages_test.rb` (create; read `test/integration/public_drafts_test.rb` for how a site with published pages and a post detail URL is built)

**Interfaces:**
- Consumes: `site_string(:in_this_section)` (Task 1).

- [ ] **Step 1: Write the failing tests**

- "a page with published subpages names the list In this section, in mono, and its links are the menu's: dim, ink on hover, no underline, one per line": `nav.page-children[aria-labelledby]` whose id points at a `p.font-cs-mono` reading "In this section"; each `nav.page-children li a` has `text-dim` and `hover:text-ink` and no `underline`; one `li` per subpage, in tree order.
- "in a language without a public locale file the label is English, and with one it is that language's": the German address of the page shows "In this section"; with `public.site.in_this_section` stored for `:de` it shows the stored word.
- "a post's own page draws no subpages list, though its listing page has subpages": the post detail URL under that page has no `nav.page-children`; the listing page itself has one.
- "a page whose subpages are all drafts or in the trash draws no list, no label and no rule": no `nav.page-children`, no "In this section" in the body.

- [ ] **Step 2: Run, expect failures**

Run: `bin/rails tailwindcss:build && bin/rails theme_css:build && PGGSSENCMODE=disable bin/rails test test/integration/public_subpages_test.rb`
Expected: the label, link-class and post-page tests fail; the drafts test may already pass.

- [ ] **Step 3: Implement** in `pages/show.html.erb`: draw the nav only when `@post.nil?` and there are children; inside, first the label `p` (`font-cs-mono text-label uppercase tracking-mono text-meta`, an id such as `page-children-label`), then the `ul` with links `text-dim hover:text-ink`. Keep the top rule and spacing (`mt-12 border-t border-line pt-6`). Update the template's comment to say why a post page has none (O7).

- [ ] **Step 4: Run it and the public guards**

Run: `PGGSSENCMODE=disable bin/rails test test/integration/public_subpages_test.rb test/integration/trash_visibility_test.rb test/integration/public_canary_test.rb test/integration/theme_pages_test.rb test/values/theme/scaffold_test.rb test/lib/public_readers_test.rb`
Expected: all pass.

- [ ] **Step 5: Commit** — `feat: the subpages list is labelled "In this section" and set as navigation`.

### Task 4: Tags read as "Tagged rails, ruby"

**Files:**
- Modify: `app/components/posts/detail_component.html.erb`
- Test: `test/components/posts/detail_component_test.rb` (create if missing)

**Interfaces:**
- Consumes: `site_string(:tagged)` (Task 1, delegated in `ApplicationComponent`).

- [ ] **Step 1: Write the failing tests**

- "a post's tags are one line: a mono Tagged label, then the names as stored, joined by commas, in the small sans": tags `rails` and `iOS` → a `p.post-tags` whose text squishes to `Tagged rails, iOS` (the post's tag order), the label a `span.font-cs-mono` reading "Tagged", the names in a `span.font-cs.text-small.text-meta`; no `uppercase` anywhere in `p.post-tags`; no `ul`, no `a`.
- "a tag that looks like markup is text": a tag named `<b>x</b>` → no `b` element, the text present.
- "a post without tags draws nothing of them": no `p.post-tags`, no "Tagged".

- [ ] **Step 2: Run, expect failures**

Run: `PGGSSENCMODE=disable bin/rails test test/components/posts/detail_component_test.rb`

- [ ] **Step 3: Implement**: the `ul` becomes `<p class="post-tags mt-10">` holding the label span (`font-cs-mono text-label uppercase tracking-mono text-meta`), a space, and the names span (`font-cs text-small text-meta`) with `post.tags.map(&:name).join(", ")` (escaped by ERB).

- [ ] **Step 4: Run it and the theme guards**

Run: `bin/rails tailwindcss:build && bin/rails theme_css:build && PGGSSENCMODE=disable bin/rails test test/components/posts/detail_component_test.rb test/values/theme/contract_test.rb test/values/theme/scaffold_test.rb test/integration/public_canary_test.rb`
Expected: all pass ("a default component template calls no method of its component that its line does not name" included).

- [ ] **Step 5: Commit** — `style: a post's tags read as Tagged, then the names as typed`.

### Task 5: The rules, the references, the roadmap, the spec and the full check

**Files:**
- Modify: `CLAUDE.md`, `docs/reference/theming.md`, `docs/roadmap.md`, `docs/superpowers/specs/2026-10-23-layout-points-design.md`

- [ ] **Step 1: Documents**

- `CLAUDE.md`, the "New admin strings are keys" bullet: a public template's words are read through `site_string` (`public.site`), as `Blocks::CodeComponent#string` reads the Code block's four; both go through `PublicStrings.read`.
- `docs/reference/theming.md`: where the default theme's look is described, the captions (sans, small, as typed), the subpages list (label, menu links, none on a post page) and the tags line; add `site_string` to "What a template may ask" if that section lists signatures; a release-note line: "Added `site_string`; the default theme's captions, subpages list and tags changed by value and class only".
- `docs/roadmap.md`: in "Contrast and buttons, part 2" strike the site's three (captions, the subpages list, tags) and Notes for you's unread state (already wired, spec 11c) as shipped by "Layout points, part 3"; replace "the 'Related' heading; tags as links" with "related posts on the site (a spec of its own, O7); tags as links once tag pages exist"; add a "Shipped" row for part 3 pointing at the spec.
- The spec: `## As built (part 3, the site)` after part 2's, listing this plan's five rulings one line each.

- [ ] **Step 2: The full check**, each after the previous finished:

```bash
bin/rubocop
bin/brakeman
bin/rails zeitwerk:check
bin/rails tailwindcss:build && bin/rails theme_css:build
PGGSSENCMODE=disable bin/rails test
sysctl -n vm.loadavg
PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system
bin/theme-build-check
git status --short
```

Expected: clean, every test green, the browser suite in its usual ~10 minutes, `bin/theme-build-check` passes.

- [ ] **Step 3: Commit** — `docs: site_string, captions, subpages and tags in the references, the roadmap and the spec's as built (part 3)`.

- [ ] **Step 4: The pull request's text** (whoever opens the PR uses it)

```markdown
## Layout points, part 3 of 3: the site

Claude Design's review, part 2 (`docs/superpowers/specs/2026-10-23-layout-points-design.md`, section E), with Claude Design's answers O7 and O8.

- **Captions are text**: the Code block's, the Image block's and a rich-text figure's caption are the body font at 13px, as typed, in the faint colour, no longer small mono capitals.
- **A page's subpages are navigation**: under a mono "In this section", set as the header's menu (no underline), one per line; a post's own page no longer shows its listing page's subpages.
- **Tags** read "Tagged rails, ruby": the names as typed, plain text.
- **For themes**: one new helper, `site_string(key)`, the site's own words in the visitor's language with English as the fallback. The default theme's captions, subpages list and tags changed by value and class only; no token, template or component method changed.

## Documentation

Editors: `editors/getting-started/how-a-site-is-built.md` (the subpages list's label, and none on a post's page), `editors/posts/tags-related-posts-and-the-mind-graph.md` (how tags show on a post). Administrators: none. Integrators: `integrators/theming/the-theme-contract.md` (`site_string`; the default theme's captions, subpages list and tags).

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT
```
