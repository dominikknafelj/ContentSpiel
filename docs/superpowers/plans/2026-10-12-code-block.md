# The Code block — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An editor adds a Code block to a page (source, a language, an optional file name, a translated caption); a visitor reads it coloured on the server, with its file name and language above it and a Copy button; a theme re-colours it by seven tokens or replaces its template.

**Architecture:** A fifth built-in block type, built the way Image and Rich text are: `BlockTypes::Code` declares three settings and uses the existing `caption` column, so there is no migration and the published copy, the audit log and the save services take it as they take any block. One new schema field type, `:code`, keeps source as typed. `CodeHighlight` (`app/values/`) is the one place that names Rouge: it cuts source into lines of `[role, text]` pairs, caches that data and answers plain text for anything it cannot colour. `Blocks::CodeComponent` prints the pairs through ERB's own escaping; the copy button is a public Stimulus controller, `code-copy`. The editor's card is the generic block card with a new field component, `Admin::Fields::CodeField`.

**Tech Stack:** Rails 8.1, Rouge 5.1 (pure Ruby, already in `Gemfile.lock`), ViewComponent 4.15, Stimulus via importmap, Tailwind 4 with plain CSS for the block, Minitest + fixtures, Capybara on Cuprite.

**Spec:** `docs/superpowers/specs/2026-10-12-code-block-design.md` (approved 2026-10-12; read all of it, the "Decided by the controller" list included).

## Global Constraints

- Read `CLAUDE.md` first; its rules bind. Read `docs/reference/content-blocks-and-types.md` before Tasks 2, 3 and 5, `docs/reference/publishing.md` and `docs/reference/translations.md` before Task 3, `docs/reference/live-editing.md` ("A form someone else holds") and `docs/reference/i18n.md` before Tasks 2 and 5, `docs/reference/design-system.md` before Tasks 2, 3 and 5.
- **This plan was checked against `main` at `c7af9aa7`. Tasks 1 to 5 are buildable on `main` as it is there, with the default theme alone. Task 6 assumes theming is merged** and says so at its top. The block is built after theming is merged, so read this before Task 3: theming's contract test holds that every component a type registry hands out is in `Theme::Contract::COMPONENTS`. If theming is on your base, that ONE test is red from the commit of Task 3 (which registers `Blocks::CodeComponent`) until Task 6 (which adds the line). That is expected and is the only failure allowed in between; do not add anything to `Theme::Contract` or to `tokens.css` before Task 6. If theming renamed something a task names (the public stylesheet `theme-default` becomes `theme`; the public layout's body becomes `layouts/public/_frame`), nothing here depends on it: no step names the built stylesheet or the layout.
- Every test command is prefixed `PGGSSENCMODE=disable`. One file, a system test included, is `bin/rails test <path>` (never `bin/rails test:system <path>`). A browser test needs `bin/rails tailwindcss:build` first. The whole browser suite is `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test:system`, after `sysctl -n vm.loadavg` says the machine is quiet. Never two test runners at once on this machine (worktrees share the test databases).
- No fixed sleeps in a system test: wait with `assert_writes_settled`, `await_js`, `await_frames`, `await_admin_controllers`, `await_notes_live` or a Capybara matcher. A system test fails on any JavaScript error.
- **The source is text, everywhere.** Nothing in `Blocks::CodeComponent`, its template or `CodeHighlight` calls `html_safe`, `raw` or `safe_join`, and Rouge's formatters are not used. A class name on a span comes from `CodeHighlight::ROLES`, never from the stored language or from Rouge's token name.
- **`CodeHighlight` is the only file that names Rouge** (`Rouge::` appears nowhere else in `app/`), and it never raises for input: no language, a stored language that is not on the list, and a lexer that raises are all plain text.
- The limit is 20,000 characters (`CodeHighlight::MAX_CHARACTERS`), refused by the server with the form's ordinary 422. No `maxlength` on the field.
- Names: the public copy controller is `code-copy` (`app/javascript/controllers/code_copy_controller.js`); the editor's counter is `admin--editor--code-limit` (`app/javascript/controllers/admin/editor/code_limit_controller.js`). Never define `Admin::CodeHighlight` (`test/lib/admin_namespace_shadow_test.rb` refuses it once `app/values/code_highlight.rb` exists); inside `module Admin` write `::CodeHighlight`.
- New CS Studio strings are locale keys. The code field's are in a new `config/locales/admin/fields.en.yml` (it holds exactly `en.admin.components.fields`); the tile's is in `editor_screen.en.yml`. The four public strings are in a new `config/locales/public.en.yml`. A block type's label and a select's choices are literals in the type's definition, as every type's are today.
- No inline handlers, no colour literals in CS Studio sources or in the default theme's stylesheets, no `mx-auto`.
- **A design question is not the implementer's to decide.** Tasks 2, 3, 4 and 5 draw something a person sees. Where a step gives values the spec does not state (a spacing, an alignment, a word), build them as written and report them, with a screenshot in light and dark, to the controller, who puts them to the design system's owner. Where a question comes up that this plan does not answer, stop and report it the same way. Do not choose.
- The pull request names, under "Documentation", the guide pages Task 7 lists.
- Commits: conventional subject, ending with the two attribution lines the controller gives in the dispatch.
- Scratch files only in a directory made with `mktemp -d` and deleted by name.

### Where the plan departs from the spec's wording, and why

Each was checked against the code; none changes what the owner approved.

1. **The file name's label reads "Filename".** A schema field's label is its name humanised (`Admin::Ui::FieldComponent#label_text`), the field is named `filename` (the spec fixes the name), and the schema has no label option. The spec's prose says "File name". Built as "Filename"; reported to the controller as a wording question for the design system's owner (a `label:` option on a schema field would be its fix, and is not built here).
2. **"Plain text" needs one new field option.** The select field's empty choice has an empty label today. `blank:` joins `ContentModel::Definition::OPTIONS` (the label of a select's empty choice), and the type says `blank: "Plain text"`.
3. **The code field's strings are in `config/locales/admin/fields.en.yml`,** not in `editor_screen.en.yml` or `ui.en.yml` as §3 says: `test/lib/source_layout_test.rb` holds one locale file per component folder, and the field's component is in `app/components/admin/fields/`.
4. **The existing counter is not reused** (the controller's ruling: reuse only without a special case). `admin--ui--char-count` is always visible, says "42 / 60 · long", announces "the recommended length" in English literals and is a hint about a soft length. This one is hidden below 18,000, says "18,412 of 20,000" and marks a hard limit. So: a small controller of its own, `admin--editor--code-limit`.
5. **`CodeHighlight.lines(code, language, block_id: nil)`** has a third, optional argument: the spec wants a raising lexer logged with the block's id, and the id has to come from the caller. Roles are Strings (`"keyword"`), not Symbols, so the cached value is the same whatever the cache store's serializer does.
6. **The integration tests are in `test/integration/admin/content_blocks_test.rb`.** The spec names `test/integration/blocks_test.rb`, which does not exist.
7. **Rouge's tag for a Dockerfile is `docker`.** The label an editor reads is "Dockerfile".
8. **The published copy's column test does not move** ("every column of content_blocks is in exactly one of the copy, the rows and never stored"): no column is added. Task 3 runs it and adds a test that the code is read from the copy.

## Review Focus

1. **A paste over the limit.** 20,001 characters must be refused with the message under the field, the text still in the field, nothing written, and the counter saying so; a paste with Windows line endings must not be counted twice (Task 2: `"more characters than max is too long, counted after line endings are one character, and the text is still in the object"`; Task 5: `"a Code block over the limit is refused with the message in its slot, nothing is written, and the answer does not touch the field"`, `"from 18,000 characters the field counts; over 20,000 the save is refused, the text stays and nothing is stored"`).
2. **Source that looks like markup.** `</pre><script>`, an ERB tag, `&`, a file name or a caption with tags in it, and a stored language that is not on the list (a list that shrank, a row written around the services) must each be text and never an element, an attribute or a class (Task 3: `"source, file name and caption that look like markup are text: one pre, no script, no element the template did not write"`, `"a stored language that is not on the list is plain text and names no language"`, `"nothing in the component, its template or the highlighter marks a string as safe"`).
3. **A lexer that fails.** A lexer that raises must cost the visitor nothing: the code is drawn plain, and the log line names the block and holds no code (Task 1: `"a lexer that raises is plain text, and the log names the block and holds no code"`; Task 3: `"a lexer that raises still draws the code"`).
4. **White space is the content.** The first line's indentation, tabs, inner blank lines and a line ending the browser sent as CRLF must come back as typed after a save, a reload, a held (read-only) render and a copy (Task 2: `"the first line's indentation, tabs and inner blank lines are kept as typed"`, `"Admin::Fields::CodeField, rewritten: the code is read-only with its indentation and its counter's action is the one left"`; Task 4: `"the button is shown where there is a clipboard; a press copies the code exactly as stored and says Copied"`; Task 5: `"a Code block added from the picker is typed into, saved by itself, and keeps its indentation after a reload; Tab leaves the field"`).
5. **A browser with no clipboard, or one that refuses.** Nobody sees a button that does nothing, a refusal is said, and what the script wrote into the page is taken back when it disconnects (Turbo's snapshot keeps it otherwise) (Task 4: `"without a clipboard the button stays hidden, and a browser that refuses is told Not copied"`, and the last lines of the test above it).
6. **A long line in a narrow place.** A 300-character line in a column of a section must scroll inside the block; the page must not scroll sideways (Task 4: `"a long line scrolls inside the block and the page never scrolls sideways, at full width and in a column"`).
7. **A visitor in a language the four public strings are not written in.** German and Spanish have no `public.*.yml` yet: the strings must be English, not a raise and not "translation missing" (Task 3: `"the caption is the visitor's language with fallback, and the four public strings fall back to English"`).

## File map

| File | Responsibility |
|---|---|
| `Gemfile`, `Gemfile.lock` | Rouge as an application dependency |
| `app/values/code_highlight.rb` (new) | The languages, the limit, the seven roles, `lines`, the cache; the one file that names Rouge |
| `app/models/content_model/definition.rb`, `field_set.rb` | The `:code` field type (kept as typed, `max:` in characters, never translated); `blank:` for a select |
| `app/components/admin/fields/code_field.rb`, `.html.erb` (new), `select_field.*` | The code textarea and its counter; a select's named empty choice |
| `app/javascript/controllers/admin/editor/code_limit_controller.js` (new) | The counter |
| `config/locales/admin/fields.en.yml` (new) | The counter's words |
| `app/components/admin/editor_screen/shared_fields_component.*`, `held_fields.rb` | A translation tab's read-only code and language label; the counter's action survives a hold |
| `app/models/block_types/code.rb` (new), `config/initializers/types.rb` | The type |
| `app/components/blocks/code_component.rb`, `.html.erb` (new) | The public render |
| `config/locales/public.en.yml` (new) | "Copy", "Copy code", "Copied", "Not copied" |
| `app/assets/tailwind/themes/default/code.css` (new), `theme.css` | The block's styles |
| `test/components/previews/blocks/code_component_preview.rb` (new) | Lookbook |
| `app/javascript/controllers/code_copy_controller.js` (new) | The Copy button |
| `app/components/admin/editor_screen/block_card_component.*`, `tile_summary_component.rb`, `config/locales/admin/editor_screen.en.yml` | The caption without the library override; the tile's line |
| `app/assets/tailwind/themes/default/tokens.css`, `sections.css`, `app/values/theme/contract.rb`, `docs/reference/theming.md`, a fixture theme (Task 6, after theming) | The seven tokens, the strong band, the two contract entries |
| `docs/reference/content-blocks-and-types.md`, `docs/reference/i18n.md`, `CLAUDE.md`, `docs/roadmap.md`, the spec | Task 7 |

---

### Task 1: Rouge as a dependency, and `CodeHighlight`

**Files:** Modify `Gemfile`, `Gemfile.lock` (by `bundle install`). Create `app/values/code_highlight.rb`, `test/values/code_highlight_test.rb`.

**Interfaces — consumes:** nothing of this plan.

**Interfaces — produces:**

```ruby
CodeHighlight::MAX_CHARACTERS   # 20_000
CodeHighlight::REVISION         # 1; bumped when RULES changes, so cached lines are not reused
CodeHighlight::LANGUAGES        # { "shell" => "Shell", ..., "yaml" => "YAML" }: Rouge's tag => the label; 20 entries, frozen
CodeHighlight::ROLES            # %w[comment keyword string constant tag attribute embed]
CodeHighlight.label(language)   # String or nil ("yaml" => "YAML"; nil, "" and an unlisted tag => nil)
CodeHighlight.lines(code, language, block_id: nil)
  # => Array of lines; a line is an Array of [role, text]; role is one of ROLES (a String) or nil.
  #    [] for no code. Never raises. Cached for a listed language.
CodeHighlight.cache_key(code, language)   # [ "code", sha256 hex of the code, language, Rouge.version, REVISION ]
```

- [ ] **Step 1: the gem.** In `Gemfile`, directly above the `gem "lookbook", …` line:

```ruby
# Colours the Code block's source on the server (code block spec §2). It was
# in the bundle only through Lookbook, a development and test gem; a
# visitor's request runs it now, so it is a dependency of its own.
# `require: false`: requiring Rouge loads every one of its lexers, so it is
# required by the one file that names it (`app/values/code_highlight.rb`).
gem "rouge", "~> 5.1", require: false
```

  Run `bundle install`. Expected: `git diff Gemfile.lock` shows one added line, `  rouge (~> 5.1)`, under `DEPENDENCIES`, and no version changes (`rouge (5.1.0)` was already there).

- [ ] **Step 2: the audit.** Run `bin/bundler-audit`. Expected: `No vulnerabilities found`, exit 0.

- [ ] **Step 3: write the failing test,** `test/values/code_highlight_test.rb`:

```ruby
require "test_helper"

# `CodeHighlight` cuts source into lines of [role, text] pairs (code block spec
# §2). The pairs asserted here were read off Rouge 5.1.0; a Rouge upgrade that
# changes one fails here, and the answer is a look at the page and a bump of
# `CodeHighlight::REVISION` if the role table changes.
class CodeHighlightTest < ActiveSupport::TestCase
  include LogCapture

  RAISING = Class.new { def self.lex(_code) = raise("boom SECRET-CODE") }

  test "the twenty languages are the listed ones, each with a Rouge lexer, and a label is read by tag" do
    assert_equal %w[Shell CSS Dockerfile ERB Go HTML INI JavaScript JSON Markdown nginx PHP Python Ruby Rust SQL TOML TypeScript XML YAML],
      CodeHighlight::LANGUAGES.values
    CodeHighlight::LANGUAGES.each_key { |tag| assert Rouge::Lexer.find(tag), "Rouge has no lexer for #{tag}" }
    assert_equal "YAML", CodeHighlight.label("yaml")
    assert_equal "Dockerfile", CodeHighlight.label("docker")
    assert_nil CodeHighlight.label("xojo")
    assert_nil CodeHighlight.label("")
    assert_nil CodeHighlight.label(nil)
    assert_predicate CodeHighlight::LANGUAGES, :frozen?
    assert_equal 20_000, CodeHighlight::MAX_CHARACTERS
  end

  test "Ruby: a comment, keywords, a string, and an instance variable, a symbol, a number and a constant as constant" do
    lines = CodeHighlight.lines(%(# note\ndef hi\n  @a = :sym + 1 + "s"\n  Foo\nend), "ruby")

    assert_equal [
      [ [ "comment", "# note" ] ],
      [ [ "keyword", "def" ], [ nil, " hi" ] ],
      [ [ nil, "  " ], [ "constant", "@a" ], [ nil, " = " ], [ "constant", ":sym" ], [ nil, " + " ], [ "constant", "1" ], [ nil, " + " ], [ "string", %("s") ] ],
      [ [ nil, "  " ], [ "constant", "Foo" ] ],
      [ [ "keyword", "end" ] ]
    ], lines
  end

  test "ERB: tags, an attribute, a string, and the template delimiters as embed" do
    assert_equal [ [
      [ "tag", "<p" ], [ nil, " " ], [ "attribute", "class=" ], [ "string", %("a") ], [ "tag", ">" ],
      [ "embed", "<%=" ], [ nil, " " ], [ "constant", "@x" ], [ nil, " " ], [ "embed", "%>" ], [ "tag", "</p>" ]
    ] ], CodeHighlight.lines(%(<p class="a"><%= @x %></p>), "erb")
  end

  test "HTML, YAML and shell: a markup comment, a key as attribute, a shell string and comment" do
    assert_equal [ [ [ "tag", "<a" ], [ nil, " " ], [ "attribute", "href=" ], [ "string", %("x") ], [ "tag", ">" ], [ nil, "t" ], [ "tag", "</a>" ], [ "comment", "<!-- c -->" ] ] ],
      CodeHighlight.lines(%(<a href="x">t</a><!-- c -->), "html")
    assert_equal [ [ [ "attribute", "key" ], [ nil, ": " ], [ "string", "value" ], [ nil, " " ], [ "comment", "# c" ] ] ],
      CodeHighlight.lines("key: value # c", "yaml")
    assert_equal [ [ [ nil, "echo " ], [ "string", %("hi") ], [ nil, " " ], [ "comment", "# c" ] ] ],
      CodeHighlight.lines(%(echo "hi" # c), "shell")
  end

  test "every role a line can carry is one of the seven, whatever the language" do
    sample = %(# c\nclass A < B\n  def x = "s" + :y.to_s + 1.to_s\nend\n<a href="x"><%= 1 %></a>\nkey: value\n)
    CodeHighlight::LANGUAGES.each_key do |tag|
      roles = CodeHighlight.lines(sample, tag).flatten(1).map(&:first).compact.uniq
      assert_empty roles - CodeHighlight::ROLES, "#{tag} answered a role that is not one of the seven"
    end
  end

  test "no language, a blank one and a language that is not on the list are plain text, tabs and angle brackets as they are" do
    plain = [ [ [ nil, "a < b" ] ], [ [ nil, "\tc" ] ] ]

    assert_equal plain, CodeHighlight.lines("a < b\n\tc", nil)
    assert_equal plain, CodeHighlight.lines("a < b\n\tc", "")
    assert_equal plain, CodeHighlight.lines("a < b\n\tc", "xojo"), "Rouge has a lexer for it, the list does not"
  end

  test "a lexer that raises is plain text, and the log names the block and holds no code" do
    log = capture_log do
      with_singleton_override(Rouge::Lexer, :find, ->(_tag) { RAISING }) do
        assert_equal [ [ [ nil, "SECRET-CODE = 1" ] ] ], CodeHighlight.lines("SECRET-CODE = 1", "ruby", block_id: 812)
      end
    end

    assert_match(/CodeHighlight: the ruby lexer raised RuntimeError for block 812/, log)
    assert_not_includes log, "SECRET-CODE"
  end

  test "lines: an empty line keeps its place, a last line break adds none, no code is no line, and a carriage return is a line break" do
    assert_equal [ [ [ nil, "a" ] ], [], [ [ nil, "b" ] ] ], CodeHighlight.lines("a\n\nb", nil)
    assert_equal [ [ [ nil, "a" ] ] ], CodeHighlight.lines("a\n", nil)
    assert_equal [], CodeHighlight.lines("", nil)
    assert_equal [], CodeHighlight.lines(nil, "ruby")
    assert_equal [ [ [ nil, "a" ] ], [ [ nil, "b" ] ], [ [ nil, "c" ] ] ], CodeHighlight.lines("a\r\nb\rc", nil)
  end

  test "the coloured lines are cached by the code, the language, Rouge's version and the revision" do
    was = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    first = CodeHighlight.lines("def a; end", "ruby")
    assert_equal [ [ [ "keyword", "def" ], [ nil, " a; " ], [ "keyword", "end" ] ] ], first

    with_singleton_override(Rouge::Lexer, :find, ->(_tag) { RAISING }) do
      assert_equal first, CodeHighlight.lines("def a; end", "ruby"), "the second read is the cache's: the lexer was not asked"
      assert_equal [ [ [ nil, "def b; end" ] ] ], CodeHighlight.lines("def b; end", "ruby"), "other code is another key"
    end
    assert_equal [ "code", Digest::SHA256.hexdigest("x"), "ruby", Rouge.version, CodeHighlight::REVISION ], CodeHighlight.cache_key("x", "ruby")
  ensure
    Rails.cache = was
  end
end
```

- [ ] **Step 4: run it to see it fail.** `PGGSSENCMODE=disable bin/rails test test/values/code_highlight_test.rb`. Expected: every test errors with `NameError: uninitialized constant CodeHighlight`.

- [ ] **Step 5: implement,** `app/values/code_highlight.rb`:

```ruby
require "rouge"

# Source code cut into the seven colour roles a theme has tokens for (code
# block spec §2), on the server, so a public page needs no script to colour
# code. `lines` answers data, never markup: one array per line of
# [role, text] pairs, the role nil for plain text. The template decides the
# elements and the class names; this decides only what is a keyword.
#
# THE ONE PLACE THAT NAMES ROUGE. Rouge was a development gem (it came with
# Lookbook); a visitor's request runs it now. So it is confined here, and
# nothing here may fail a page: no language, a stored language that is not
# on the list (a list that shrank, a row written around the services) and a
# lexer that raises are all plain text. Rouge's lexers are regular
# expressions, so a crafted input could be slow; the block's limit
# (`MAX_CHARACTERS`) bounds it, an editor is the only author and the result
# is cached, so a slow one is paid once per change. If one is ever found,
# `Regexp.timeout` around the lex, with the same plain answer, is the fix.
#
# WHAT IS CACHED is these lines, not HTML, so a theme's template is never
# inside the cache. The key is the code's digest, the language, Rouge's
# version and `REVISION`: bump `REVISION` when `RULES` changes.
module CodeHighlight
  MAX_CHARACTERS = 20_000
  REVISION = 1

  # Rouge's tag => the label an editor reads (and a visitor, above the code).
  # The list only grows: a stored tag that is no longer here is drawn plain.
  LANGUAGES = {
    "shell" => "Shell", "css" => "CSS", "docker" => "Dockerfile", "erb" => "ERB", "go" => "Go",
    "html" => "HTML", "ini" => "INI", "javascript" => "JavaScript", "json" => "JSON", "markdown" => "Markdown",
    "nginx" => "nginx", "php" => "PHP", "python" => "Python", "ruby" => "Ruby", "rust" => "Rust",
    "sql" => "SQL", "toml" => "TOML", "typescript" => "TypeScript", "xml" => "XML", "yaml" => "YAML"
  }.freeze

  # The seven roles, each a theme token (`--th-syn-<role>`) and a class
  # (`syn-<role>`). Strings, so the cached lines read the same whatever
  # serializer the cache store uses.
  ROLES = %w[comment keyword string constant tag attribute embed].freeze

  # Rouge's token names by prefix, most specific first. `Comment.Preproc` is
  # `embed`, which is what makes ERB's delimiters stand out. Everything that
  # matches none is plain.
  RULES = [
    [ "Comment.Preproc", "embed" ],
    [ "Comment", "comment" ],
    [ "Keyword", "keyword" ],
    [ "Literal.String.Symbol", "constant" ],
    [ "Literal.String", "string" ],
    [ "Literal.Number", "constant" ],
    [ "Name.Variable.Instance", "constant" ],
    [ "Name.Constant", "constant" ],
    [ "Name.Tag", "tag" ],
    [ "Name.Attribute", "attribute" ]
  ].freeze

  module_function

  def label(language) = LANGUAGES[language.to_s]

  # `block_id` is only for the log line of a lexer that raised.
  def lines(code, language, block_id: nil)
    code = code.to_s.gsub(/\r\n?/, "\n")
    lexer = lexer_for(language)
    return plain(code) if lexer.nil?

    Rails.cache.fetch(cache_key(code, language)) { coloured(code, lexer, language, block_id) }
  end

  def cache_key(code, language) = [ "code", Digest::SHA256.hexdigest(code), language.to_s, Rouge.version, REVISION ]

  def lexer_for(language) = LANGUAGES.key?(language.to_s) ? Rouge::Lexer.find(language.to_s) : nil

  # `map` runs the lexer here, inside the rescue: `lex` alone answers a lazy
  # enumerator. The log line names the block and never the code or the
  # error's message, which can quote it.
  def coloured(code, lexer, language, block_id)
    split_lines(lexer.lex(code).map { |token, text| [ role_of(token), text ] })
  rescue StandardError => error
    Rails.logger.warn("CodeHighlight: the #{language} lexer raised #{error.class} for block #{block_id.inspect}; drawn as plain text")
    plain(code)
  end

  def plain(code) = split_lines([ [ nil, code ] ])

  def role_of(token)
    name = token.qualname
    RULES.find { |prefix, _role| name == prefix || name.start_with?("#{prefix}.") }&.last
  end

  # Pairs cut at line breaks, neighbours of one role joined. The line break
  # after the last line adds no line, and no code is no line at all.
  def split_lines(pairs)
    lines = [ [] ]
    pairs.each do |role, text|
      text.split(/(\n)/).each do |part|
        next if part.empty?
        next lines << [] if part == "\n"

        last = lines.last.last
        last && last[0] == role ? last[1] << part : lines.last << [ role, part ]
      end
    end
    lines.pop if lines.last.empty?
    lines
  end
end
```

- [ ] **Step 6: run it to see it pass.** `PGGSSENCMODE=disable bin/rails test test/values/code_highlight_test.rb`. Expected: 9 runs, 0 failures, 0 errors.

- [ ] **Step 7: the guards a new file under `app/values` joins.** Run `PGGSSENCMODE=disable bin/rails test test/lib/dependency_direction_test.rb test/lib/admin_namespace_shadow_test.rb test/lib/production_boot_test.rb` and `bin/rails zeitwerk:check`. Expected: all pass, `All is good!`. Then `bin/rubocop Gemfile app/values/code_highlight.rb test/values/code_highlight_test.rb`: no offences.

- [ ] **Step 8: commit.**

```bash
git add Gemfile Gemfile.lock app/values/code_highlight.rb test/values/code_highlight_test.rb
git commit -m "feat: Rouge as a dependency of its own, and CodeHighlight, the one place that names it"
```

---

### Task 2: the `:code` field type, stored as typed, and its input

A field type end to end, with no block type using it yet: its tests build a definition of their own. The counter's script is exercised in a browser in Task 5, once a block has the field.

**Files:** Modify `app/models/content_model/definition.rb`, `app/models/content_model/field_set.rb`, `app/components/admin/fields/select_field.rb`, `select_field.html.erb`, `app/components/admin/editor_screen/shared_fields_component.rb`, `shared_fields_component.html.erb`, `app/components/admin/editor_screen/held_fields.rb`, `test/lib/admin_i18n_test.rb` (the `CONVERTED` list), `test/components/admin/fields/select_field_test.rb`, `test/components/admin/ui/field_component_test.rb`, `test/components/admin/editor_screen/shared_fields_component_test.rb`, `test/components/admin/editor_screen/held_fields_test.rb`. Create `app/components/admin/fields/code_field.rb`, `code_field.html.erb`, `app/javascript/controllers/admin/editor/code_limit_controller.js`, `config/locales/admin/fields.en.yml`, `test/models/content_model/code_field_test.rb`, `test/components/admin/fields/code_field_test.rb`.

**Interfaces — consumes:** nothing of this plan (a test names 20,000 as a number).

**Interfaces — produces:**

```ruby
t.field :code, :code, max: 20_000        # a new scalar type; `max:` counts characters; `translated: true` raises ArgumentError
t.field :language, :select, options: { "ruby" => "Ruby" }, blank: "Plain text"   # `blank:`: the label of a select's empty choice
# FieldSet: a :code value is stored with line endings as "\n", the outer lines of only white space dropped,
#           everything else as typed; only white space is nil; over `max:` is the error :too_long.
Admin::Fields::CodeField                 # the input Admin::Ui::FieldComponent dispatches a :code field to
Admin::EditorScreen::SharedFieldsComponent::Code   # Data.define(:text): what `.display` answers for a :code field with a value
Admin::EditorScreen::HeldFields::ALLOWED_ACTIONS   # + "admin--editor--code-limit#update"
```

  Markup of the field, for Task 5's tests: `textarea#<prefix>-code[name='block[settings][code]']`, its counter `p#<prefix>-code-count`, both inside `[data-controller='admin--editor--code-limit']`.

- [ ] **Step 1: write the failing model test,** `test/models/content_model/code_field_test.rb`:

```ruby
require "test_helper"

# The `:code` field type (code block spec §1): source is kept as typed. A
# `:text` field is stripped at both ends, which would take the first line's
# indentation.
class ContentModel::CodeFieldTest < ActiveSupport::TestCase
  setup do
    @definition = ContentModel::BlockTypeDefinition.new("sample").tap do |t|
      t.field :language, :select, options: { "ruby" => "Ruby" }, blank: "Plain text"
      t.field :code, :code, max: 10
    end
  end

  def fields(values) = ContentModel::FieldSet.for(@definition).new({}).assign(values)

  test "the first line's indentation, tabs and inner blank lines are kept as typed" do
    typed = "    one\n\ttwo\n\n  x  "

    assert_equal typed, fields("code" => typed).code
    assert_equal({ "code" => typed }, fields("code" => typed).untranslated_hash)
  end

  test "a line ending is one line break, whatever the browser sent" do
    assert_equal "a\nb\nc", fields("code" => "a\r\nb\rc").code
  end

  test "leading and trailing lines of only white space are dropped, and only white space is nothing" do
    assert_equal "  a\n b", fields("code" => "\n \t\n  a\n b\n\t\n\n").code
    assert_nil fields("code" => " \n\t\n").code
    assert_equal({}, fields("code" => " \n\t\n").untranslated_hash)
    assert_nil fields("code" => "").code
  end

  test "more characters than max is too long, counted after line endings are one character, and the text is still in the object" do
    over = fields("code" => "x" * 11)

    assert_not over.valid?
    assert_equal [ "is too long (maximum is 10 characters)" ], over.errors[:code]
    assert_equal "x" * 11, over.code, "a refused value is not cut"
    assert fields("code" => "x" * 10).valid?
    assert fields("code" => "ab\r\ncd\r\nefgh").valid?, "twelve characters as sent, ten as stored"
    assert fields("code" => "é" * 10).valid?, "characters, not bytes"
  end

  test "a code field is never translated" do
    error = assert_raises(ArgumentError) { ContentModel::BlockTypeDefinition.new("x").field(:code, :code, translated: true) }

    assert_equal "code fields can't be translated (the code is the same in every language)", error.message
  end

  test "a blank label is for a select that is not required, and for nothing else" do
    assert_raises(ArgumentError) { ContentModel::BlockTypeDefinition.new("x").field(:name, :string, blank: "None") }
    assert_raises(ArgumentError) { ContentModel::BlockTypeDefinition.new("x").field(:kind, :select, options: %w[a], required: true, blank: "None") }
    assert_equal "Plain text", @definition.fields.first.options[:blank]
  end

  test "a select with a blank label still refuses a value that is not on its list, and takes none" do
    assert_not fields("language" => "cobol").valid?
    assert fields("language" => "").valid?
    assert fields("language" => "ruby").valid?
  end
end
```

- [ ] **Step 2: run it to see it fail.** `PGGSSENCMODE=disable bin/rails test test/models/content_model/code_field_test.rb`. Expected: every test errors in `setup` with `ArgumentError: unknown field option(s) [:blank]`.

- [ ] **Step 3: implement the type.** In `app/models/content_model/definition.rb`, replace the three constant lines (`SCALAR_TYPES`, `GROUP_TYPES`, `OPTIONS`) with the first block below, and add the two refusals of the second block to `#field`, after its `select fields need` line:

```ruby
    # `:code` is source code: stored as typed (`FieldSet#cast_code`), never
    # stripped like `:text`, and never translated -- the code is the same in
    # every language, and a translated field is what is offered to an AI
    # provider (`Admin::Ui::FieldComponent::TRANSLATABLE_TYPES` does not list
    # it either).
    SCALAR_TYPES = %i[string text code integer boolean date url select content_type tag].freeze
    GROUP_TYPES = %i[group groups].freeze
    # `blank:` is the label of a select's empty choice ("Plain text"); without
    # it the choice has no label. `max:` counts characters for a `:code` field
    # and is a number's upper bound for an `:integer`.
    OPTIONS = %i[required default min max translated options of blank].freeze
```

```ruby
      raise ArgumentError, "code fields can't be translated (the code is the same in every language)" if type == :code && options[:translated]
      raise ArgumentError, "`blank:` names the empty choice of a select that isn't required" if options.key?(:blank) && (type != :select || options[:required])
```

  In `app/models/content_model/field_set.rb`, in `#cast`, add the `:code` line to the `case`:

```ruby
        case field.type
        when :integer then Integer(value.to_s, exception: false)
        when :boolean then ActiveModel::Type::Boolean.new.cast(value)
        when :date then parse_date(value)
        when :code then cast_code(value)
        else value.to_s.strip.presence
        end
```

  directly under `#cast`:

```ruby
      # Source code (`:code`, code block spec §1) is kept as typed: the first
      # line's indentation, tabs, inner blank lines and trailing spaces. Two
      # things are not content: which line ending the browser sent (a form
      # submits CRLF) and lines of only white space before the first line and
      # after the last, which a paste brings along. Lines, not a regular
      # expression: a run of blank lines in the middle of 20,000 characters
      # must not be walked once per line.
      def cast_code(value)
        lines = value.to_s.gsub(/\r\n?/, "\n").split("\n", -1)
        lines.shift while lines.any? && lines.first.strip.empty?
        lines.pop while lines.any? && lines.last.strip.empty?
        lines.join("\n").presence
      end
```

  and in `#validate_fields`, after the two `:inclusion` lines:

```ruby
          errors.add(field.name, :too_long, count: field.options[:max]) if field.type == :code && field.options[:max] && value.length > field.options[:max]
```

- [ ] **Step 4: run it to see it pass.** `PGGSSENCMODE=disable bin/rails test test/models/content_model`. Expected: 0 failures, 0 errors (the folder's other files included).

- [ ] **Step 5: write the failing component tests.** `test/components/admin/fields/code_field_test.rb`:

```ruby
require "test_helper"

class Admin::Fields::CodeFieldTest < ViewComponent::TestCase
  Field = ContentModel::Definition::Field

  def render_field(value, **options)
    field = Field.new(name: "code", type: :code, options: options)
    render_inline Admin::Fields::CodeField.new(field:, form_name: "block[settings]", value: value, locale: "en", id_prefix: "block-7")
  end

  def counter = "p#block-7-code-count"

  test "a monospace textarea of twelve rows that neither wraps nor corrects, with the code as typed and no maxlength" do
    render_field("  def a\n\tb", max: 20_000)

    assert_selector "textarea#block-7-code[name='block[settings][code]'][rows='12'][wrap='off'][spellcheck='false'][autocapitalize='off'][autocomplete='off']"
    assert_selector "textarea.font-cs-mono.whitespace-pre.overflow-auto"
    assert_includes page.find("textarea")[:class], "[tab-size:2]"
    assert_equal "  def a\n\tb", Nokogiri::HTML5.fragment(rendered_content).at_css("textarea").text
    assert_no_selector "textarea[maxlength]"
  end

  test "the counter is in the page and hidden below nine tenths of the limit, reads the count from there, and warns over the limit" do
    render_field("x" * 17_999, max: 20_000)
    assert_selector "#{counter}[hidden]", visible: :all

    render_field("x" * 18_412, max: 20_000)
    assert_selector "#{counter}.text-meta:not([hidden])", text: "18,412 of 20,000"

    render_field("x" * 20_001, max: 20_000)
    assert_selector "#{counter}.text-warn-ink:not([hidden])", text: "20,001 of 20,000"
  end

  test "the counter's script has the limit, where it starts, its one message, and reads the field" do
    render_field("x", max: 20_000)

    wrapper = page.find("[data-controller='admin--editor--code-limit']")
    assert_equal "20000", wrapper["data-admin--editor--code-limit-limit-value"]
    assert_equal "18000", wrapper["data-admin--editor--code-limit-from-value"]
    assert_equal "%{used} of %{limit}", JSON.parse(wrapper["data-messages"]).fetch("components.fields.code_field.count")
    assert_selector "textarea[data-admin--editor--code-limit-target='input'][data-action='input->admin--editor--code-limit#update'][aria-describedby='block-7-code-count']"
    assert_selector "#{counter}[data-admin--editor--code-limit-target='output']", visible: :all
  end

  test "without a limit there is no counter and no script" do
    render_field("x")

    assert_selector "textarea#block-7-code"
    assert_no_selector "[data-controller], [data-action], p", visible: :all
  end
end
```

  In `test/components/admin/fields/select_field_test.rb`, add:

```ruby
  test "a select that is not required names its empty choice when the field says how, and leaves it unnamed otherwise" do
    named = Field.new(name: "language", type: :select, options: { options: { "ruby" => "Ruby" }, blank: "Plain text" })
    render_inline Admin::Fields::SelectField.new(field: named, form_name: "block[settings]", value: nil, locale: "en")
    assert_selector "option[value='']", text: "Plain text"

    unnamed = Field.new(name: "size", type: :select, options: { options: %w[small] })
    render_inline Admin::Fields::SelectField.new(field: unnamed, form_name: "block[settings]", value: nil, locale: "en")
    assert_equal "", page.find("option[value='']").text

    required = Field.new(name: "size", type: :select, options: { options: %w[small], required: true })
    render_inline Admin::Fields::SelectField.new(field: required, form_name: "block[settings]", value: "small", locale: "en")
    assert_no_selector "option[value='']"
  end
```

  In `test/components/admin/ui/field_component_test.rb`, add `Field.new(name: "j", type: :code, options: {})` to the list in `"dispatches every scalar field type without raising"`, and add to the same class:

```ruby
  test "a code field is never offered to the AI translation" do
    assert_not_includes Admin::Ui::FieldComponent::TRANSLATABLE_TYPES, :code
  end
```

  In `test/components/admin/editor_screen/shared_fields_component_test.rb`, add:

```ruby
  Field = ContentModel::Definition::Field

  test "a select is shown by its label, an empty one by its blank label, and a value that is not on the list as it is stored" do
    field = Field.new(name: "language", type: :select, options: { options: { "ruby" => "Ruby" }, blank: "Plain text" })
    display = ->(value) { Admin::EditorScreen::SharedFieldsComponent.display(field, value) }

    assert_equal "Ruby", display.("ruby")
    assert_equal "Plain text", display.(nil)
    assert_equal "cobol", display.("cobol")
    assert_equal "small", Admin::EditorScreen::SharedFieldsComponent.display(Field.new(name: "size", type: :select, options: { options: %w[small] }), "small")
  end

  test "code is shown in a scrolling pre of at most twelve lines, as text, and no code as a dash" do
    field = Field.new(name: "code", type: :code, options: {})
    shown = Admin::EditorScreen::SharedFieldsComponent.display(field, "  a <b>bold</b>\n\tb")
    assert_nil Admin::EditorScreen::SharedFieldsComponent.display(field, nil)

    render_inline(Admin::EditorScreen::SharedFieldsComponent.new(fields: [ [ "Code", shown ], [ "Filename", nil ] ]))

    assert_selector "dd pre[tabindex='0'].overflow-auto", visible: :all
    assert_includes page.find("dd pre", visible: :all)[:class], "max-h-[12lh]"
    assert_equal "  a <b>bold</b>\n\tb", Nokogiri::HTML5.fragment(rendered_content).at_css("dd pre").text
    assert_no_selector "dd b", visible: :all
    assert_text :all, "—"
  end
```

  In `test/components/admin/editor_screen/held_fields_test.rb`, add `"input->admin--editor--code-limit#update"` as the last entry of the test's own `ALLOWED` list, and add:

```ruby
  test "Admin::Fields::CodeField, rewritten: the code is read-only with its indentation and its counter's action is the one left" do
    field = ContentModel::Definition::Field.new(name: "code", type: :code, options: { max: 20_000 })
    render_inline Admin::Ui::FieldComponent.new(field: field, form_name: "block[settings]", value: "    indented\n\tb", locale: "en", id_prefix: "block-1")

    assert_survives(rendered_content)
    rewritten = Nokogiri::HTML5.fragment(held(rendered_content))
    assert rewritten.at_css("textarea[name='block[settings][code]'][readonly]")
    assert_equal "    indented\n\tb", rewritten.at_css("textarea").text
    assert_equal [ "input->admin--editor--code-limit#update" ], rewritten.css("[data-action]").map { |node| node["data-action"] }
  end
```

- [ ] **Step 6: run them to see them fail.** `PGGSSENCMODE=disable bin/rails test test/components/admin/fields test/components/admin/ui/field_component_test.rb test/components/admin/editor_screen/shared_fields_component_test.rb test/components/admin/editor_screen/held_fields_test.rb`. Expected: `NameError: uninitialized constant Admin::Fields::CodeField` in the code field's tests, the dispatch test and the held test; the select test fails on `"Plain text"`; the shared-fields tests fail (`"ruby"` where `"Ruby"` is expected, a String where the pre is expected).

- [ ] **Step 7: implement the input.** `config/locales/admin/fields.en.yml`:

```yaml
# CS Studio's schema field inputs, `app/components/admin/fields/` (docs/reference/i18n.md).
# Keys are `admin.components.fields.<class name without Admin::Fields::, underscored>`.
# YAML: a value with a `%{...}` in it is double-quoted.
en:
  admin:
    components:
      fields:
        # Under a code field, from nine tenths of its limit: "18,412 of 20,000".
        # Both numbers arrive formatted for the reader's language. The server
        # writes it once and `admin--editor--code-limit` keeps it current.
        code_field:
          count: "%{used} of %{limit}"
```

  `app/components/admin/fields/code_field.rb`:

```ruby
module Admin
  module Fields
    # Source code (code block spec §3), for `:code` fields: a plain textarea
    # in the monospace face that neither wraps nor corrects. No code editor
    # library and no colours here; the Tab key leaves the field, as in every
    # textarea (spec decision 5, confirmed by the owner).
    #
    # No `maxlength`: it would cut a paste without a word. The limit
    # (`max:`) is the server's to refuse, with the text kept in the field,
    # and from nine tenths of it a counter says how much is used.
    #
    # The counter is `admin--editor--code-limit`, not the plain columns'
    # `admin--ui--char-count`: that one is always shown and is a hint about a
    # recommended length ("70 / 60 · long"); this one stays out of the way
    # until the limit is near, and the limit is real.
    class CodeField < Base
      COUNTER_FROM = 0.9

      def rows = 12

      def limit = field.options[:max]

      def counter? = limit.present?

      def threshold = (limit * COUNTER_FROM).floor

      # Characters as the server counts them (`String#length`), which is what
      # the script's `Array.from(value).length` counts too.
      def used = value.to_s.length

      def counter_shown? = used >= threshold

      def over? = used > limit

      def counter_id = "#{input_id}-count"

      def counter_text = t(".count", used: helpers.number_with_delimiter(used), limit: helpers.number_with_delimiter(limit))

      def counter_class = [ "mt-1 text-right font-cs-mono text-xs", (over? ? "text-warn-ink" : "text-meta") ]

      def input_class = "#{setup_input_class} font-cs-mono text-sm whitespace-pre overflow-auto [tab-size:2]"

      def wrapper_data
        return {} unless counter?

        {
          controller: "admin--editor--code-limit",
          "admin--editor--code-limit-limit-value": limit,
          "admin--editor--code-limit-from-value": threshold,
          messages: messages_data("components.fields.code_field.count")
        }
      end

      # The script only reads the field (`HeldFields::ALLOWED_ACTIONS`).
      def input_data = counter? ? { "admin--editor--code-limit-target": "input", action: "input->admin--editor--code-limit#update" } : {}
    end
  end
end
```

  `app/components/admin/fields/code_field.html.erb`:

```erb
<%= tag.div(data: wrapper_data) do %>
  <%= tag.textarea value, name: input_name, id: input_id, class: input_class, rows: rows, wrap: "off",
        spellcheck: "false", autocapitalize: "off", autocomplete: "off", required: field.required?,
        aria: ({ describedby: counter_id } if counter?), data: input_data %>
  <% if counter? %>
    <%= tag.p counter_text, id: counter_id, hidden: !counter_shown?, class: counter_class, data: { "admin--editor--code-limit-target": "output" } %>
  <% end %>
<% end %>
```

  `app/javascript/controllers/admin/editor/code_limit_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"
import { messages } from "i18n/messages"

// The counter under a code field (code block spec §3): hidden until the text
// is within a tenth of the limit, then "18,412 of 20,000", in the warning
// colour once it is over. It counts what the server counts: `Array.from`
// walks code points, as Ruby's `String#length` does.
//
// It only READS the field. It sets no value, has nothing to tell autosave,
// and is one of the actions that survive in a form someone else holds
// (`Admin::EditorScreen::HeldFields::ALLOWED_ACTIONS`). The limit itself is
// the server's: a save over it is the form's ordinary 422, with the text
// left in the field.
export default class extends Controller {
  static targets = [ "input", "output" ]
  static values = { limit: Number, from: Number }

  connect() {
    this.update()
  }

  update() {
    const used = Array.from(this.inputTarget.value).length
    const text = messages(this.element).t("components.fields.code_field.count", { used: this.number(used), limit: this.number(this.limitValue) })

    this.outputTarget.textContent = text
    this.outputTarget.hidden = used < this.fromValue
    this.outputTarget.classList.toggle("text-warn-ink", used > this.limitValue)
    this.outputTarget.classList.toggle("text-meta", used <= this.limitValue)
  }

  // Grouped for the reader's language, as the server's first paint is; a
  // locale tag `Intl` rejects gets the bare digits.
  number(value) {
    try {
      return new Intl.NumberFormat(messages(this.element).locale()).format(value)
    } catch (error) {
      return String(value)
    }
  }
}
```

  `app/components/admin/fields/select_field.rb`, in the class:

```ruby
      # The empty choice of a select that is not required: unnamed, unless
      # the field says what it means (`blank: "Plain text"`).
      def blank_choice = field.required? ? false : (field.options[:blank] || true)
```

  and in `select_field.html.erb` replace `include_blank: !field.required?` with `include_blank: blank_choice`.

  `app/components/admin/editor_screen/shared_fields_component.rb`: add the value object and two cases, and say so in the class comment (one sentence: "A select is shown by its label and code in a scrolling `pre`, both read-only like the rest").

```ruby
      # Code shown read-only: the template draws it in a `pre`, not as a line of text.
      Code = Data.define(:text)

      def self.display(field, value)
        case field.type
        when :boolean then value ? "Yes" : "No"
        when :groups then (count = Array(value).size).zero? ? nil : "#{count} #{"entry".pluralize(count)}"
        when :group then value.present? ? "Set" : nil
        when :select then select_label(field, value)
        when :code then value.present? ? Code.new(value.to_s) : nil
        else value.to_s
        end
      end

      # The label an editor picked, not the stored value; the empty choice by
      # its own label where it has one; a value that is no longer on the list
      # as it is stored.
      def self.select_label(field, value)
        return field.options[:blank].to_s if value.blank?

        options = field.options[:options]
        (options[value.to_s] if options.is_a?(Hash)) || value.to_s
      end
```

  In `shared_fields_component.html.erb`, replace the `<dd>` line with:

```erb
        <dd class="text-ink">
          <% if value.is_a?(Admin::EditorScreen::SharedFieldsComponent::Code) %>
            <%= tag.pre value.text, tabindex: 0, class: "max-h-[12lh] overflow-auto rounded-cs border border-line bg-sunken p-2 font-cs-mono text-sm [tab-size:2]" %>
          <% else %>
            <%= value.presence || "—" %>
          <% end %>
        </dd>
```

  In `app/components/admin/editor_screen/held_fields.rb`, add `admin--editor--code-limit#update` as the last entry of `ALLOWED_ACTIONS`.

  In `test/lib/admin_i18n_test.rb`, add to `CONVERTED`: `app/components/admin/fields/code_field.rb`, `app/components/admin/fields/code_field.html.erb`, `app/javascript/controllers/admin/editor/code_limit_controller.js`.

- [ ] **Step 8: run them to see them pass.** The command of Step 6. Expected: 0 failures, 0 errors.

- [ ] **Step 9: the guards.** `PGGSSENCMODE=disable bin/rails test test/lib/admin_i18n_test.rb test/lib/source_layout_test.rb test/lib/script_messages_test.rb test/lib/tailwind_sources_test.rb test/lib/admin_design_rules_test.rb test/lib/inline_handlers_test.rb test/lib/erb_comments_test.rb test/components/admin`. Expected: all pass. What each holds here: the new files hold no English (`admin_i18n`); `admin--editor--code-limit` has its controller file, the key `.count` exists, and `fields.en.yml` holds one folder's scope (`source_layout`); the script's message is served by the component's `messages_data` call (`script_messages`); the script's `classList` is under an `@source` path (`tailwind_sources`).

- [ ] **Step 10: design report.** The spec fixes the face, twelve rows, no wrapping and the counter's words. It does not fix: the field's text size (`text-sm`), the counter's place (right-aligned under the field, like the meta title's), that going over the limit is shown by colour and the form's error message but not announced by the counter, and the read-only `pre`'s frame on a translation tab. Report these four to the controller for the design system's owner; build them as written meanwhile.

- [ ] **Step 11: commit.**

```bash
bin/rubocop app/models/content_model app/components/admin/fields app/components/admin/editor_screen test/models/content_model test/components/admin
git add app/models/content_model app/components/admin/fields app/components/admin/editor_screen/shared_fields_component.rb app/components/admin/editor_screen/shared_fields_component.html.erb app/components/admin/editor_screen/held_fields.rb app/javascript/controllers/admin/editor/code_limit_controller.js config/locales/admin/fields.en.yml test/lib/admin_i18n_test.rb test/models/content_model/code_field_test.rb test/components/admin
git commit -m "feat: the code field type — source stored as typed, with a limit the server refuses and a counter near it"
```

---

### Task 3: the Code block type and its public render

After this task an editor can add a Code block and a visitor reads it coloured (uncoloured by role until Task 6 declares the tokens: a `color` whose token is not declared is the inherited ink). The Copy button is in the markup and stays hidden until Task 4's script shows it. The card's caption still carries the Image block's library wording until Task 5.

**Files:** Create `app/models/block_types/code.rb`, `app/components/blocks/code_component.rb`, `app/components/blocks/code_component.html.erb`, `config/locales/public.en.yml`, `app/assets/tailwind/themes/default/code.css`, `test/components/blocks/code_component_test.rb`, `test/components/previews/blocks/code_component_preview.rb`. Modify `config/initializers/types.rb`, `app/assets/tailwind/themes/default/theme.css`, `app/models/content_block.rb` (one phrase of the class comment), `test/models/built_in_types_test.rb`, `test/models/content_block_test.rb`, `test/integration/public_blocks_test.rb`, `test/integration/public_canary_test.rb`, `test/integration/design_tokens_test.rb`, `test/services/translation_state_parity_test.rb`.

**Interfaces — consumes:** `CodeHighlight::LANGUAGES`, `MAX_CHARACTERS`, `ROLES`, `.label(language)`, `.lines(code, language, block_id:)` (Task 1); the `:code` field type and `blank:` (Task 2).

**Interfaces — produces:**

```ruby
BlockTypes::Code.register            # the type "code": fields language (:select), filename (:string), code (:code); uses :caption; capability :code
BlockTypes.names                     # => %w[rich_text image code post_list section]
Blocks::CodeComponent.new(block:, page:)   # renders nothing for a block with no code
# What its template may call (Task 6 lists these in the theming contract), each safe for an empty block:
#   block, page, lines, code, language (the tag), language_label, filename, caption
# I18n: public.blocks.code.{copy, copy_code, copied, failed}
```

  Markup, for Task 4's script and tests: `figure.content-block--code[data-controller='code-copy'][data-code-copy-copied-value][data-code-copy-failed-value]`, holding `button[hidden][data-code-copy-target='button'][data-action='code-copy#copy']`, `[role='status'][data-code-copy-target='status']` and `pre[tabindex='0'][data-code-copy-target='source']`.

- [ ] **Step 1: write the failing component test,** `test/components/blocks/code_component_test.rb`:

```ruby
require "test_helper"

class Blocks::CodeComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper

  CODE = "def hi\n  1\nend".freeze
  HOSTILE = %(</pre></code><script>alert(1)</script>\n<%= @x %> & <b>bold</b>).freeze

  def code_block(settings = {}, **attributes)
    root_page.content_blocks.create!(block_type: :code, position: 0,
      settings: { "language" => "ruby", "filename" => "app/hi.rb", "code" => CODE }.merge(settings).compact, **attributes)
  end

  def draw(block) = render_inline(Blocks::CodeComponent.new(block: block, page: root_page))

  # The markup as a browser parses it.
  def fragment = Nokogiri::HTML5.fragment(rendered_content)

  test "a figure with the file name and language above the code, a hidden Copy button, a status line and the code coloured" do
    block = code_block
    draw(block)

    assert_selector "figure.content-block.content-block--code[data-controller='code-copy'][data-code-copy-copied-value='Copied'][data-code-copy-failed-value='Not copied']"
    assert_selector ".code-head .code-file#code-#{block.id}-file", text: "app/hi.rb"
    assert_selector ".code-head .code-language", text: "Ruby"
    assert_selector ".code-head button[type='button'][hidden][data-code-copy-target='button'][data-action='code-copy#copy'][aria-label='Copy code'][aria-describedby='code-#{block.id}-file']",
      text: "Copy", visible: :all
    assert_selector ".code-head [role='status'].sr-only[data-code-copy-target='status']", visible: :all
    assert_selector "pre[tabindex='0'][data-code-copy-target='source'] > code span.syn-keyword", text: "def"
    assert_equal CODE, fragment.at_css("pre").text, "the code's text is the stored code, to the character"
    assert_no_selector "figcaption"
  end

  test "a block with no code draws nothing" do
    draw(code_block("code" => nil, "filename" => "empty.rb"))

    assert_equal "", rendered_content.strip
  end

  test "the head is drawn without a file name or a language: it holds the button, which then describes itself by nothing" do
    draw(code_block("filename" => nil, "language" => nil))

    assert_selector ".code-head button[data-code-copy-target='button']", visible: :all
    assert_no_selector ".code-file, .code-language, button[aria-describedby]", visible: :all
    assert_empty fragment.css("pre span"), "no language is plain text"
  end

  test "source, file name and caption that look like markup are text: one pre, no script, no element the template did not write" do
    [ "erb", "html", nil ].each do |language|
      draw(code_block({ "language" => language, "filename" => "<i>x</i>.rb", "code" => HOSTILE }, caption: "<b>cap</b>"))

      assert_equal 1, fragment.css("pre").size, language.inspect
      assert_empty fragment.css("script, b, i"), language.inspect
      assert_equal HOSTILE, fragment.at_css("pre").text, language.inspect
      assert_empty fragment.css("pre *").map(&:name).uniq - %w[code span], language.inspect
      spans = fragment.css("pre span")
      assert_empty spans.flat_map { |span| span.attributes.keys }.uniq - %w[class], "a span carries a class and nothing else"
      assert_empty spans.map { |span| span["class"] }.uniq - CodeHighlight::ROLES.map { |role| "syn-#{role}" }, "a class is one of the seven roles'"
      assert_equal "<i>x</i>.rb", fragment.at_css(".code-file").text
      assert_equal "<b>cap</b>", fragment.at_css("figcaption").text.strip
    end
  end

  test "a stored language that is not on the list is plain text and names no language" do
    block = code_block
    block.update_columns(settings: block.settings.merge("language" => %(cobol"><script>))) # version: none (a test writes the row a list that shrank would leave)

    draw(block.reload)

    assert_no_selector ".code-language"
    assert_empty fragment.css("pre span, script")
    assert_equal CODE, fragment.at_css("pre").text
  end

  test "a lexer that raises still draws the code" do
    raising = Class.new { def self.lex(_code) = raise("boom") }

    with_singleton_override(Rouge::Lexer, :find, ->(_tag) { raising }) { draw(code_block) }

    assert_equal CODE, fragment.at_css("pre").text
    assert_selector ".code-language", text: "Ruby"
    assert_empty fragment.css("pre span")
  end

  test "the caption is the visitor's language with fallback, and the four public strings fall back to English" do
    with_locales(%w[en de], default: "en") do
      block = code_block({}, caption: "A sample")

      I18n.with_locale(:de) { draw(block) }
      assert_selector "figcaption", text: "A sample"
      assert_selector "button[aria-label='Copy code']", text: "Copy", visible: :all
      assert_selector "figure[data-code-copy-copied-value='Copied'][data-code-copy-failed-value='Not copied']"

      Mobility.with_locale(:de) { block.update!(caption: "Ein Beispiel") }
      I18n.with_locale(:de) { draw(block) }
      assert_selector "figcaption", text: "Ein Beispiel"
    end
  end

  test "nothing in the component, its template or the highlighter marks a string as safe, and only the highlighter names Rouge" do
    %w[app/components/blocks/code_component.rb app/components/blocks/code_component.html.erb app/values/code_highlight.rb].each do |path|
      assert_no_match(/html_safe|\braw\b|safe_join|Formatters/, Rails.root.join(path).read, path)
    end
    naming = Dir[Rails.root.join("app/**/*.{rb,erb,js}")].select { |path| File.read(path).match?(/\bRouge\b/) }
    assert_equal [ Rails.root.join("app/values/code_highlight.rb").to_s ], naming
  end
end
```

  In `test/models/built_in_types_test.rb` (`"built-ins are registered"`) and in `test/models/content_block_test.rb` (`"block_type is a string checked against the BlockTypes registry"`), change the expected names to `%w[rich_text image code post_list section]`, and add to `built_in_types_test.rb`:

```ruby
  test "code is a block of three settings and a caption, none of them required, the code never translated" do
    code = BlockTypes.fetch(:code)

    assert_equal "Code", code.label
    assert_equal [ %w[language select], %w[filename string], %w[code code] ], code.fields.map { |field| [ field.name, field.type.to_s ] }
    assert_equal %w[caption], code.uses_columns
    assert code.capability?(:code)
    assert_equal Blocks::CodeComponent, code.component
    assert code.fields.none? { |field| field.required? || field.translated? }
    assert_equal CodeHighlight::LANGUAGES, code.fields.first.options[:options]
    assert_equal "Plain text", code.fields.first.options[:blank]
    assert_equal 20_000, code.fields.last.options[:max]
  end
```

- [ ] **Step 2: run them to see them fail.** `PGGSSENCMODE=disable bin/rails test test/components/blocks/code_component_test.rb test/models/built_in_types_test.rb test/models/content_block_test.rb`. Expected: the component tests error with `ActiveRecord::RecordInvalid: Validation failed: Block type isn't a registered block type`; the two name tests fail on the list; the new type test errors in `BlockTypes.fetch(:code)` (`ContentModel::UnknownType`).

- [ ] **Step 3: implement the type and the component.** `app/models/block_types/code.rb`:

```ruby
module BlockTypes
  # Source code with a language, an optional file name and a caption (code
  # block spec §1). The three settings are the same in every language of the
  # site and live in `settings`; the caption is the block's existing
  # translated `caption` column, its only translated field, and optional, so
  # a Code block never makes its page "missing" in a language.
  #
  # Nothing is required: the block picker makes an empty block first, as it
  # does for an image, and the public component draws nothing until there is
  # code. `:code` is the capability the editor's tile asks, never the type's
  # name. The languages, the limit and the colouring are `CodeHighlight`'s.
  module Code
    def self.register
      BlockTypes.register :code do |t|
        t.label "Code"
        t.field :language, :select, options: CodeHighlight::LANGUAGES, blank: "Plain text"
        t.field :filename, :string
        t.field :code, :code, max: CodeHighlight::MAX_CHARACTERS
        t.uses :caption
        t.capability :code
        t.component Blocks::CodeComponent
      end
    end
  end
end
```

  In `config/initializers/types.rb`, after `BlockTypes::Image.register`:

```ruby
  BlockTypes::Code.register
```

  In `app/models/content_block.rb`'s class comment, end the sentence that lists which columns matter with ", `settings` + `caption` for code."

  `config/locales/public.en.yml`:

```yaml
# The public site's own strings: what the default theme's templates say to a
# visitor that no editor typed. Read in the visitor's language, with English
# as the fallback (`Blocks::CodeComponent#string`), so a language without a
# `public.<locale>.yml` shows English and never "translation missing".
#
# This file starts ahead of the roadmap's item on translating the public site
# (item 7 of "Next"): the Code block's four strings are the first keys, the
# site's other strings are still literals in the templates, and that item
# moves them here and adds German and Spanish.
en:
  public:
    blocks:
      # The Code block's copy button: its label, its accessible name, and
      # what it says for two seconds after a press (or when the browser
      # refuses the clipboard).
      code:
        copy: "Copy"
        copy_code: "Copy code"
        copied: "Copied"
        failed: "Not copied"
```

  `app/components/blocks/code_component.rb`:

```ruby
module Blocks
  # Source code, coloured on the server (`BlockTypes::Code`, code block spec
  # §4). Built like `Blocks::ImageComponent`: it reads the block it is handed
  # -- a published view on the site, the rows in a preview -- and nothing
  # else.
  #
  # THE CODE IS TEXT. The template prints each token's text through ERB's
  # own escaping and wraps a coloured one in a span whose class is one of
  # `CodeHighlight::ROLES`. Nothing here, in the template or in
  # `CodeHighlight` marks a string as safe, and the highlighter's own markup
  # output is not used, so the code can add no element, no attribute and no
  # class to the page (`test/components/blocks/code_component_test.rb`).
  # The file name and the caption are escaped text too.
  #
  # The head is always drawn, since it holds the Copy button; the button is
  # `hidden` in the markup and `code-copy` shows it where there is a
  # clipboard, so without JavaScript the code is all there and only the
  # button is missing.
  class CodeComponent < ApplicationComponent
    def initialize(block:, page:)
      @block = block
      @page = page
    end

    def render? = code.present?

    private

    attr_reader :block, :page

    # The three settings are untranslated: one value for every language.
    def settings = @settings ||= block.settings_object

    def code = settings&.code

    # The language's tag as stored, or nil. A tag that is no longer on the
    # list has no label and is drawn plain.
    def language = settings&.language

    def language_label = CodeHighlight.label(language)

    def filename = settings&.filename

    # One array per line of [role, text] pairs; the role is nil for plain text.
    def lines = CodeHighlight.lines(code, language, block_id: block.id)

    # The block's one translated field, in the visitor's language with fallback.
    def caption = translated(block, :caption)

    def file_id = "code-#{block.id}-file"

    # One of the block's four public strings, in the visitor's language where
    # `config/locales/public.<locale>.yml` has it, in English otherwise.
    def string(key)
      full = "public.blocks.code.#{key}"
      I18n.t(full, locale: I18n.exists?(full, I18n.locale) ? I18n.locale : :en)
    end
  end
end
```

  `app/components/blocks/code_component.html.erb` (the `pre` is ONE line on purpose: any white space between its tags would be part of the code):

```erb
<%# The copy script's markup (the identifier, its three targets, its action and its two
    values) is what a theme's own template has to write to keep the button working. %>
<figure class="content-block content-block--code" data-controller="code-copy" data-code-copy-copied-value="<%= string(:copied) %>" data-code-copy-failed-value="<%= string(:failed) %>">
  <div class="code-head">
    <% if filename.present? %>
      <span class="code-file" id="<%= file_id %>"><%= filename %></span>
    <% end %>
    <% if language_label %>
      <span class="code-language"><%= language_label %></span>
    <% end %>
    <%= tag.button string(:copy), type: "button", hidden: true, aria: { label: string(:copy_code), describedby: (file_id if filename.present?) },
          data: { code_copy_target: "button", action: "code-copy#copy" } %>
    <span class="sr-only" role="status" data-code-copy-target="status"></span>
  </div>
  <pre tabindex="0" data-code-copy-target="source"><code><% lines.each_with_index do |line, index| %><%= "\n" if index.positive? %><% line.each do |role, text| %><% if role %><%= tag.span(text, class: "syn-#{role}") %><% else %><%= text %><% end %><% end %><% end %></code></pre>
  <% if caption.present? %>
    <figcaption><%= caption %></figcaption>
  <% end %>
</figure>
```

- [ ] **Step 4: run them to see them pass.** The command of Step 2. Expected: 0 failures, 0 errors.

- [ ] **Step 5: write the tests of the page, the copy and the translation state, and the failing test of the stylesheet.** In `test/integration/public_blocks_test.rb`:

```ruby
  test "a code block is drawn with its head and its code coloured, at the top level and in a column of a section" do
    section = @root.content_blocks.create!(block_type: :section, position: 0, settings: { "layout" => "two" })
    @root.content_blocks.create!(block_type: :code, position: 1, settings: { "language" => "ruby", "filename" => "a.rb", "code" => "def top; end" })
    @root.content_blocks.create!(block_type: :code, position: 0, section: section, section_column: 2, settings: { "language" => "yaml", "code" => "inside: column" })

    get "/"

    assert_response :success
    assert_select "main figure.content-block--code", count: 2
    assert_select "figure.content-block--code .code-file", text: "a.rb"
    assert_select "figure.content-block--code pre span.syn-keyword", text: "def"
    assert_select ".content-section__column figure.content-block--code pre", text: "inside: column"
    assert_select ".content-section__column figure.content-block--code .code-language", text: "YAML"
  end

  test "a code block on a live page is read from its published copy: a save shows nothing until it is published, and counts as a change" do
    page = create_page(title: "Docs")
    block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "code", settings: { "language" => "ruby", "code" => "first = 1" } }).record
    publish_changes(page)
    path = PublicSite::Urls.new.path_for(page, "en")

    assert ContentBlocks::Save.call(block, attributes: { settings: { "code" => "second = 2" } }).ok?
    get path

    assert_select "figure.content-block--code pre", text: "first = 1"
    assert page.reload.unpublished_changes_at.present?, "a save on a live page marks it"
    assert_equal [ :changed ], Publishing::Changes.of(page).blocks.map(&:kind)
    assert_equal "ruby", block.reload.settings["language"], "a save of the code alone leaves the other settings"

    publish_changes(page)
    get path
    assert_select "figure.content-block--code pre", text: "second = 2"
  end

  test "an empty code block draws nothing on the page" do
    @root.content_blocks.create!(block_type: :code, position: 0)

    get "/"

    assert_response :success
    assert_select "figure.content-block--code", count: 0
  end
```

  In `test/integration/public_canary_test.rb`, in `build_site`, inside the block of `@alpha`, after the line that adds the top-level image block:

```ruby
      block(page, "code", settings: { "language" => "ruby", "filename" => "app/models/sample.rb", "code" => "sample = 1" },
        translations: LOCALES.index_with { |locale| { caption: "Code caption #{locale}" } })
```

  and in the test `"rows overwritten without publishing change nothing a visitor sees, in any language, and publishing brings them"`, directly after `assert_includes before.values.flatten.join, "Deletable words en"`:

```ruby
    assert_includes before.values.flatten.join, "Code caption de", "the site has a Code block on it"
```

  In `test/services/translation_state_parity_test.rb`:

```ruby
  def stored_state(record, locale)
    Translations::State.where(record_type: record.class.polymorphic_name, record_id: record.id, locale: locale).pick(:state)
  end

  # Code block spec §1: the caption is the block's only translated field and
  # is optional; the code is the same in every language.
  test "a code block's caption is tracked like an image's, never missing, and a change of the code changes no state" do
    as_owner do
      page = create_page(title: "Docs", translations: { "de" => { title: "Doku" }, "es" => { title: "Documentos" } })
      block = ContentBlocks::Save.call(page.content_blocks.new, attributes: { block_type: "code", settings: { "language" => "ruby", "code" => "a = 1" } }).record
      assert_parity page
      assert_equal "complete", stored_state(page, "de")

      assert ContentBlocks::Save.call(block, translations: { "en" => { caption: "A sample" } }).ok?
      assert_parity page
      assert_equal "complete", stored_state(page, "de"), "a caption left untranslated is a choice, not a gap"

      assert ContentBlocks::Save.call(block, translations: { "de" => { caption: "Ein Beispiel" } }).ok?
      assert ContentBlocks::Save.call(block, translations: { "en" => { caption: "Another sample" } }).ok?
      assert_parity page
      assert_equal "outdated", stored_state(page, "de")
      assert_equal "complete", stored_state(page, "es")
      assert_equal :outdated, block.reload.translation_state(:caption, "de")

      assert ContentBlocks::Save.call(block, attributes: { settings: { "code" => "a = 2", "filename" => "a.rb", "language" => "python" } }).ok?
      assert_parity page
      assert_equal "outdated", stored_state(page, "de")
      assert_equal "complete", stored_state(page, "es")
    end
  end
```

  In `test/integration/design_tokens_test.rb`:

```ruby
  # Code block spec §4: plain rules on tokens, because the span classes are
  # built from role names and no utility scan would find them.
  test "the code block's stylesheet is imported by the theme, holds no colour of its own, colours each role by its token and keeps a long line inside" do
    css = Rails.root.join("app/assets/tailwind/themes/default/code.css").read

    assert_includes Rails.root.join("app/assets/tailwind/themes/default/theme.css").read, %(@import "./code.css";)
    refute_match(/#\h{3,8}\b|\brgba?\(|\bhsla?\(|\boklch\(/, css)
    CodeHighlight::ROLES.each { |role| assert_match(/\.syn-#{role}\s*\{\s*color:\s*var\(--th-syn-#{role}\);/, css) }
    assert_match(/\.content-block--code\s*\{[^}]*min-width:\s*0;/, css)
    assert_match(/\.content-block--code pre\s*\{[^}]*overflow-x:\s*auto;[^}]*white-space:\s*pre;/m, css)
    assert_match(/\.content-block--code \.code-head\s*\{[^}]*color:\s*var\(--th-dim\);/m, css, "meta on the sunken ground is 4.3:1 in the light theme; the head reads as dim")
  end
```

- [ ] **Step 6: run them to see them fail.** `PGGSSENCMODE=disable bin/rails test test/integration/design_tokens_test.rb`. Expected: the new test errors with `Errno::ENOENT` for `code.css`. (The page, canary and parity tests already pass, since Step 3 built what they ask; run them in Step 8.)

- [ ] **Step 7: the stylesheet.** `app/assets/tailwind/themes/default/code.css`:

```css
/* The Code block (code block spec §4, `Blocks::CodeComponent`). Plain rules
   on tokens, not utilities: the span classes are built from role names
   (`syn-keyword`), which no utility scan would find, and a theme that
   replaces the block's template keeps these by writing the same classes.

   The code and its head stand on the sunken ground, so the head reads as
   `dim`: `meta` on sunken is 4.3:1 in the light theme. A band re-values the
   tokens for what is inside it (`sections.css`), so nothing here knows a
   band.

   `min-width: 0` on the figure and `overflow-x: auto` on the `pre` are what
   keep a long line inside the block, in a column of a section as at full
   width: the line scrolls in the `pre` (which is focusable, so a keyboard
   can scroll it) and the page never scrolls sideways.

   The seven `--th-syn-*` tokens are the theme's (`tokens.css`). A `color`
   whose token is not declared is invalid when computed and so the span
   inherits the code's ink: a role with no token reads as plain text. */
.content-block--code {
  min-width: 0;
  margin-block: 2.5rem;
}
.content-block--code .code-head {
  display: flex;
  align-items: baseline;
  gap: var(--th-sp-3);
  padding: var(--th-sp-2) var(--th-sp-3);
  border: 1px solid var(--th-line);
  border-bottom: 0;
  border-radius: var(--th-radius) var(--th-radius) 0 0;
  background: var(--th-sunken);
  font-family: var(--th-mono);
  font-size: var(--th-t-small);
  color: var(--th-dim);
}
.content-block--code .code-file {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: var(--th-ink);
}
.content-block--code .code-language {
  font-size: var(--th-t-label);
  letter-spacing: var(--th-track-mono);
  text-transform: uppercase;
}
.content-block--code .code-head button {
  margin-inline-start: auto;
  padding: 0 var(--th-sp-1);
  border: 0;
  background: none;
  font: inherit;
  color: var(--th-accent);
  cursor: pointer;
}
.content-block--code .code-head button:hover {
  color: var(--th-accent-hover);
}
.content-block--code .code-head button:focus-visible,
.content-block--code pre:focus-visible {
  outline: 2px solid var(--th-accent);
  outline-offset: 2px;
}
.content-block--code pre {
  margin: 0;
  padding: var(--th-sp-3);
  overflow-x: auto;
  white-space: pre;
  tab-size: 2;
  border: 1px solid var(--th-line);
  border-radius: 0 0 var(--th-radius) var(--th-radius);
  background: var(--th-sunken);
  font-family: var(--th-mono);
  font-size: var(--th-t-small);
  line-height: 1.6;
  color: var(--th-ink);
}
.content-block--code figcaption {
  margin-top: var(--th-sp-2);
  font-family: var(--th-mono);
  font-size: var(--th-t-label);
  letter-spacing: var(--th-track-mono);
  text-transform: uppercase;
  color: var(--th-meta);
}
.content-block--code .syn-comment { color: var(--th-syn-comment); }
.content-block--code .syn-keyword { color: var(--th-syn-keyword); }
.content-block--code .syn-string { color: var(--th-syn-string); }
.content-block--code .syn-constant { color: var(--th-syn-constant); }
.content-block--code .syn-tag { color: var(--th-syn-tag); }
.content-block--code .syn-attribute { color: var(--th-syn-attribute); }
.content-block--code .syn-embed { color: var(--th-syn-embed); }
```

  In `app/assets/tailwind/themes/default/theme.css`, after `@import "./sections.css";`:

```css
@import "./code.css";
```

- [ ] **Step 8: the Lookbook preview,** `test/components/previews/blocks/code_component_preview.rb`:

```ruby
require_relative "../preview_fixtures"

module Blocks
  # `Blocks::CodeComponent` (code block spec §4): a coloured sample with its
  # file name, plain text with no head but the button, and one with a caption
  # and a line long enough to scroll.
  class CodeComponentPreview < ViewComponent::Preview
    def ruby_with_file_name
      render component("language" => "ruby", "filename" => "app/models/greeting.rb", "code" => "# Says hello\nclass Greeting\n  def to_s = \"Hello, \#{@name}\"\nend")
    end

    def plain_text
      render component("code" => "No language: no colours, and a head that holds only the button.")
    end

    def erb_with_caption_and_a_long_line
      render component({ "language" => "erb", "filename" => "app/views/pages/show.html.erb",
        "code" => %(<h1 class="title"><%= translated(@page, :title) %></h1>\n<p>#{"A long line that scrolls. " * 12}</p>) },
        caption: "The page's heading")
    end

    private

    def component(settings, caption: "")
      page = PreviewFixtures.page(title: "Code preview")
      block = page.content_blocks.create!(block_type: :code, position: 0, settings: settings, caption: caption)

      Blocks::CodeComponent.new(block: block, page: page)
    end
  end
end
```

- [ ] **Step 9: run everything this task touches, and the guards it joins.**

  `PGGSSENCMODE=disable bin/rails test test/components/blocks test/components/previews_test.rb test/models/built_in_types_test.rb test/models/content_block_test.rb test/models/publishing_test.rb test/integration/public_blocks_test.rb test/integration/public_canary_test.rb test/integration/published_copy_render_test.rb test/integration/design_tokens_test.rb test/services/translation_state_parity_test.rb test/lib/public_readers_test.rb test/lib/dependency_direction_test.rb test/lib/erb_comments_test.rb test/lib/inline_handlers_test.rb test/integration/open_types_test.rb test/integration/mcp_test.rb`

  Expected: 0 failures, 0 errors. What the guards hold here: the canary overwrites the Code block's `settings` and `caption` on the rows and finds none of it on any public URL until the page is published (the code is read from the copy); `public_readers_test` derives `app/components/blocks/` and finds no line of the new component that reaches rows; `publishing_test`'s `"every column of content_blocks is in exactly one of the copy, the rows and never stored"` passes untouched, because no column was added. If theming is on your base, `Theme::Contract`'s test of the registries is red now, as the Global Constraints say; nothing else may be.

- [ ] **Step 10: look at it, and report the drawing.** `bin/rails tailwindcss:build`, start `bin/dev`, open Lookbook's three previews of `Blocks::CodeComponent` in light and dark and at 360px wide. The spec states the ground (`--th-sunken`), the text (`--th-ink`), the border (`--th-line`), the face (`--th-mono`), the scroll and the focusable `pre`. Everything else in Step 7 is a first drawing: the spacing, the head's alignment and its `dim` text, the language in small capitals, the button as accent-coloured text at the right, the caption in the Image block's caption style. Report it to the controller with the screenshots, for the design system's owner; change nothing on your own judgement.

- [ ] **Step 11: commit.**

```bash
bin/rubocop app/models/block_types app/components/blocks config/initializers/types.rb test/components test/integration test/models test/services
git add app/models/block_types/code.rb app/models/content_block.rb app/components/blocks/code_component.rb app/components/blocks/code_component.html.erb config/initializers/types.rb config/locales/public.en.yml app/assets/tailwind/themes/default/code.css app/assets/tailwind/themes/default/theme.css test/components/blocks/code_component_test.rb test/components/previews/blocks/code_component_preview.rb test/models/built_in_types_test.rb test/models/content_block_test.rb test/integration/public_blocks_test.rb test/integration/public_canary_test.rb test/integration/design_tokens_test.rb test/services/translation_state_parity_test.rb
git commit -m "feat: the Code block — a block type whose source is coloured on the server and reaches the page only as text"
```

---

### Task 4: the Copy button

**Files:** Create `app/javascript/controllers/code_copy_controller.js`, `test/system/code_block_test.rb`. Modify `test/integration/public_javascript_test.rb`.

**Interfaces — consumes:** the markup of `Blocks::CodeComponent` (Task 3): the identifier `code-copy` on the figure, the targets `button`, `source`, `status`, the action `code-copy#copy`, the values `copied` and `failed`.

**Interfaces — produces:** the Stimulus controller `code-copy`. Values: `copied` (String), `failed` (String), `restore` (Number, milliseconds, default 2000: how long the answer stays; a test shortens it through `data-code-copy-restore-value`). Targets: `button`, `source`; `status` is optional.

- [ ] **Step 1: write the failing tests.** In `test/integration/public_javascript_test.rb`:

```ruby
  # Code block spec §4: the copy button is a controller of the site's own,
  # at the top level of `controllers/` like `theme`, so a public page loads
  # it and still nothing of CS Studio.
  test "a public page with a Code block carries the copy controller and no admin script" do
    page = create_page(title: "Docs")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "code", settings: { "code" => "a = 1" } }).ok?
    publish_changes(page)

    get PublicSite::Urls.new.path_for(page, "en")

    assert_response :success
    assert_select "figure[data-controller='code-copy'] button[hidden][data-action='code-copy#copy']"
    assert modulepreloads.any? { |href| href.include?("controllers/code_copy_controller") }, "the copy controller is preloaded with the site's own"
    ADMIN_ONLY.each do |name|
      assert modulepreloads.none? { |href| href.include?(name) }, "#{name} is modulepreloaded on a page with a Code block"
    end
    assert_select "[data-controller*='admin--']", count: 0
  end
```

  `test/system/code_block_test.rb`:

```ruby
require "application_system_test_case"

# The Code block on the public site, in a browser (code block spec §4): the
# Copy button, and a long line.
#
# The clipboard is the browser's and a headless one may refuse it, so each
# test puts its own in place of `navigator.clipboard`: one that records what
# it was handed, none at all, or one that refuses. The script asks for the
# clipboard when it connects, so after changing it a test takes the
# controller off the figure and puts it back (`reconnect`), which is also
# how a disconnect is seen.
class CodeBlockSystemTest < ApplicationSystemTestCase
  CODE = "def greet(name)\n  puts \"Hello, \#{name}\"\nend".freeze
  FIGURE = "figure.content-block--code".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Docs")
  end

  def add_code(code, **attributes)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "code", settings: { "language" => "ruby", "code" => code } }.merge(attributes))
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def open_page
    publish_changes(@page)
    visit PublicSite::Urls.new.path_for(@page, "en")
    await_connected
  end

  def await_connected
    await_js("window.Stimulus && Array.from(document.querySelectorAll('#{FIGURE}')).every((figure) => window.Stimulus.getControllerForElementAndIdentifier(figure, 'code-copy'))")
  end

  def disconnect
    page.execute_script("document.querySelector('#{FIGURE}').removeAttribute('data-controller')")
    await_js("!window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('#{FIGURE}'), 'code-copy')")
  end

  def reconnect
    disconnect
    page.execute_script("document.querySelector('#{FIGURE}').setAttribute('data-controller', 'code-copy')")
    await_connected
  end

  def clipboard(script) = page.execute_script("Object.defineProperty(navigator, 'clipboard', { configurable: true, value: #{script} })")

  def restore_after(milliseconds) = page.execute_script("document.querySelector('#{FIGURE}').setAttribute('data-code-copy-restore-value', '#{milliseconds}')")

  test "the button is shown where there is a clipboard; a press copies the code exactly as stored and says Copied, and the words go back" do
    add_code(CODE, settings: { "language" => "ruby", "filename" => "greet.rb", "code" => CODE })
    open_page
    clipboard("{ writeText: (text) => { window.__copied = text; return Promise.resolve() } }")
    reconnect
    restore_after(60_000)

    button = find("#{FIGURE} button", text: "Copy")
    button.click

    assert_selector "#{FIGURE} button", exact_text: "Copied"
    assert_selector "#{FIGURE} [role=status]", exact_text: "Copied", visible: :all
    assert_equal CODE, page.evaluate_script("window.__copied"), "what is copied is the stored code: no markup, the indentation and the line breaks as typed"

    restore_after(50)
    find("#{FIGURE} button").click
    assert_selector "#{FIGURE} button", exact_text: "Copy"
    assert_equal "", page.evaluate_script("document.querySelector('#{FIGURE} [role=status]').textContent")

    # What the script wrote into the page is taken back when it disconnects
    # (Turbo's snapshot would keep it): the button's own word, an empty
    # status, and the button hidden as the server drew it.
    restore_after(60_000)
    find("#{FIGURE} button").click
    assert_selector "#{FIGURE} button", exact_text: "Copied"
    disconnect
    assert_selector "#{FIGURE} button[hidden]", exact_text: "Copy", visible: :all
    assert_equal "", page.evaluate_script("document.querySelector('#{FIGURE} [role=status]').textContent")
  end

  test "without a clipboard the button stays hidden, and a browser that refuses is told Not copied" do
    add_code(CODE)
    open_page
    clipboard("undefined")
    reconnect

    assert_selector "#{FIGURE} button[hidden]", visible: :all
    assert_selector "#{FIGURE} pre", text: "def greet(name)"

    clipboard("{ writeText: () => Promise.reject(new DOMException('refused', 'NotAllowedError')) }")
    reconnect
    restore_after(60_000)
    find("#{FIGURE} button", text: "Copy").click

    assert_selector "#{FIGURE} button", exact_text: "Not copied"
    assert_selector "#{FIGURE} [role=status]", exact_text: "Not copied", visible: :all
  end

  test "a long line scrolls inside the block and the page never scrolls sideways, at full width and in a column" do
    long = %(x = "#{"a" * 300}")
    section = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "section", settings: { "layout" => "two" } }).record
    add_code(long)
    add_code(long, section_id: section.id, section_column: 2)
    open_page

    assert_selector "#{FIGURE} pre[tabindex='0']", count: 2
    assert page.evaluate_script("Array.from(document.querySelectorAll('#{FIGURE} pre')).every((pre) => pre.scrollWidth > pre.clientWidth)"), "each block scrolls its own long line"
    assert page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth"), "the page does not scroll sideways"
    assert_equal "auto", page.evaluate_script("getComputedStyle(document.querySelector('#{FIGURE} pre')).overflowX")
  end
end
```

- [ ] **Step 2: run them to see them fail.** `bin/rails tailwindcss:build`, then `PGGSSENCMODE=disable bin/rails test test/integration/public_javascript_test.rb test/system/code_block_test.rb`. Expected: the integration test fails on `"the copy controller is preloaded with the site's own"`; the two button tests fail in `await_connected` (`timed out waiting for: window.Stimulus && …`); the long-line test fails there too.

- [ ] **Step 3: implement,** `app/javascript/controllers/code_copy_controller.js`:

  > **Superseded (2026-10-12, as built).** The controller below was not shipped as written: its `disconnect` reads `this.buttonTarget`, and a controller taken off its element finds no target any more, so it raised "Missing target element" in this plan's own tests. The built file keeps the button, the strip and the status line as fields at `connect`, takes its words back at `turbo:before-cache` as well, has a `label` value and a `strip` target, and says nothing after a late answer. Read `app/javascript/controllers/code_copy_controller.js` and `docs/reference/content-blocks-and-types.md` ("The copy script"), not this listing; the spec's "As built" lists every departure.

```js
import { Controller } from "@hotwired/stimulus"

// The Code block's Copy button (`Blocks::CodeComponent`, code block spec §4).
// A controller of the site's own, like `theme`: a public page loads it, and a
// theme that replaces the block's template keeps the button by writing the
// same markup (the identifier, the `button`, `source` and `status` targets,
// the `copy` action, the two values).
//
// The button is `hidden` in the markup and shown here only where there is a
// clipboard to write to, so nobody sees a button that does nothing: a page
// without JavaScript, or on plain http away from localhost, has the code
// and no button.
//
// What is copied is the `source` target's text: the code as stored, with no
// markup, its indentation and line breaks as typed.
//
// The words are the server's (`copied` and `failed` values), so this file
// holds no English. `restore` is how long the answer stays, in milliseconds.
//
// Everything this writes into the page is taken back in `disconnect`: Turbo
// keeps a snapshot of the page, and a snapshot taken a second after a press
// would otherwise come back saying "Copied" with nothing copied.
export default class extends Controller {
  static targets = [ "button", "source", "status" ]
  static values = { copied: String, failed: String, restore: { type: Number, default: 2000 } }

  connect() {
    this.label = this.buttonTarget.textContent
    this.buttonTarget.hidden = !navigator.clipboard?.writeText
  }

  disconnect() {
    this.reset()
    this.buttonTarget.hidden = true
  }

  async copy() {
    let answer = this.copiedValue
    try {
      await navigator.clipboard.writeText(this.sourceTarget.textContent)
    } catch (error) {
      answer = this.failedValue
    }
    this.say(answer)
  }

  // The button shows the answer and the status line says it to a screen
  // reader (the button's accessible name stays "Copy code").
  say(answer) {
    clearTimeout(this.timer)
    this.buttonTarget.textContent = answer
    if (this.hasStatusTarget) this.statusTarget.textContent = answer
    this.timer = setTimeout(() => this.reset(), this.restoreValue)
  }

  reset() {
    clearTimeout(this.timer)
    this.buttonTarget.textContent = this.label
    if (this.hasStatusTarget) this.statusTarget.textContent = ""
  }
}
```

- [ ] **Step 4: run them to see them pass.** The command of Step 2 (no rebuild needed: the script is not a stylesheet). Expected: 0 failures, 0 errors, and no JavaScript error reported by the teardown.

- [ ] **Step 5: the guards.** `PGGSSENCMODE=disable bin/rails test test/lib/source_layout_test.rb test/lib/tailwind_sources_test.rb test/lib/admin_design_rules_test.rb test/lib/inline_handlers_test.rb test/lib/system_test_sleeps_test.rb test/lib/system_test_shards_test.rb`. Expected: all pass (the script writes no class name and no colour; the new system file holds no sleep and is in exactly one shard). Then `bin/importmap audit`: no vulnerable packages (no pin was added: `pin_all_from "app/javascript/controllers"` already covers the file).

- [ ] **Step 6: design report.** The spec fixes the words, the two seconds and the hidden-until-usable button. It does not say whether the button's own label changes or only the status line: this plan changes both (the button reads "Copied"). Report that to the controller for the design system's owner with a recording or two screenshots.

- [ ] **Step 7: commit.**

```bash
git add app/javascript/controllers/code_copy_controller.js test/system/code_block_test.rb test/integration/public_javascript_test.rb
git commit -m "feat: the Code block's Copy button — shown where there is a clipboard, and what it says it takes back"
```

---

### Task 5: the Code block in the editor

The generic block card already draws the type (Tasks 2 and 3). This task takes the Image block's library wording off a caption that has no library text behind it, gives the block its line on a section's tile, and proves the card in the editor: saved as typed, refused over the limit with the text kept, read-only when someone else holds it.

**Files:** Modify `app/components/admin/editor_screen/block_card_component.rb`, `block_card_component.html.erb`, `app/components/admin/editor_screen/tile_summary_component.rb`, `config/locales/admin/editor_screen.en.yml`, `test/components/admin/editor_screen/block_card_component_test.rb`, `tile_summary_component_test.rb`, `held_fields_test.rb`, `test/integration/admin/content_blocks_test.rb`. Create `test/system/admin/code_block_test.rb`.

**Interfaces — consumes:** the type `code` and its capability `:code` (Task 3); `Admin::Fields::CodeField`'s markup, `textarea#block-<id>-code` and `p#block-<id>-code-count` (Task 2); `::CodeHighlight.label(language)` (Task 1); `SharedFieldsComponent.display` for `:select` and `:code` (Task 2).

**Interfaces — produces:**

```ruby
Admin::EditorScreen::BlockCardComponent#caption_options
  # { placeholder: <the library image's caption>, override: "caption" } for a type that uses "image"; {} otherwise
# I18n: admin.components.editor_screen.tile_summary.no_code ("No code yet")
```

- [ ] **Step 1: write the failing component tests.** In `test/components/admin/editor_screen/block_card_component_test.rb`:

```ruby
  def code_block(page, **settings)
    page.content_blocks.create!(block_type: "code", position: 0, caption: "A sample",
      settings: { "language" => "ruby", "filename" => "a.rb", "code" => "    a = 1" }.merge(settings.stringify_keys))
  end

  test "a code block's card: language, file name and code stacked in that order, then a caption that overrides nothing" do
    page = create_page(title: "Code card")
    block = code_block(page)
    prefix = Admin::EditorScreen::BlockCardComponent.error_prefix(block)

    render_card(block, page: page)

    assert_text "Code"
    assert_equal %w[language filename code caption], Capybara.string(rendered_content).all("form .admin-field, form .admin-column").map { |node| node["data-field-name"] }
    assert_selector "select##{prefix}-language[name='block[settings][language]'] option[value='ruby'][selected]", text: "Ruby"
    assert_selector "select##{prefix}-language option[value='']", text: "Plain text"
    assert_selector "select##{prefix}-language option", count: 21
    assert_selector "input##{prefix}-filename[name='block[settings][filename]'][value='a.rb']"
    assert_selector "textarea##{prefix}-code[name='block[settings][code]']"
    assert_equal "    a = 1", Nokogiri::HTML5.fragment(rendered_content).at_css("textarea##{prefix}-code").text
    assert_selector "##{prefix}-code-errors", visible: :all
    assert_no_selector ".admin-block-settings-row"

    assert_selector "input##{prefix}-caption[name='block[caption]'][value='A sample']"
    assert_no_selector "input##{prefix}-caption[placeholder]"
    assert_no_selector "[data-controller='admin--ui--override-field']"
    assert_no_text "from Media"
    assert_no_text "Reset"
  end

  test "an image block's card is as it was: its caption and alt are overrides of the library's text, with an image and without one" do
    page = create_page(title: "Image pin")
    asset = create_media_asset
    asset.update!(alt: "A dog", caption: "Our dog")
    with_image = page.content_blocks.create!(block_type: "image", position: 0, media_asset: asset, caption: "Mine")
    without_image = page.content_blocks.create!(block_type: "image", position: 1)

    [ with_image, without_image ].each do |block|
      prefix = Admin::EditorScreen::BlockCardComponent.error_prefix(block)
      render_card(block, page: page)

      assert_selector "[data-controller='admin--ui--override-field']", count: 2
      assert_selector "[data-admin--ui--override-field-input-id-value='#{prefix}-caption']"
      assert_selector "[data-admin--ui--override-field-input-id-value='#{prefix}-alt']"
      assert_text "Empty uses the caption from Media"
      assert_text "Empty uses the alt text from Media"
    end

    prefix = Admin::EditorScreen::BlockCardComponent.error_prefix(with_image)
    render_card(with_image, page: page)
    assert_selector "input##{prefix}-caption[name='block[caption]'][placeholder='Our dog'][value='Mine']"
    assert_selector "input##{prefix}-alt[name='block[alt]'][placeholder='A dog']"
    assert_selector "[data-admin--ui--override-field-input-id-value='#{prefix}-caption'] button", text: "Reset"
  end

  test "on a translation tab a code block's three settings are shared fields, read-only, and only the caption is edited" do
    with_locales(%w[en de], default: "en") do
      page = create_page(title: "Code tab")
      block = code_block(page)

      render_inline Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "de")

      assert_selector "details[data-shared-fields] summary", text: "Shared fields (3)"
      assert_equal %w[Language Filename Code], Capybara.string(rendered_content).all("details[data-shared-fields] dt", visible: :all).map { |node| node.text(:all) }
      assert_selector "details[data-shared-fields] dd", text: "Ruby", visible: :all
      assert_selector "details[data-shared-fields] dd", text: "a.rb", visible: :all
      assert_equal "    a = 1", Nokogiri::HTML5.fragment(rendered_content).at_css("details[data-shared-fields] dd pre").text
      assert_no_selector "[name='block[settings][code]'], [name='block[settings][language]'], [name='block[settings][filename]']", visible: :all
      assert_selector "input[name='block[caption]']"
      assert_no_selector "[data-controller='admin--ui--override-field']"
    end
  end
```

  In `test/components/admin/editor_screen/tile_summary_component_test.rb`:

```ruby
  test "a code block is its file name, else its language, else its first line, else says there is no code, and needs no attention" do
    render_summary block("code", settings: { "language" => "yaml", "filename" => "config/deploy.yml", "code" => "service: site" })
    assert_equal "config/deploy.yml", page.find(line).text

    render_summary block("code", settings: { "language" => "yaml", "code" => "service: site" })
    assert_equal "YAML", page.find(line).text

    render_summary block("code", settings: { "code" => "    first line\nsecond line" })
    assert_equal "first line", page.find(line).text

    render_summary block("code", settings: { "code" => "x" * 200 })
    assert_equal 80, page.find(line).text.length

    render_summary block("code")
    assert_equal "No code yet", page.find(line).text
    assert_no_selector attention
    assert_no_selector "img"
  end
```

  In `test/components/admin/editor_screen/held_fields_test.rb`:

```ruby
  test "a code block's card, rewritten; held by someone else its code is read-only with its indentation, its select disabled, and no save is wired" do
    page = create_page(title: "Held code")
    block = page.content_blocks.create!(block_type: "code", position: 0, settings: { "language" => "ruby", "filename" => "a.rb", "code" => "    indented\n\tb" })
    as_owner { render_inline Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en", editable: true) }
    assert_survives(rendered_content)

    reserve(block, page, users(:two), "tab-bbbbbbbb")
    as_viewer(users(:one), tab: "tab-aaaaaaaa") { render_inline Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en") }

    assert_selector "fieldset.admin-held textarea[name='block[settings][code]'][readonly]"
    assert_equal "    indented\n\tb", Nokogiri::HTML5.fragment(rendered_content).at_css("textarea[name='block[settings][code]']").text
    assert_selector "fieldset.admin-held select[name='block[settings][language]'][disabled]"
    assert_selector "fieldset.admin-held input[name='block[settings][filename]'][readonly]"
    assert_no_selector "[data-controller~='admin--saving--autosave']"
    left = Nokogiri::HTML5.fragment(rendered_content).css("fieldset.admin-held [data-action]").flat_map { |node| node["data-action"].split }
    assert_empty left - [ "input->admin--editor--code-limit#update" ], "only the counter, which reads, is left in a held code card"
  end
```

- [ ] **Step 2: run them to see them fail.** `PGGSSENCMODE=disable bin/rails test test/components/admin/editor_screen/block_card_component_test.rb test/components/admin/editor_screen/tile_summary_component_test.rb test/components/admin/editor_screen/held_fields_test.rb`. Expected: the code card test fails on `assert_no_selector "[data-controller='admin--ui--override-field']"` (the caption still carries the library wording); the translation-tab test fails on the same line; the tile test fails on the first `assert_equal` (a code block has no line yet: `""`). The Image pin test and the held test pass already: they hold what must not change.

- [ ] **Step 3: implement.** In `app/components/admin/editor_screen/block_card_component.rb`, after `#column_placeholder`:

```ruby
      # A caption is a per-use override of a library text only where the type
      # also uses an image: then the library image's caption is the input's
      # placeholder and the field gets the help line, Reset and the library's
      # text (`admin/shared/_override_field`). A type with a caption and no
      # image (the Code block) has no library text behind it, so its caption
      # is a plain translated field.
      def caption_options = uses_columns.include?("image") ? { placeholder: column_placeholder("caption"), override: "caption" } : {}
```

  In `block_card_component.html.erb`, in the `when "caption"` branch, replace the line `placeholder: column_placeholder("caption"), override: "caption", **translation("caption")` with:

```erb
                  **caption_options, **translation("caption")
```

  In `app/components/admin/editor_screen/tile_summary_component.rb`, add the code branch to `#content` before the `lists_posts` one, and the method under `#listing`. Add to the class comment's list of lines "a code block's file name".

```ruby
      def content
        if definition.nil? then t(".unavailable", type: block.block_type)
        elsif uses?("image") then asset ? asset.file.filename.to_s : t(".no_image")
        elsif uses?("body") then block.body_document(locale: locale).plain_paragraphs.first.to_s.truncate(LENGTH).presence || t(".empty_text")
        elsif definition.capability?(:code) then code_line
        elsif definition.capability?(:lists_posts) then listing
        end
      end
```

```ruby
      # What tells one code block from another at a glance: its file name,
      # else its language as an editor reads it, else the start of its first
      # line. An empty one says so and is not marked: an empty block is the
      # state the picker leaves it in.
      def code_line
        settings = block.settings_object(locale: locale)

        settings&.filename.presence || ::CodeHighlight.label(settings&.language) ||
          settings&.code.to_s.lines.first.to_s.strip.truncate(LENGTH).presence || t(".no_code")
      end
```

  In `config/locales/admin/editor_screen.en.yml`, under `tile_summary:`, after `empty_text`:

```yaml
          no_code: "No code yet"
```

- [ ] **Step 4: run them to see them pass.** The command of Step 2. Expected: 0 failures, 0 errors.

- [ ] **Step 5: write the failing integration tests,** in `test/integration/admin/content_blocks_test.rb`:

```ruby
  # --- the Code block (code block spec §1, §3) ---

  def code_block(**attributes) = @page.content_blocks.create!(block_type: "code", position: 0, **attributes)

  def save_code(block, settings, base: block.reload.updated_at.iso8601(6), tab: nil, **more)
    patch "#{blocks_path}/#{block.id}", params: { block: { settings: settings, **more }, base_updated_at: base }, as: :turbo_stream,
      headers: { "X-Notes-Tab" => tab }.compact
  end

  test "adding a Code block streams its card with the code field, and its code is saved as typed" do
    post blocks_path, params: { block: { block_type: "code" } }, as: :turbo_stream
    assert_response :success
    block = @page.content_blocks.last
    assert_equal "code", block.block_type
    assert_select "turbo-stream template textarea[name='block[settings][code]']"

    save_code(block, { language: "ruby", filename: "a.rb", code: "\r\n    def a\r\n\tb\r\n    end\r\n\r\n" }, caption: "A sample")

    assert_response :success
    assert_equal({ "language" => "ruby", "filename" => "a.rb", "code" => "    def a\n\tb\n    end" }, block.reload.settings)
    assert_equal "A sample", block.caption
  end

  test "a Code block over the limit is refused with the message in its slot, nothing is written, and the answer does not touch the field" do
    block = code_block(settings: { "code" => "kept = 1" })
    stamp = block.reload.updated_at

    save_code(block, { code: "x" * 20_001 })

    assert_response :unprocessable_entity
    assert_select "turbo-stream[target='block-#{block.id}-code-errors'] template", text: /Code is too long \(maximum is 20000 characters\)/
    assert_no_match(/<textarea/, response.body, "the field, and the text in it, is the browser's to keep")
    assert_equal "kept = 1", block.reload.settings["code"]
    assert_equal stamp, block.updated_at

    save_code(block, { code: "x" * 20_000 })
    assert_response :success
    assert_equal 20_000, block.reload.settings["code"].length
  end

  test "a Code block's language is one of the list or none, and a save of the code alone leaves it" do
    block = code_block(settings: { "language" => "ruby", "code" => "a = 1" })

    save_code(block, { language: "cobol" })
    assert_response :unprocessable_entity
    assert_select "turbo-stream[target='block-#{block.id}-language-errors'] template", text: /Language is not included in the list/
    assert_equal "ruby", block.reload.settings["language"]

    save_code(block, { code: "a = 2" })
    assert_response :success
    assert_equal({ "language" => "ruby", "code" => "a = 2" }, block.reload.settings)

    save_code(block, { language: "" })
    assert_response :success
    assert_equal({ "code" => "a = 2" }, block.reload.settings)
  end

  test "a Code block in a column says its file name on its tile, is duplicated with its code and caption, and is deleted" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    inside = @page.content_blocks.create!(block_type: "code", section: section, section_column: 1, position: 0)

    save_code(inside, { filename: "config/deploy.yml", code: "service: site" })
    assert_response :success
    assert_select "turbo-stream[action=replace][target='block-#{inside.id}-tile-summary'] template", text: %r{config/deploy\.yml}

    top = @page.content_blocks.create!(block_type: "code", position: 1, caption: "Cap", settings: { "language" => "yaml", "code" => "  a: 1\n  b: 2" })
    post "#{blocks_path}/#{top.id}/duplicate", as: :turbo_stream
    assert_response :success
    copy = (@page.content_blocks.reload.to_a - [ section, inside, top ]).sole
    assert_equal "code", copy.block_type
    assert_equal top.settings, copy.settings
    assert_equal "Cap", copy.caption

    delete "#{blocks_path}/#{copy.id}", as: :turbo_stream
    assert_response :success
    assert_not ContentBlock.exists?(copy.id)
  end

  test "a Code block's save is refused when it is stale and when another tab holds it, like any block's" do
    block = code_block(settings: { "code" => "zero" })
    base = block.updated_at.iso8601(6)

    save_code(block, { code: "one" }, base: base, tab: "tab-aaaaaaaa")
    assert_response :success
    travel 1.minute do
      save_code(block, { code: "two" }, base: base, tab: "tab-aaaaaaaa")
    end
    assert_response :conflict
    assert_equal "one", block.reload.settings["code"]

    sign_in_as users(:two)
    save_code(block, { code: "theirs" }, tab: "tab-bbbbbbbb")
    assert_response :conflict
    assert_equal "one", block.reload.settings["code"]
  end

  test "the editor draws a Code block's card on the default tab and its shared fields on a translation tab" do
    block = code_block(settings: { "language" => "ruby", "code" => "a = 1" })

    get "/cs-studio/pages/#{@page.id}"
    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(block)} textarea#block-#{block.id}-code", text: /a = 1/

    get "/cs-studio/pages/#{@page.id}", params: { locale: "de" }
    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(block)} textarea", count: 0
    assert_select "##{ActionView::RecordIdentifier.dom_id(block)} details[data-shared-fields] dd pre", text: /a = 1/
  end
```

- [ ] **Step 6: run them.** `PGGSSENCMODE=disable bin/rails test test/integration/admin/content_blocks_test.rb`. Expected: every one passes, because Tasks 2, 3 and this task's Step 3 built what they ask (the tile's file name is Step 3's). They are written here because this is where the editor's behaviour is proved end to end; a failure names what an earlier task got wrong, and is fixed there.

- [ ] **Step 7: write the browser test,** `test/system/admin/code_block_test.rb`:

```ruby
require "application_system_test_case"

# The Code block's card in the page editor, in a browser (code block spec
# §3): typed into and saved by itself with its white space as typed, refused
# over the limit with the text left in the field, and read-only for a second
# person while the first holds it.
class Admin::CodeBlockSystemTest < ApplicationSystemTestCase
  TYPED = "    indented first\n  second".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    users(:one).update!(name: "Olga Braun")
    @page = create_page(title: "Docs", published: false)
    sign_in_via_form(users(:one))
  end

  def open_editor
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    await_notes_live
  end

  def code_id(block) = "block-#{block.id}-code"

  def code_field(block) = find("##{code_id(block)}")

  # Puts `count` characters into the field as a paste would, in one event.
  def paste(block, count)
    page.execute_script("const field = document.getElementById(arguments[0]); field.value = 'x'.repeat(arguments[1]); field.dispatchEvent(new Event('input', { bubbles: true }))", code_id(block), count)
  end

  test "a Code block added from the picker is typed into, saved by itself, and keeps its indentation after a reload; Tab leaves the field" do
    open_editor
    # Scoped to the picker: the rich-text toolbar has a "Code block" button, and a label is matched as a part.
    within("#block-picker-end") { press "Code" }
    assert_selector ".admin-block-card textarea[name='block[settings][code]']"
    block = @page.content_blocks.sole
    await_admin_controllers

    code_field(block).set(TYPED)
    select "Ruby", from: "block-#{block.id}-language"
    assert_writes_settled
    assert_equal({ "language" => "ruby", "code" => TYPED }, block.reload.settings)

    code_field(block).send_keys(:tab)
    assert_not_equal code_id(block), page.evaluate_script("document.activeElement.id"), "Tab moves on, as in every textarea"
    assert_equal TYPED, code_field(block).value, "and puts nothing into the code"

    open_editor
    assert_equal TYPED, code_field(block).value
    assert_equal "ruby", find("#block-#{block.id}-language").value
    assert_selector "##{code_id(block)}-count", visible: :hidden
  end

  test "from 18,000 characters the field counts; over 20,000 the save is refused, the text stays and nothing is stored" do
    block = @page.content_blocks.create!(block_type: "code", position: 0, settings: { "code" => "kept = 1" })
    open_editor
    assert_selector "##{code_id(block)}-count", visible: :hidden

    paste(block, 18_412)
    assert_selector "##{code_id(block)}-count", text: "18,412 of 20,000"
    assert_writes_settled
    assert_equal 18_412, block.reload.settings["code"].length

    paste(block, 20_001)
    assert_selector "##{code_id(block)}-errors", text: "Code is too long (maximum is 20000 characters)"
    assert_selector "##{code_id(block)}-count.text-warn-ink", text: "20,001 of 20,000"
    assert_equal 20_001, page.evaluate_script("document.getElementById('#{code_id(block)}').value.length"), "the refused text is still in the field"
    assert_equal 18_412, block.reload.settings["code"].length, "and nothing was written"
  end

  test "while one person types in the code, a second person's card is read-only with the same text" do
    block = @page.content_blocks.create!(block_type: "code", position: 0, settings: { "language" => "ruby", "code" => "as written" })
    open_editor
    code_field(block).set(TYPED)
    assert_writes_settled
    assert_equal TYPED, block.reload.settings["code"]

    using_session(:dana) do
      sign_in_via_form(users(:two))
      open_editor

      assert_selector "#content_block_#{block.id}[data-editing-held=true] [data-editing-kind=held]", text: "Olga Braun is editing this block"
      assert_selector "##{code_id(block)}[readonly]"
      assert_equal TYPED, code_field(block).value
      assert_selector "#block-#{block.id}-language[disabled]"
      assert_no_selector "#content_block_#{block.id} form[data-controller~='admin--saving--autosave']"

      code_field(block).send_keys("ZZZ")
      await_frames
      assert_equal TYPED, code_field(block).value
    end
    assert_equal TYPED, block.reload.settings["code"]
  end
end
```

- [ ] **Step 8: run it.** `bin/rails tailwindcss:build`, check `sysctl -n vm.loadavg`, then `PGGSSENCMODE=disable bin/rails test test/system/admin/code_block_test.rb`. Expected: 3 runs, 0 failures, 0 errors, no JavaScript error. This is the first run of `admin--editor--code-limit` in a browser: a failure in the second test's counter lines is Task 2's script, fixed there.

- [ ] **Step 9: the guards.** `PGGSSENCMODE=disable bin/rails test test/components/admin test/lib/admin_i18n_test.rb test/lib/source_layout_test.rb test/lib/script_messages_test.rb test/lib/notes_boundary_test.rb test/lib/editing_guards_test.rb test/lib/system_test_sleeps_test.rb test/lib/system_test_shards_test.rb test/integration/admin/editing_test.rb test/integration/admin/editing_claims_test.rb`. Expected: all pass (the tile's new word is a key; the card names no feature it did not name; every unit and its ancestors still have ids).

- [ ] **Step 10: look at it, and report.** In `bin/dev`, add a Code block to a page and to a column of a section; paste a long sample; open the German tab; open the page in a second browser as another user while the first is typing. Report to the controller, for the design system's owner, with screenshots in light and dark: the card as a whole (three stacked fields and a caption), the label "Filename" (the spec's prose says "File name"; see "Where the plan departs" 1), the tile's line, the shared fields with the scrolling `pre`, and the held card. Change nothing on your own judgement.

- [ ] **Step 11: commit.**

```bash
bin/rubocop app/components/admin/editor_screen test/components/admin/editor_screen test/integration/admin/content_blocks_test.rb test/system/admin/code_block_test.rb
git add app/components/admin/editor_screen/block_card_component.rb app/components/admin/editor_screen/block_card_component.html.erb app/components/admin/editor_screen/tile_summary_component.rb config/locales/admin/editor_screen.en.yml test/components/admin/editor_screen/block_card_component_test.rb test/components/admin/editor_screen/tile_summary_component_test.rb test/components/admin/editor_screen/held_fields_test.rb test/integration/admin/content_blocks_test.rb test/system/admin/code_block_test.rb
git commit -m "feat: the Code block in the editor — a caption that overrides nothing, its line on a tile, and the card proved in a browser"
```

---

### Task 6: the theming contract — seven syntax tokens and the block's template

**This task assumes theming is merged; before starting, read `docs/reference/theming.md` and `app/values/theme/contract.rb` and adapt the names below to what was built.** The names here are the theming spec's (`docs/superpowers/specs/2026-10-12-theming-design.md`: `Theme::Contract::TOKENS` and `COMPONENTS`, `Theme.with(theme) { }`, the fixture theme `test/fixtures/themes/plain`, the reference file checked against the contract by a test). Where the code that was built says it differently (a constant's shape, a test file's name, how a test hands a folder in), the built code wins and the intent of each step stays. If theming is NOT merged, stop and tell the controller: nothing in this task can be built on `main` alone except Steps 1 to 4, and those would turn theming's own token test red the day it lands.

**Files:** Modify `app/assets/tailwind/themes/default/tokens.css`, `app/assets/tailwind/themes/default/sections.css`, `test/integration/design_tokens_test.rb`, `app/values/theme/contract.rb`, `docs/reference/theming.md`, the contract's own test file and the theme's integration test file (read their names off the theming pull request). Create `test/fixtures/themes/code/components/blocks/code_component.html.erb`.

**Interfaces — consumes:** `CodeHighlight::ROLES` (Task 1); `Blocks::CodeComponent` and the methods its template may call (Task 3); the classes `syn-<role>` and the declarations `color: var(--th-syn-<role>)` of `code.css` (Task 3); the copy script's markup (Task 4).

**Interfaces — produces:** the seven tokens `--th-syn-comment`, `--th-syn-keyword`, `--th-syn-string`, `--th-syn-constant`, `--th-syn-tag`, `--th-syn-attribute`, `--th-syn-embed`, each with a light and a dark value, and two entries of the contract: those seven names among its tokens, and `blocks/code_component` among its replaceable components with `block`, `page`, `lines`, `code`, `language`, `language_label`, `filename`, `caption`.

- [ ] **Step 1: write the failing token tests,** in `test/integration/design_tokens_test.rb` (the helpers `theme_tokens`, `resolve_colour` and `contrast` are that file's own; `mix` is new and goes with them under `private`):

```ruby
  # Code block spec §5: one token per role the highlighter names, each with
  # its dark value.
  SYNTAX_TOKENS = %w[comment keyword string constant tag attribute embed].map { |role| "--th-syn-#{role}" }.freeze

  test "the seven syntax tokens are the highlighter's seven roles, and each has a light and a dark value" do
    assert_equal CodeHighlight::ROLES.map { |role| "--th-syn-#{role}" }, SYNTAX_TOKENS
    theme_tokens.each do |theme, tokens|
      SYNTAX_TOKENS.each { |token| assert tokens.key?(token), "#{token} missing from the #{theme} theme" }
    end
  end

  # WCAG 1.4.3 for code: every role on both grounds a code block stands on
  # (`--th-sunken`, and `--th-surface`, which a tinted band puts behind it),
  # in both themes. 28 pairs; the lowest is the comment on sunken, 5.7:1
  # light and 5.5:1 dark.
  test "every syntax colour is readable on both grounds a code block has, in both themes" do
    pairs = 0
    theme_tokens.each do |theme, tokens|
      %w[--th-sunken --th-surface].each do |ground|
        SYNTAX_TOKENS.each do |token|
          ratio = contrast(resolve_colour(tokens, ground), resolve_colour(tokens, token))
          assert_operator ratio, :>=, 4.5, "#{token} on #{ground} (#{theme}) is #{ratio.round(2)}:1"
          pairs += 1
        end
      end
    end
    assert_equal 28, pairs
  end

  # Spec decision 8 (confirmed by the owner): on a strong band the code is
  # one colour. The band re-values the seven to its own text colour, the
  # comment to its dim, and its sunken ground is that text colour at 12%.
  test "on a strong band the code is one colour: the seven are the band's text colour, the comment its dim, both readable on the band's sunken ground" do
    strong = Rails.root.join("app/assets/tailwind/themes/default/sections.css").read[/\.content-section--strong\s*\{(.*?)\}/m, 1]
    (SYNTAX_TOKENS - %w[--th-syn-comment]).each { |token| assert_match(/#{token}:\s*var\(--th-on-band-strong\);/, strong) }
    assert_match(/--th-syn-comment:\s*var\(--th-on-band-strong-dim\);/, strong)
    assert_match(/--th-sunken:\s*color-mix\(in srgb, var\(--th-on-band-strong\) 12%, transparent\);/, strong, "the ground the two colours are measured on below")

    theme_tokens.each do |theme, tokens|
      band, ink, dim = %w[--th-band-strong --th-on-band-strong --th-on-band-strong-dim].map { |name| resolve_colour(tokens, name) }
      ground = mix(ink, band, 0.12)
      assert_operator contrast(ink, ground), :>=, 4.5, "code on a strong band (#{theme}) is #{contrast(ink, ground).round(2)}:1"
      assert_operator contrast(dim, ground), :>=, 4.5, "a comment on a strong band (#{theme}) is #{contrast(dim, ground).round(2)}:1"
    end
  end
```

```ruby
    # `color-mix(in srgb, top <share>, transparent)` painted over `under`:
    # mixed in the encoded values, as a browser does, from and to linear light.
    def mix(top, under, share)
      encode = ->(value) { value <= 0.0031308 ? value * 12.92 : 1.055 * value**(1 / 2.4) - 0.055 }
      decode = ->(value) { value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4 }
      top.zip(under).map { |one, other| decode.(encode.(one) * share + encode.(other) * (1 - share)) }
    end
```

- [ ] **Step 2: run them to see them fail.** `PGGSSENCMODE=disable bin/rails test test/integration/design_tokens_test.rb`. Expected: the first fails with `--th-syn-comment missing from the light theme`; the second errors with `KeyError: key not found: "--th-syn-comment"`; the third fails on its first `assert_match`.

- [ ] **Step 3: the tokens.** In `app/assets/tailwind/themes/default/tokens.css`, at the end of the `:root, [data-theme="light"]` block:

```css
  /* The Code block's seven syntax colours (code block spec §5), one per role
     `CodeHighlight::ROLES` names: `code.css` colours `.syn-<role>` by
     `--th-syn-<role>`. On the sunken ground and on the surface (which a
     tinted band puts behind code) the lowest is the comment, 5.7:1 here and
     5.5:1 in the dark block; `test/integration/design_tokens_test.rb` holds
     all 28 pairs at 4.5:1 or better. */
  --th-syn-comment: oklch(0.47 0.01 270);
  --th-syn-keyword: oklch(0.45 0.12 250);
  --th-syn-string: oklch(0.43 0.10 150);
  --th-syn-constant: oklch(0.46 0.10 65);
  --th-syn-tag: oklch(0.42 0.07 200);
  --th-syn-attribute: oklch(0.44 0.10 300);
  --th-syn-embed: oklch(0.46 0.15 25);
```

  and at the end of the `[data-theme="dark"]` block:

```css
  /* The syntax colours again. */
  --th-syn-comment: oklch(0.68 0.01 270);
  --th-syn-keyword: oklch(0.76 0.10 250);
  --th-syn-string: oklch(0.78 0.11 150);
  --th-syn-constant: oklch(0.80 0.10 75);
  --th-syn-tag: oklch(0.78 0.07 200);
  --th-syn-attribute: oklch(0.76 0.09 300);
  --th-syn-embed: oklch(0.76 0.11 25);
```

- [ ] **Step 4: the strong band.** In `app/assets/tailwind/themes/default/sections.css`, at the end of the `.content-section--strong` rule, after the `--th-surface` line:

```css
  /* Code on this band is one colour (code block spec, decision 8): the band
     turns the page's colours round, and a second set of seven values for it
     would be fourteen more to keep readable. The comment keeps its step back. */
  --th-syn-comment: var(--th-on-band-strong-dim);
  --th-syn-keyword: var(--th-on-band-strong);
  --th-syn-string: var(--th-on-band-strong);
  --th-syn-constant: var(--th-on-band-strong);
  --th-syn-tag: var(--th-on-band-strong);
  --th-syn-attribute: var(--th-on-band-strong);
  --th-syn-embed: var(--th-on-band-strong);
```

  Run the command of Step 2. Expected: 0 failures, 0 errors (the existing `"the sections stylesheet holds no colour of its own"` among them).

- [ ] **Step 5: write the failing contract tests.** In the contract's own test file (the theming spec's "`Theme::Contract`: every component a type registry hands out is on the list; every token is defined in `tokens.css` …"), add, adapting the constants' shapes:

```ruby
  test "the Code block is in the contract: its template is replaceable with its eight methods, and its seven syntax tokens are tokens" do
    assert_equal %i[block page lines code language language_label filename caption], Theme::Contract::COMPONENTS.fetch("blocks/code_component")
    CodeHighlight::ROLES.each { |role| assert_includes Theme::Contract::TOKENS, "--th-syn-#{role}" }
    %i[lines code language language_label filename caption].each do |name|
      assert Blocks::CodeComponent.private_method_defined?(name) || Blocks::CodeComponent.method_defined?(name), "#{name} is promised and not defined"
    end
  end
```

  In the theme's integration test file (where `Theme.with` draws a page under `test/fixtures/themes/plain`), add, building the two themes the way that file builds `plain`:

```ruby
  test "a theme replaces the Code block's template, and a theme that does not is drawn the default one" do
    page = create_page(title: "Docs")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "code", settings: { "language" => "ruby", "filename" => "a.rb", "code" => "a = 1" } }).ok?
    publish_changes(page)
    path = PublicSite::Urls.new.path_for(page, "en")

    Theme.with(theme_at("test/fixtures/themes/code")) { get path }
    assert_response :success
    assert_select "div.plain-code[data-controller='code-copy'] pre[data-code-copy-target='source']", text: "a = 1"
    assert_select "div.plain-code .plain-code__file", text: "a.rb"
    assert_select "figure.content-block--code", count: 0

    Theme.with(theme_at("test/fixtures/themes/plain")) { get path }
    assert_response :success
    assert_select "figure.content-block--code pre span.syn-constant", text: "1"
    assert_select "div.plain-code", count: 0
  end
```

  (`theme_at` stands for however that file turns a folder into a `Theme`; use its helper.) `test/fixtures/themes/plain` is NOT given a Code template: every other test of it is then also a test of the fallback, as the theming spec asks of that fixture.

- [ ] **Step 6: run them to see them fail.** Run the two files. Expected: `KeyError` for `"blocks/code_component"`; the theme test fails because the folder `test/fixtures/themes/code` does not exist. (The registries' test of the contract has been red since Task 3 and is still.)

- [ ] **Step 7: the two entries, the fixture and the reference.** In `app/values/theme/contract.rb`: add the seven names to `TOKENS`, beside the other colour tokens, in the order of `CodeHighlight::ROLES`; and add to `COMPONENTS`, after the Image block's line:

```ruby
    "blocks/code_component" => %i[block page lines code language language_label filename caption],
```

  `test/fixtures/themes/code/components/blocks/code_component.html.erb`, a theme of one file (the `pre` on one line, for the reason the default template's is):

```erb
<div class="plain-code" data-controller="code-copy" data-code-copy-copied-value="Copied" data-code-copy-failed-value="Not copied">
  <% if filename.present? %>
    <p class="plain-code__file"><%= filename %></p>
  <% end %>
  <button type="button" hidden data-code-copy-target="button" data-action="code-copy#copy">Copy</button>
  <pre data-code-copy-target="source"><% lines.each_with_index do |line, index| %><%= "\n" if index.positive? %><% line.each do |_role, text| %><%= text %><% end %><% end %></pre>
</div>
```

  In `docs/reference/theming.md`, in the form its other entries have: the seven tokens with what each colours (the spec's table in §5) and the sentence that a strong band makes them one colour; the component's entry with what the template receives (`block`, `page`; `lines`, one array per line of `[role, text]` pairs with the role nil for plain text and otherwise one of the seven; `code`, the source as stored; `language`, the tag; `language_label`; `filename`; `caption`; each safe for an empty block, and the component draws nothing without code); and the copy script's markup, which a replaced template has to write to keep the button: the identifier `code-copy` on the block's element, the targets `button` (rendered `hidden`), `source` (whose text is what is copied) and the optional `status` (`role="status"`), the action `code-copy#copy`, and the values `data-code-copy-copied-value` and `data-code-copy-failed-value`. Say that a template prints `text` through ERB's own escaping and never marks it safe. If the reference's test compares the file with `Theme::Contract`, it tells you what is still missing.

- [ ] **Step 8: run everything.** `PGGSSENCMODE=disable bin/rails test` (the whole unit suite). Expected: 0 failures, 0 errors, the contract's registries test green again. Then `bin/rails tailwindcss:build`, `sysctl -n vm.loadavg`, and `PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test:system`. Expected: 0 failures. Then `bin/rails theme:check` against the fixture `code` theme if the task takes a path, and `bin/rails theme:new` into a `mktemp -d` directory: the copy holds `components/blocks/code_component.html.erb` (delete the directory by name).

- [ ] **Step 9: look at it, and report.** With the default theme: a Code block in Ruby, ERB and YAML, in light and dark, on the page, in a tinted band and in a strong band. Report the screenshots to the controller for the design system's owner: the seven values are the spec's and are not the implementer's to tune; a colour that reads badly is a question, not a fix.

- [ ] **Step 10: commit.**

```bash
git add app/assets/tailwind/themes/default/tokens.css app/assets/tailwind/themes/default/sections.css app/values/theme/contract.rb docs/reference/theming.md test/integration/design_tokens_test.rb test/fixtures/themes/code
git add -u test
git commit -m "feat: the Code block in the theming contract — seven syntax tokens, one colour on a strong band, a replaceable template"
```

---

### Task 7: documentation

No guide text is written in this repository: the guide lives in `contentspiel-docs` and is written there after this pull request, from the pull request as it was really built. This task writes what this repository keeps and names the guide pages for the pull request.

**Files:** Modify `docs/reference/content-blocks-and-types.md`, `docs/reference/i18n.md`, `CLAUDE.md`, `docs/roadmap.md`, `docs/superpowers/specs/2026-10-12-code-block-design.md`. (`docs/reference/theming.md` was Task 6's, because a test reads it.)

**Interfaces — consumes:** everything Tasks 1 to 6 built, as built. Read the diff of the branch (`git diff main...HEAD --stat`, then the files) before writing a sentence: describe the code that is there, not this plan.

- [ ] **Step 1: `docs/reference/content-blocks-and-types.md`.**
  - To the `> Describes:` line add `app/values/code_highlight.rb`, `app/components/blocks/code_component.rb`, `app/components/admin/fields/code_field.rb`, `app/javascript/controllers/code_copy_controller.js`, `app/javascript/controllers/admin/editor/code_limit_controller.js`, `app/assets/tailwind/themes/default/code.css`.
  - In "Content blocks", the list of types becomes `rich_text` / `image` / `code` / `post_list` / `section`.
  - A new section, "The Code block", after "Blocks in CS Studio", in the file's own density, covering: the type and why its three settings are in `settings` and its caption is the `caption` column (no migration, the copy's column test untouched); the `:code` field type (what is kept, what is normalised, `max:` in characters, never translated and why that keeps it from an AI provider) and `blank:`; `CodeHighlight` (the one file that names Rouge, `require: false`, the role table, plain text for everything it cannot colour, the log line without code, what is cached and under which key, when to bump `REVISION`); the public component and the escaping rule with the tests that hold it; the copy script and what it takes back on disconnect; the card (the caption's override only with an image, the counter and why it is not `admin--ui--char-count`, the shared fields on a translation tab, the tile's line); what a hold does to it; the limits (a slow lexer and the `Regexp.timeout` fix; two ways to show code; the settings' size in each audit snapshot and copy).
  - In "Sections", the sentence that lists what a tile's line is gains "a code block's file name".

- [ ] **Step 2: `docs/reference/i18n.md`.** In "Files": `config/locales/admin/fields.en.yml` (the schema field inputs' folder, as any component folder's) and `config/locales/public.en.yml` (the public site's own strings: read in the visitor's language with English as the fallback, started by the Code block ahead of roadmap item 7, which fills it). One paragraph, "A string of the public site", with `Blocks::CodeComponent#string` as the example and the reason for the explicit fallback (no I18n fallbacks are configured, and the test environment raises on a missing key).

- [ ] **Step 3: `CLAUDE.md`.**
  - "What This Repo Is" stays general (the spec says so).
  - In the reference index, the content-blocks line gains `app/values/code_highlight.rb`, `app/components/blocks/code_component.*`, `app/components/admin/fields/code_field.*` and the two scripts.
  - Under "Rules a change can break silently", add these, each with its guarding test as built (check every test name against the files before writing it):
    - The Code block's source, file name and caption reach a page only as escaped text: nothing in `Blocks::CodeComponent`, its template or `CodeHighlight` marks a string as safe, Rouge's formatters are not used, and a span's class is one of `CodeHighlight::ROLES`, never the stored language (`test/components/blocks/code_component_test.rb`: "source, file name and caption that look like markup are text: one pre, no script, no element the template did not write", "a stored language that is not on the list is plain text and names no language", "nothing in the component, its template or the highlighter marks a string as safe, and only the highlighter names Rouge").
    - `CodeHighlight` is the one file that names Rouge and never fails a page: no language, a language off the list and a lexer that raises are plain text, logged with the block's id and no code; a change of `RULES` bumps `REVISION` (`test/values/code_highlight_test.rb`: "a lexer that raises is plain text, and the log names the block and holds no code", "the coloured lines are cached by the code, the language, Rouge's version and the revision").
    - A `:code` field is stored as typed and is never translated, so never offered to an AI provider; its limit is refused by the server and never cut by a `maxlength` (`test/models/content_model/code_field_test.rb`: "the first line's indentation, tabs and inner blank lines are kept as typed", "a code field is never translated"; `test/components/admin/ui/field_component_test.rb`: "a code field is never offered to the AI translation"; `test/integration/admin/content_blocks_test.rb`: "a Code block over the limit is refused with the message in its slot, nothing is written, and the answer does not touch the field").
    - A block's caption is a library override only for a type that also uses an image (`test/components/admin/editor_screen/block_card_component_test.rb`: "a code block's card: language, file name and code stacked in that order, then a caption that overrides nothing", "an image block's card is as it was: its caption and alt are overrides of the library's text, with an image and without one").
    - What `code-copy` writes into the page it takes back when it disconnects, and the button is shown only where there is a clipboard (`test/system/code_block_test.rb`, both button tests). No static guard.
    - If Task 6 was built: the seven `--th-syn-*` tokens and the Code block's template methods are contract names, changed only with a release note; all 28 colour pairs stay at 4.5:1 (`test/integration/design_tokens_test.rb`: "every syntax colour is readable on both grounds a code block has, in both themes").
  - In "Key Conventions", the sentence on admin strings gains the public file: a string the public site's own templates say is a key in `config/locales/public.en.yml`.
  - Run `PGGSSENCMODE=disable bin/rails test test/lib` afterwards: the layout guard reads `CLAUDE.md` and `docs/reference` for controller identifiers.

- [ ] **Step 4: `docs/roadmap.md`.**
  - "Shipped": a row for the Code block with this spec.
  - "Next", item 2 (the catalogue): "Today: 5 block types (rich text, image, code, post list, section)", and one sentence that the Code block was built ahead of the catalogue for the documentation site.
  - "Next", item 7 (Admin UI in German): add that `config/locales/public.en.yml` exists already, started by the Code block with its four strings ahead of this item; the item moves the public site's other literals into it and adds `public.de.yml` and `public.es.yml`, and until then a German or Spanish visitor reads those four in English.
  - "Known gaps", a new "Code block" group, one line each, with what would close it: the label reads "Filename" (a `label:` option on schema fields); going over the limit is not announced by the counter; no line numbers, highlighted lines or diffs; code inside rich text has no language and is not coloured; a Markdown fence in a post stays rich text; the MCP server has no block tools, so no tool writes a Code block (item 8); a lexer has no time limit beyond the size cap (`Regexp.timeout`); the German and Spanish of the four public strings. Add anything the build found.
  - The documentation site's entry: the Code block is built; its theme renames `--th-syn-attr` to `--th-syn-attribute`, reads `lines`, and drops `docs--copy` for `code-copy` (work in `contentspiel-docs`).

- [ ] **Step 5: the spec's "As built".** In `docs/superpowers/specs/2026-10-12-code-block-design.md`, change the status line to "built (plan `docs/superpowers/plans/2026-10-12-code-block.md`)" and add a last section, "As built", listing where the code left the text: the eight points of "Where the plan departs from the spec's wording" above, each as it finally was, and whatever the build changed beyond them (a design answer from the owner, a name theming chose). Say for each which document now describes the code.

- [ ] **Step 6: the whole check.**

```sh
PGGSSENCMODE=disable bin/rails test
bin/rubocop
bin/brakeman
bin/bundler-audit
bin/importmap audit
bin/rails zeitwerk:check
```

  Expected: 0 failures and 0 errors; no offences; brakeman exits 0 with no new warning and `config/brakeman.ignore` untouched; no vulnerabilities, twice; `All is good!`. The browser suite ran whole in Task 6 and nothing since touched what a browser runs; run it again only if Step 1 to 5 changed more than documents.

- [ ] **Step 7: the pull request's "Documentation" section.** Name these guide pages (in `contentspiel-docs`; written there, after this is merged, from this pull request):
  - **New, integrators: "How to add a block type"**: a walk-through that follows this block as it was really built, commit by commit (the declaration and its fields and where they are stored; the new field type; the component and its template; the editor card; what is translated; the published copy; the tokens; the tests and the guards it joined), so it describes no step nobody took.
  - Editors: `pages/build-a-page-with-blocks` (a fifth block type: its fields, the limit, what is translated), `pages/arrange-blocks-in-sections` (one sentence: it works in a column), `pages/the-rich-text-editor` (when to use which code), `translating` (the code is shared, the caption is not).
  - Integrators: `theming/the-token-contract` (seven tokens), `theming/rendering-blocks-and-pages` and the block and template reference (the component's entry, the `code-copy` markup).

- [ ] **Step 8: commit.**

```bash
git add docs/reference/content-blocks-and-types.md docs/reference/i18n.md CLAUDE.md docs/roadmap.md docs/superpowers/specs/2026-10-12-code-block-design.md
git commit -m "docs: the Code block — the reference, the rules with their tests, the roadmap and the spec as built"
```

---

## Self-review: where each part of the spec is built

| Spec | Task |
|---|---|
| Decision 1, §2 "Rouge colours the code", its own `Gemfile` line, the audit | Task 1 |
| Decision 2, §2 the twenty languages and "Plain text" | Task 1 (`LANGUAGES`), Task 2 (`blank:`), Task 3 (the type) |
| Decision 3, §1 settings and the `caption` column, no migration, nothing required | Task 3 |
| Decision 4, §1 the `:code` field type: kept as typed, line endings, outer blank lines, `max:`, never translated, not in `TRANSLATABLE_TYPES` | Task 2 |
| Decision 5 the Tab key leaves the field | Task 2 (a plain textarea), Task 5 (the browser test) |
| Decision 6 the limit is refused, not cut | Task 2 (the model, no `maxlength`), Task 5 (the request and the browser) |
| Decision 7, §2 the cache holds lines, keyed on digest, language, version and revision | Task 1 |
| Decision 8 one colour on a strong band | Task 6 |
| Decision 9, §4 the copy controller, `code-copy` | Task 4 |
| §1 the published copy, the mark, the publish dialog's count; no column added | Task 3 (the page test, the canary, the column test run) |
| §1 translation state | Task 3 (the parity test) |
| §1 writes are the existing services | Task 3 (the parity and page tests go through them), Task 5 (duplicate, delete, stale, claim) |
| §2 no language, an unlisted tag and a raising lexer are plain; logged once without code | Task 1, Task 3 |
| §3 `Admin::Fields::CodeField`, the counter | Task 2, Task 5 (in a browser) |
| §3 the caption without the override; the Image block unchanged | Task 5 |
| §3 shared fields on a translation tab | Task 2 (`display`), Task 5 (the card and the page) |
| §3 autosave, base, stale check, claim, hold; `HeldFields` | Task 2 (the allow-list), Task 5 |
| §3 the tile's summary | Task 5 |
| §3 strings are keys | Task 2 (`fields.en.yml`), Task 5 (`no_code`) |
| §4 the component, its markup, the head, escaping | Task 3 |
| §4 long lines scroll, the page does not | Task 3 (the stylesheet), Task 4 (the browser test) |
| §4 the public strings and their fallback | Task 3 |
| §4 the styles | Task 3 |
| §5 the seven tokens, the contrast test, the strong band, the contract's two entries, the second theme | Task 6 |
| §5 the documentation theme | not this repository: named in Task 7 Step 4 |
| §6 MCP and Markdown: nothing changes | no task; Task 3 Step 9 runs the MCP tests |
| Risks | Task 1 (confined, plain on failure, the cap), Task 7 (the gaps on the roadmap) |
| Testing, every bullet | Tasks 1 to 6 |
| Documentation | Task 7 (Task 6 for `theming.md`) |

**Without a task:** the guide pages (they live in `contentspiel-docs`; Task 7 Step 7 names them). The documentation theme's three changes (its repository). German and Spanish for the four public strings (roadmap item 7). Nothing else.

**Placeholders:** none. Two things are deliberately left to be read off code that does not exist yet, and only in Task 6: the shape of `Theme::Contract`'s two constants and the helper that turns a fixture folder into a `Theme`. The task says so at its top and gives the theming spec's names to adapt.

**Names, checked across tasks:** `CodeHighlight.lines(code, language, block_id:)`, `.label`, `.cache_key`, `LANGUAGES`, `ROLES`, `MAX_CHARACTERS`, `REVISION` (Task 1, used in 3, 5, 6); the field option `blank:` and the type `:code` (Task 2, used in 3); `Admin::Fields::CodeField`'s ids `block-<id>-code`, `-code-count`, `-code-errors` (Task 2, used in 5); `admin--editor--code-limit#update` (Task 2: the script, the component, `HeldFields`, both test lists); the capability `:code` (Task 3, used in 5); `code-copy` with `button`, `source`, `status`, `copied`, `failed`, `restore` (Task 3's markup, Task 4's script and tests, Task 6's fixture); `syn-<role>` and `--th-syn-<role>` (Task 3's stylesheet, Task 6's tokens); `public.blocks.code.{copy,copy_code,copied,failed}` (Task 3's file and component).
