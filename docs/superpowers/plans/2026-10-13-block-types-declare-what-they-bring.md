# A block type declares everything it brings — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A block type says in its own definition what it brings (its contract line, its tokens, its stylesheet, its tile line, its read-only editor actions and one filled sample of itself), and every list that only repeated that is derived from the registry, so a built-in type is added by `bin/rails generate block_type <name>` and one definition, and an outside type can be registered through one hook, with no change a visitor or an editor can see.

**Architecture:** `ContentModel::BlockTypeDefinition` gains six declarations. `Theme::Contract`'s block lists become methods that read `BlockTypes.all` (the shared tokens, the templates, the post components, the helpers and the rich-text selectors stay constants), and a hand-written **ledger** test holds the built-ins' part to today's names. The stylesheet entry (`ThemeCss.entry`), the editor's tile (`TileSummaryComponent`), the held form's allow-list (`HeldFields.allowed_actions`) and the shared tests (`test/support/block_samples.rb`) read the declarations. The five built-ins are converted one at a time behind a short transition (their old hand-written entries are read only for a type that declares nothing yet), then the two declarations become required. `ContentSpiel::Plugins.block_types` (`lib/content_spiel/plugins.rb`) keeps an engine's registration block and `config/initializers/types.rb` replays it after the built-ins on every prepare, and the theme is prepared last in that same block.

**Tech Stack:** Rails 8.1, ViewComponent 4.15, Tailwind 4 (`tailwindcss-ruby`), Rails generators (Thor), Minitest + fixtures, Capybara on Cuprite.

**Spec:** `docs/superpowers/specs/2026-10-13-block-types-declare-what-they-bring-design.md` (approved 2026-10-13; read all of it, "The owner's answers" included: they settle the open questions and win over the decisions above them where the two differ). The map of every hand-written place, with line numbers at `c182882b`, is `/Users/dknafelj/src/ContentSpiel/.superpowers/block-types-map.md`.

## Global Constraints

- Read `CLAUDE.md` first; its rules bind. Read `docs/reference/content-blocks-and-types.md` before every task, `docs/reference/theming.md` before Tasks 2, 3, 6, 8 and 12, `docs/reference/live-editing.md` ("A form someone else holds") before Task 4, `docs/reference/i18n.md` before Tasks 4, 8, 9 and 11.
- **No behaviour change for a visitor or an editor.** No page, card, tile, word or style changes. Each task names how it proves that; the proofs across the plan are the ledger (Task 2), `test/values/theme/scaffold_test.rb` byte for byte (every task from 2 on), the canary (`test/integration/public_canary_test.rb`), the tile's and the held form's existing tests unchanged in their expectations, and the before/after comparison of the built stylesheet (Tasks 3, 8 and 12) and of every public page of the seeded site (Task 12) against the snapshot the controller takes in Task 0, **before any code changes**.
- Every test command is prefixed `PGGSSENCMODE=disable`. One file is `PGGSSENCMODE=disable bin/rails test <path>`. A system test is run one file at a time, after `bin/rails tailwindcss:build` and `bin/rails theme_css:build`: `PGGSSENCMODE=disable bin/rails test test/system/<file>`. **Never two test runs at once on this machine** (worktrees share the test databases), **never a build while tests run** (the stylesheet's stamp, `CLAUDE.md`), and `bin/theme-build-check` is run alone. The full unit and browser suites are the controller's, in Task 12.
- No fixed sleeps in a system test; a system test fails on any JavaScript error (`CLAUDE.md`).
- The definition holds data: names, a path, a callable that answers data. Only a component or a task turns it into markup or a file, so `test/lib/dependency_direction_test.rb` needs no new entry. A model returns no markup and translates nothing.
- `lib/` reads no registry. What `lib/theme_css.rb` needs of the block types is handed to it as data by `lib/tasks/theme_css.rake`. `lib/content_spiel/plugins.rb` is plain Ruby (it is required before `Bundler.require`) and names no application constant at load time.
- New CS Studio strings are locale keys; the tile's per-type words live under `admin.components.editor_screen.tile_summary.types.<type>` (a slash in a type's name read as a dot). A type's label, a select's choices, `blank:` and `label:` stay literals in the definition.
- Tokens, never colour literals: in CS Studio sources (`test/lib/admin_design_rules_test.rb`), in the default theme's stylesheets other than `tokens.css`, and in an outside type's stylesheet (decision 3, refused at registration from Task 6).
- Stimulus identifiers follow the path; a `read_only_actions` entry is `identifier#method` of a controller file that exists.
- Never define an `Admin::` constant named after a top-level domain: `Admin::ContentSpiel` is refused by `test/lib/admin_namespace_shadow_test.rb` once `lib/content_spiel/` exists. Inside `module Admin` write `::BlockTypes`.
- Built-ins stay where Rails puts them (decision 15): no folder per type, no engine for a built-in.
- The order of the block types is the picker's: `rich_text`, `image`, `code`, `post_list`, `section`, then outside types in the order their hooks were called.
- Commits: one per task (Task 12 makes two). Conventional subject (`feat:`, `ref:`, `test:`, `docs:`), and the message ends with exactly these two lines:

```
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT
```

- Scratch files only in a directory made with `mktemp -d` and deleted by name; nothing is written into the worktree that is not committed.
- No guide text in this repository. The guide pages (`contentspiel-docs`) are named in the pull request's "Documentation" section only (Task 12, Step 9).

### Where the plan departs from the spec's wording, and why

Each was checked against the code at `61a85d01`; none changes what the owner approved.

1. **`sections.css` stays the default theme's own stylesheet; the Section type declares no `stylesheet`.** Decision 7 says `theme.css` no longer imports `sections.css` or `code.css`; the owner's answer 4 says the default theme's own stylesheets, `sections.css` among them, come before every type's by a fixed rule of the entry. So `theme.css` keeps `tokens.css`, `prose.css` and `sections.css` (which also holds the strong band's re-values of other types' tokens, decision 3), and only `code.css` leaves it, for the Code type's `stylesheet "code.css"`. The entry is: the default theme's `theme.css`, then each type's stylesheet in registration order, then the theme's. That is today's order, so the built stylesheet is expected to be byte for byte the same; Tasks 3 and 8 compare it.
2. **A transition between the mechanism and the conversions.** Decision 16 puts the mechanism first "with the five types still written as today", and decision 2 makes `theme_methods` and `sample` required. Both cannot hold in one commit. So the requirement is switched on in Task 10, after the last conversion, and until then `Theme::Contract::WRITTEN_BLOCK_LINES` and `WRITTEN_BLOCK_THEMED_TOKENS` and `HeldFields::WRITTEN_TYPE_ACTIONS` hold today's entries for a type that declares nothing yet. Each conversion task deletes its type's entries; Task 10 deletes the constants. The ledger is green at every commit.
3. **The tile's parts are four kinds, not three.** Decision 8's set (`:text`, `:mono`, `:word`) cannot draw the Code tile's "Empty" in `text-meta` (`tile_summary_component_test.rb`: `"#{line} > span.text-meta"`) without a visible change. A fourth kind, `[:hint, key, **values]`, is a CS Studio word in the meta colour. The Note block's `[:icon, name]` will be the fifth.
4. **"Every declared token is defined in the built stylesheet" reads the sources the build imports** (`tokens.css` and each registered type's stylesheet), not the minified output: they hold the same declarations, and the sources can be split by selector.
5. **The derived smoke test is two files.** `test/models/block_samples_test.rb` would request public pages and render CS Studio components; in this repository's layout that is `test/integration/block_samples_test.rb` (save, publish, draw from the copy, top level and in a column) and `test/components/admin/editor_screen/block_samples_card_test.rb` (the card and its held form).
6. **The contract test's invented `marquee`** cannot fail the old way once `theme_methods` is required: registration refuses it first. In Task 10 the test becomes "a block type registered without theme methods is refused at registration, and the message says what to declare", the same guarantee one step earlier.
7. **The generator's own test cannot run the whole suite in-process.** `test/lib/generators/block_type_generator_test.rb` writes the files into a temporary folder, loads the generated definition and component, registers the type and runs the derived checks on it (the contract, the sample saved, published and drawn); Task 11 also runs the guards and the shared tests once with a generated type in the working tree and destroys it again before the commit.
8. **The colour-literal guard for an outside type's stylesheet** has no place in the spec; it is `BlockTypeDefinition#finalize!` for a type with an owner, which also refuses a relative `stylesheet` path for such a type.
9. **`theme:new` and the check need an outside type's template file.** `CLAUDE.md` says nothing but `Theme#component_for` names ViewComponent's `sidecar_files`, so `BlockTypeDefinition#component_template` finds it beside the component's source file (`Object.const_source_location`).
10. **The theme's prepare moves into `types.rb`** (decision 6). Its `booted` flag becomes `Rails.application.config.x.theme_booted`, set in `config/initializers/theme.rb`'s `after_initialize`, and `test/lib/theme_guards_test.rb`'s allow-list names `config/initializers/types.rb` and the new line.
11. **Requiring the hook before `Bundler.require` is right** (the task asked to check it): an engine's `initializer` runs after `config/application.rb` has been read, so the convention alone would not need it, but a gem that names the hook when its own file is loaded by `Bundler.require` would raise `NameError` without it. It follows `lib/site_address.rb`'s and `lib/telemetry/path_scrubber.rb`'s pattern: required explicitly although `lib/` is autoloaded, therefore not reloaded, which is what the hook needs (its kept blocks outlive every reload).
12. **Every test that registers a block type of its own** (eight files, listed in Task 10) gains the two required lines through one helper, `TestTypes.declare(t)`.

## Review Focus

1. **A gem removed from a site.** A page that holds a block of a type no longer registered must still answer 200 on the site (the block skipped) and in the editor ("Unavailable type — gallery/album"), its published copy must not move, and a theme that still replaces that type's template must be refused by the check with a message that names the template and says to remove it (Task 6: `"a block of an outside type that is no longer registered is dormant: the page answers, the editor names it, the copy stays, and a theme's template of it is refused by name"`).
2. **A development reload with an outside type.** After any code reload the outside type must come back after the five built-ins, and a theme that replaces its template must still pass the check, because the theme is prepared after the types (Task 6: `"a type registered through the hook survives a reload, after the built-ins, and the theme check still knows its template"`).
3. **A sample that proves nothing.** A sample that leaves a column its type uses empty (no caption, no alt, no body, no image) lets the canary pass while the column is never compared (spec, Risks). Every column a type `uses` must be filled by its sample (Task 5: `"a sample fills every column its type uses and names at least one text the public page shows"`).
4. **A theme that re-colours a block.** After `code.css` leaves `theme.css` for the entry, a theme's own stylesheet must still come after every type's, so its `--th-syn-keyword` still wins (Task 3: `"a theme's stylesheet is imported after every type's, so a block token it declares again wins"`).
5. **An empty or odd block on a tile.** Once the Code and Post list lines move into the types, a block with no settings, a Code block whose stored language is no longer on the list, and a post list naming a content type that is no longer registered must read exactly as today and raise nothing (Task 8: `"a code block whose stored language is not on the list reads as plain text: its first line alone"`; Task 9: `"a post list naming a content type that is no longer registered reads as its stored name"`; the existing empty-block tests of both).

## File map

| File | Responsibility |
|---|---|
| `app/models/content_model/block_type_definition.rb` | The six declarations, `owner`, `stylesheet_path`, `component_template`, the closed `uses`, the outside type's refusals, the requirement (Tasks 1, 6, 8, 10) |
| `app/models/block_types.rb` | `theme_css_blocks`: the build's inputs as data (Task 3) |
| `app/models/block_types/{rich_text,image,code,post_list,section}.rb` | Each type's declarations; `Code.summary`, `PostList.summary` (Tasks 7–9) |
| `app/values/theme/contract.rb` | `components`, `themed_tokens`, `fixed_tokens`, `tokens`, `path_of`, `template_for`; the shared constants; the transition's written entries (Tasks 2, 7–10) |
| `app/values/theme/check.rb`, `scaffold.rb` | Read the contract's methods; the message for a template of no registered type (Task 2) |
| `config/initializers/types.rb`, `theme.rb` | The theme prepared last; the hook's replay; the generator's marker (Tasks 2, 6, 11) |
| `lib/theme_css.rb`, `lib/tasks/theme_css.rake`, `app/assets/tailwind/themes/default/theme.css` | The entry imports each type's stylesheet (Tasks 3, 8) |
| `app/components/admin/editor_screen/tile_summary_component.rb`, `config/locales/admin/editor_screen.en.yml` | The tile draws a type's summary parts; the words move under `types` (Tasks 4, 8, 9) |
| `app/components/admin/editor_screen/held_fields.rb` | `CMS_ACTIONS`, `allowed_actions` (Tasks 4, 8) |
| `lib/content_spiel/plugins.rb`, `config/application.rb` | The hook (Task 6) |
| `lib/generators/block_type/` | The generator and its templates (Task 11) |
| `test/support/contract_ledger.rb`, `test/values/theme/contract_ledger_test.rb` | The ledger and its test (Task 2) |
| `test/support/block_samples.rb`, `test/support/gallery_album.rb`, `test/fixtures/block_types/gallery/` | The sample helper; the outside test type (Tasks 5, 6) |
| `test/integration/block_samples_test.rb`, `test/components/admin/editor_screen/block_samples_card_test.rb` | The derived smoke tests (Task 5) |
| `test/lib/content_spiel/plugins_test.rb`, `test/models/content_model/block_type_definition_test.rb`, `test/lib/generators/block_type_generator_test.rb` | New guards (Tasks 1, 6, 10, 11) |
| `docs/reference/*.md`, `CLAUDE.md`, the spec, `docs/roadmap.md` | Folded into each task where a reference describes its change; the spanning documents in Task 12 |

---

### Task 0: the "before" snapshot (the controller's, before Task 1 is dispatched)

**Who and when:** the controller, in this worktree, on the commit that adds this plan, **before any implementer starts and before any code changes**. Nothing else may run meanwhile (no tests, no `bin/dev`). The snapshot lives outside the worktree and is compared in Tasks 3, 8 and 12; it is not committed.

- [ ] **Step 1: a scratch folder.** `SNAP="$(mktemp -d)"; echo "$SNAP"` and write the path into the controller's notes: every later comparison names it.

- [ ] **Step 2: the stylesheet.**

```sh
bin/rails tailwindcss:build
cp app/assets/builds/theme.css "$SNAP/theme.before.css"
```

  Expected: the build ends without an error; `$SNAP/theme.before.css` is non-empty.

- [ ] **Step 3: the seeded site.** `bin/rails runner 'puts Page.count'`. If it prints `0`, run `bin/rails db:prepare && bin/rails db:seed`. From here until Task 12's comparison, nothing writes to the development database (no `bin/dev` session that edits, no seed).

- [ ] **Step 4: the pages script,** written to `$SNAP/pages.rb` (it is the same script for the after-snapshot):

```ruby
# Every public page of the development site, as a visitor gets it, one file
# per address: the status on the first line, then the body with the
# per-request nonce taken out. Usage: bin/rails runner "$SNAP/pages.rb" "$SNAP/before"
require "action_dispatch/testing/integration"

out = Pathname(ARGV.fetch(0))
out.mkpath
session = ActionDispatch::Integration::Session.new(Rails.application)
session.host! "localhost"

paths = PublicPath.current.includes(:record).filter_map { |row| PublicSite::Urls.new.path_for(row.record, row.locale) }
paths += [ "/", "/no-such-page-anywhere" ] + SiteSetting.instance.locale_codes.map { |code| "/#{code}/" }
paths.uniq.sort.each do |path|
  session.get(path)
  name = path == "/" ? "_root" : path.delete_prefix("/").delete_suffix("/").tr("/", "~")
  out.join("#{name}.html").write("#{session.response.status}\n#{session.response.body.gsub(/ nonce="[^"]*"/, "")}")
end
puts "#{paths.uniq.size} pages written to #{out}"
```

- [ ] **Step 5: run it.** `bin/rails runner "$SNAP/pages.rb" "$SNAP/before"`. Expected: `N pages written to …/before` with N above 5, and `grep -L '^200' "$SNAP"/before/*.html` lists only `no-such-page-anywhere.html`.

---

### Task 1: the six declarations on the definition

**Files:**
- Modify: `app/models/content_model/block_type_definition.rb`
- Create: `test/models/content_model/block_type_definition_test.rb`

**Interfaces:**
- Consumes: `ContentModel::Definition` (`dsl_attribute`, `uses`, `capability?`, `fields`), `ThemeCss::DEFAULT` (`lib/theme_css.rb`, `"app/assets/tailwind/themes/default/theme.css"`).
- Produces (every later task relies on these names):

```ruby
ContentModel::BlockTypeDefinition::COLUMNS          # %w[body caption alt image]
ContentModel::BlockTypeDefinition::Sample           # Data.define(:settings, :translations, :body, :image, :shows)
definition.theme_methods(*names)  # setter with names; reader without: Array<String> (frozen) or nil
definition.tokens(themed: [], fixed: [])            # setter only
definition.themed_tokens          # Array<String>, without "--th-"; [] by default
definition.fixed_tokens           # Array<String>; [] by default
definition.stylesheet(path = nil) # setter/reader (dsl_attribute): String or Pathname or nil
definition.summary(callable = nil)  # setter/reader: responds to call(block, locale:) => Array of parts, or nil
definition.read_only_actions(*ids)  # setter with ids; reader without: Array<String> ("identifier#method"); [] by default
definition.sample(**values)       # setter with keywords; reader without: Sample or nil
                                  #   Sample#settings: Hash (string keys), #translations: Hash ("en" => Hash), #body: String (Markdown) or nil,
                                  #   #image: true/false, #shows: Array<String>, at least one
definition.owner                  # "gallery" for "gallery/album"; nil for a bare (built-in) name
definition.stylesheet_path(root: Rails.root)  # absolute Pathname or nil; a relative stylesheet is in the default theme's folder
definition.component_template     # Pathname of the .html.erb beside the component's source file, or nil without a component
```

- [ ] **Step 1: write the failing test,** `test/models/content_model/block_type_definition_test.rb`:

```ruby
require "test_helper"

# What a block type declares beside its fields (block types spec, decision 1):
# the names a theme may call, its tokens, its stylesheet, its tile line, its
# editor script's read-only actions and one filled sample. Each is read by a
# list that used to be written by hand; here only their shapes are held.
class ContentModel::BlockTypeDefinitionTest < ActiveSupport::TestCase
  def definition(name = "test_shape") = ContentModel::BlockTypeDefinition.new(name)

  test "the six declarations are read back as they were given, and are empty or nil when not given" do
    summary = ->(_block, locale:) { [ [ :text, locale ] ] }
    d = definition
    assert_nil d.theme_methods
    assert_equal [], d.themed_tokens
    assert_equal [], d.fixed_tokens
    assert_nil d.stylesheet
    assert_nil d.summary
    assert_equal [], d.read_only_actions
    assert_nil d.sample

    d.theme_methods :block, :page, :titled?
    d.tokens themed: %w[shape-ground], fixed: %w[shape-gap]
    d.stylesheet "shape.css"
    d.summary summary
    d.read_only_actions "admin--ui--char-count#update"
    d.sample settings: { language: "ruby" }, translations: { "en" => { caption: "A caption" } }, body: "Some **words**", image: true, shows: [ "A caption" ]

    assert_equal %w[block page titled?], d.theme_methods
    assert_predicate d.theme_methods, :frozen?
    assert_equal %w[shape-ground], d.themed_tokens
    assert_equal %w[shape-gap], d.fixed_tokens
    assert_equal "shape.css", d.stylesheet
    assert_same summary, d.summary
    assert_equal %w[admin--ui--char-count#update], d.read_only_actions
    assert_equal({ "language" => "ruby" }, d.sample.settings)
    assert_equal({ "en" => { caption: "A caption" } }, d.sample.translations)
    assert_equal "Some **words**", d.sample.body
    assert_equal true, d.sample.image
    assert_equal [ "A caption" ], d.sample.shows
  end

  test "a declaration of the wrong shape is refused when it is written, and the message says the shape" do
    assert_match(/a method's name/, assert_raises(ArgumentError) { definition.theme_methods "Block" }.message)
    assert_match(/without the --th- prefix/, assert_raises(ArgumentError) { definition.tokens themed: %w[--th-x] }.message)
    assert_match(/without the --th- prefix/, assert_raises(ArgumentError) { definition.tokens fixed: %w[Shape_gap] }.message)
    assert_match(/identifier#method/, assert_raises(ArgumentError) { definition.read_only_actions "update" }.message)
    assert_match(/callable/, assert_raises(ArgumentError) { definition.summary "words" }.message)
    assert_match(/settings, translations, body, image, shows/, assert_raises(ArgumentError) { definition.sample shows: [ "x" ], blocks: [] }.message)
    assert_match(/at least one text/, assert_raises(ArgumentError) { definition.sample settings: {} }.message)
    assert_match(/at least one text/, assert_raises(ArgumentError) { definition.sample shows: [] }.message)
    assert_match(/"en" at least/, assert_raises(ArgumentError) { definition.sample translations: { "de" => { caption: "x" } }, shows: [ "x" ] }.message)
  end

  test "uses outside body, caption, alt and image is refused" do
    d = definition
    d.uses :caption, :alt
    assert_equal %w[caption alt], d.uses_columns

    error = assert_raises(ArgumentError) { definition.uses :caption, :subtitle }
    assert_includes error.message, "subtitle"
    assert_includes error.message, "body, caption, alt, image"
  end

  test "owner is the part of the name before the slash, and a built-in has none" do
    assert_nil definition("code").owner
    assert_equal "gallery", definition("gallery/album").owner
  end

  test "a relative stylesheet is in the default theme's folder, an absolute one is taken as it is" do
    d = definition
    assert_nil d.stylesheet_path
    d.stylesheet "code.css"
    assert_equal Rails.root.join("app/assets/tailwind/themes/default/code.css"), d.stylesheet_path
    d.stylesheet Pathname("/srv/gem/album.css")
    assert_equal Pathname("/srv/gem/album.css"), d.stylesheet_path
  end

  test "a component's template is the file beside its source" do
    assert_equal Rails.root.join("app/components/blocks/code_component.html.erb"), BlockTypes.fetch(:code).component_template
    assert_nil definition.component_template
  end
end
```

- [ ] **Step 2: run it.** `PGGSSENCMODE=disable bin/rails test test/models/content_model/block_type_definition_test.rb`. Expected: errors with `NoMethodError: undefined method 'theme_methods'` (and the `uses` test fails: no refusal).

- [ ] **Step 3: implement.** In `app/models/content_model/block_type_definition.rb`, below `dsl_attribute :columns` and above `finalize!` (keep every existing line and comment):

```ruby
    # What a block type brings beside its fields (block types spec, decision
    # 1). Each declaration is READ by the list that used to repeat it by hand:
    # `theme_methods` and `tokens` by `Theme::Contract`, `stylesheet` by the
    # public stylesheet's build (`BlockTypes.theme_css_blocks`), `summary` by
    # the editor's tile, `read_only_actions` by the held form's allow-list,
    # `sample` by the shared tests. A declaration nothing reads would be
    # documentation in code; none of these is.
    #
    # The columns a block type may name with `uses`: the block card draws and
    # the save services write these four and no other (`BlockCardComponent`'s
    # template, `Admin::ContentBlocksController::TRANSLATED_COLUMNS`), so a
    # fifth name was silently drawn as nothing (decision 12).
    COLUMNS = %w[body caption alt image].freeze

    METHOD_NAME = /\A[a-z_][a-z0-9_]*\??\z/
    TOKEN_NAME = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
    ACTION = /\A[a-z0-9]+(?:-[a-z0-9]+)*(?:--[a-z0-9]+(?:-[a-z0-9]+)*)*#[a-zA-Z]\w*\z/

    # One filled block of the type (decision 14): `settings` (string keys),
    # `translations` (locale => values: translated schema fields and the
    # `caption` / `alt` columns), `body` (Markdown, written in the default
    # language), `image` (true: the test attaches a library image), `shows`
    # (texts the public page holds for the block).
    Sample = Data.define(:settings, :translations, :body, :image, :shows)

    def initialize(name)
      super
      @themed_tokens = []
      @fixed_tokens = []
      @read_only_actions = []
    end

    attr_reader :themed_tokens, :fixed_tokens

    dsl_attribute :stylesheet

    def uses(*columns)
      unknown = columns.map(&:to_s) - COLUMNS
      raise ArgumentError, "a block type uses #{COLUMNS.join(", ")} and no other column; #{unknown.join(", ")} is drawn and saved by nothing" if unknown.any?

      super
    end

    # The methods the type's public template may call: the type's line in the
    # theme contract, a promise to themes outside this repository.
    def theme_methods(*names)
      return @theme_methods if names.empty?

      names = names.map(&:to_s)
      bad = names.grep_v(METHOD_NAME)
      raise ArgumentError, "theme_methods takes a method's name, lowercase: #{bad.inspect}" if bad.any?

      @theme_methods = names.freeze
    end

    # The `--th-` tokens the type brings, without the prefix: `themed` have a
    # value for light and one for dark, `fixed` have one.
    def tokens(themed: [], fixed: [])
      themed = themed.map(&:to_s)
      fixed = fixed.map(&:to_s)
      bad = (themed + fixed).grep_v(TOKEN_NAME)
      raise ArgumentError, "a token is named without the --th- prefix, in lowercase words joined by dashes: #{bad.inspect}" if bad.any?

      @themed_tokens = themed.freeze
      @fixed_tokens = fixed.freeze
    end

    # The tile's line of a closed block, as data: a callable taking the
    # block and `locale:` and answering parts (decision 8; the kinds are
    # `Admin::EditorScreen::TileSummaryComponent::LOOKS`).
    def summary(callable = nil)
      return @summary if callable.nil?
      raise ArgumentError, "`summary` is a callable taking the block and `locale:`" unless callable.respond_to?(:call)

      @summary = callable
    end

    # The type's editor-script actions that only read or move focus: they
    # survive in a form someone else holds (decision 10).
    def read_only_actions(*ids)
      return @read_only_actions if ids.empty?

      ids = ids.map(&:to_s)
      bad = ids.grep_v(ACTION)
      raise ArgumentError, "a read-only action is written identifier#method (admin--editor--code-limit#update): #{bad.inspect}" if bad.any?

      @read_only_actions = ids.freeze
    end

    def sample(**values)
      return @sample if values.empty?

      unknown = values.keys - Sample.members
      raise ArgumentError, "a sample holds settings, translations, body, image, shows; not #{unknown.join(", ")}" if unknown.any?

      shows = Array(values[:shows])
      raise ArgumentError, "a sample's `shows:` names at least one text the public page holds for it" if shows.empty? || !shows.all?(String)

      translations = (values[:translations] || {}).transform_keys(&:to_s)
      raise ArgumentError, "a sample's translations are written for \"en\" at least" if translations.any? && !translations.key?("en")

      @sample = Sample.new(
        settings: (values[:settings] || {}).transform_keys(&:to_s).freeze,
        translations: translations.freeze,
        body: values[:body],
        image: values[:image] == true,
        shows: shows.freeze
      )
    end

    # "gallery" for "gallery/album": an outside type's names are its owner's.
    def owner = name.include?("/") ? name.split("/", 2).first : nil

    def stylesheet_path(root: Rails.root)
      return nil if stylesheet.nil?

      path = Pathname(stylesheet)
      path.absolute? ? path : Pathname(root).join(ThemeCss::DEFAULT).dirname.join(path)
    end

    # The component's own template, found beside its source file, not
    # through ViewComponent's `sidecar_files` (`Theme#component_for` is the
    # one place that names that, `CLAUDE.md`). `theme:new` copies it and the
    # build scans its folder when it is outside app/components/blocks.
    def component_template
      file, = component && Object.const_source_location(component.name)
      file && Pathname(file).sub_ext(".html.erb")
    end
```

  Check before running: `grep -rn "t.uses\|\.uses " app test | grep -v "body\|caption\|alt\|image"` lists no block type that uses another column (a content type's `uses` is `ContentTypeDefinition`'s and unaffected).

- [ ] **Step 4: run it and the neighbours.**

```sh
PGGSSENCMODE=disable bin/rails test test/models/content_model test/models/built_in_types_test.rb test/models/content_block_test.rb
```

  Expected: 0 failures, 0 errors.

- [ ] **Step 5: commit.**

```bash
git add app/models/content_model/block_type_definition.rb test/models/content_model/block_type_definition_test.rb
git commit -m "feat: a block type can declare its theme methods, tokens, stylesheet, tile line, read-only actions and a sample

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 2: the derived contract, the ledger, and the theme prepared after the types

**Files:**
- Modify: `app/values/theme/contract.rb`, `app/values/theme/check.rb` (`MAY_HOLD`, `misplaced`), `app/values/theme/scaffold.rb` (`write`, `stylesheet`), `config/initializers/types.rb`, `config/initializers/theme.rb`, `app/components/blocks/image_component.rb` (the comment naming `COMPONENTS`), `docs/reference/theming.md` (every mention of the four constants and of the theme's prepare in `theme.rb`)
- Create: `test/support/contract_ledger.rb`, `test/values/theme/contract_ledger_test.rb`
- Modify: `test/test_helper.rb` (requires the ledger)
- Modify tests: `test/values/theme/contract_test.rb`, `test/values/theme/check_test.rb`, `test/values/theme/scaffold_test.rb`, `test/lib/theming_reference_test.rb`, `test/integration/theme_pages_test.rb` (lines 329–390 and 515), `test/lib/theme_guards_test.rb`

**Interfaces:**
- Consumes: Task 1's `theme_methods`, `themed_tokens`, `fixed_tokens`, `owner`, `component_template`.
- Produces:

```ruby
Theme::Contract.components         # Hash{String path => Array<String>}, frozen: block types in registration order, then POST_COMPONENTS
Theme::Contract.themed_tokens      # Array<String>: SHARED_THEMED_TOKENS, then each block type's, in registration order
Theme::Contract.fixed_tokens       # Array<String>: SHARED_FIXED_TOKENS, then each block type's
Theme::Contract.tokens             # Array<String>, prefixed "--th-"
Theme::Contract.path_of(component) # component.name.underscore ("blocks/code_component")
Theme::Contract.template_for(path, root: Rails.root)  # Pathname of the default template a theme replaces
Theme::Contract::SHARED_THEMED_TOKENS, SHARED_FIXED_TOKENS, POST_COMPONENTS   # constants
Theme::Contract::WRITTEN_BLOCK_LINES          # transition: today's five block lines, read only for a type that declares no theme_methods
Theme::Contract::WRITTEN_BLOCK_THEMED_TOKENS  # transition: { "code" => %w[syn-comment … syn-embed] }
ContractLedger::COMPONENTS, ::THEMED_TOKENS, ::FIXED_TOKENS   # test/support/contract_ledger.rb: the ledger, read by its test and by theming_reference_test.rb
Rails.application.config.x.theme_booted       # false at boot's prepare, true after
```

- [ ] **Step 1: write the ledger, failing.** The written copy is data in `test/support/contract_ledger.rb` (required by `test/test_helper.rb` beside `support/test_types`), because two tests read it: the ledger test below, and `test/lib/theming_reference_test.rb` (Step 6), which holds the reference's tables to it. A test file is never required by another (the runner loads each, and `test "…"` raises for a test defined twice).

```ruby
# THE LEDGER (block types spec, decision 4). The contract's block lists are
# derived from the registry, which makes ADDING a name easy and also makes
# REMOVING one easy: a method dropped from a type's `theme_methods`, a token
# renamed, a type deleted, and a theme outside this repository breaks with no
# test failing. This is the one hand list kept on purpose: the built-in
# types' part of the contract, written out, held to the code by
# test/values/theme/contract_ledger_test.rb and to docs/reference/theming.md
# by test/lib/theming_reference_test.rb. Changing it is the moment a person
# writes the release note ("a name added, renamed or removed is a release
# note"), so change it only together with that note.
#
# A type with an owner's name (`gallery/album`, `test/quote`) is its gem's
# promise, not the CMS's, and is not in it.
module ContractLedger
  COMPONENTS = {
    "blocks/rich_text_component" => %w[block page],
    "blocks/image_component" => %w[block page asset alt caption sizes],
    "blocks/code_component" => %w[block page lines code language language_label filename caption string],
    "blocks/post_list_component" => %w[block page list_component],
    "blocks/section_component" => %w[block page columns layout background width],
    "posts/blog_list_component" => %w[posts page],
    "posts/resume_list_component" => %w[posts page],
    "posts/now_list_component" => %w[posts page],
    "posts/detail_component" => %w[post]
  }.freeze

  THEMED_TOKENS = %w[
    paper surface sunken ink dim meta line line-strong
    accent accent-hover accent-tint on-accent
    ok ok-ink ok-tint warn warn-ink warn-tint danger danger-ink danger-tint
    shadow-menu
    band-tinted band-strong on-band-strong on-band-strong-dim on-band-strong-accent
    syn-comment syn-keyword syn-string syn-constant syn-tag syn-attribute syn-embed
  ].freeze

  FIXED_TOKENS = %w[
    font mono
    t-display t-h1 t-h2 t-h3 t-body t-small t-label
    track-mono track-wide
    sp-1 sp-2 sp-3 sp-4 sp-5 sp-6 sp-7
    radius radius-pill ease
  ].freeze
end
```

  `test/values/theme/contract_ledger_test.rb`:

```ruby
require "test_helper"

# The built-in types' part of the contract is the ledger
# (test/support/contract_ledger.rb, which says why it is written by hand).
class Theme::ContractLedgerTest < ActiveSupport::TestCase
  include ContractLedger

  def outside = BlockTypes.all.select(&:owner)

  def built_in_components
    Theme::Contract.components.except(*outside.filter_map { |definition| definition.component && Theme::Contract.path_of(definition.component) })
  end

  def built_in(list, reader) = list - outside.flat_map(&reader)

  def assert_ledger(components: built_in_components, themed: built_in(Theme::Contract.themed_tokens, :themed_tokens), fixed: built_in(Theme::Contract.fixed_tokens, :fixed_tokens))
    note = "Theme::Contract no longer says what the ledger says. A theme outside this repository relies on every name here: " \
           "if the change is meant, write the release note and change the ledger in test/support/contract_ledger.rb with it"
    assert_equal COMPONENTS.keys, components.keys, "#{note} (the components, in order)"
    COMPONENTS.each { |path, methods| assert_equal methods, components.fetch(path), "#{note} (the methods of #{path})" }
    assert_equal THEMED_TOKENS, themed, "#{note} (the themed tokens, in order)"
    assert_equal FIXED_TOKENS, fixed, "#{note} (the fixed tokens, in order)"
  end

  test "the built-in types' part of the contract is the ledger: a name added, renamed or removed is a release note" do
    assert_ledger
  end

  test "the ledger can fail: a method dropped from a built-in's line, and a token renamed, are each named" do
    dropped = built_in_components.merge("blocks/image_component" => %w[block page asset alt caption])
    error = assert_raises(Minitest::Assertion) { assert_ledger(components: dropped) }
    assert_includes error.message, "the methods of blocks/image_component"

    renamed = built_in(Theme::Contract.themed_tokens, :themed_tokens).map { |name| name == "syn-attribute" ? "syn-attr" : name }
    error = assert_raises(Minitest::Assertion) { assert_ledger(themed: renamed) }
    assert_includes error.message, "the themed tokens, in order"
  end
end
```

- [ ] **Step 2: run it.** `PGGSSENCMODE=disable bin/rails test test/values/theme/contract_ledger_test.rb`. Expected: errors, `NoMethodError: undefined method 'components' for module Theme::Contract`.

- [ ] **Step 3: the contract.** In `app/values/theme/contract.rb`:
  - Rewrite the class comment's "ADDING A BLOCK TYPE" paragraph: a block type joins by its declarations (`theme_methods`, `tokens`), which these methods read from `BlockTypes`; the built-ins' part is held by the ledger (`test/values/theme/contract_ledger_test.rb`); content types are not part of this (their three components stay written in `POST_COMPONENTS`); the lists are still data and name no class, a component being written as its path.
  - Replace `THEMED_TOKENS` with `SHARED_THEMED_TOKENS` (the first 27 names, without the seven `syn-*`), `FIXED_TOKENS` with `SHARED_FIXED_TOKENS` (the same 21), delete `TOKENS`, and split `COMPONENTS` into the transition's `WRITTEN_BLOCK_LINES` (the five `blocks/*` lines, the Code line's comment moved with it) and `POST_COMPONENTS` (the four `posts/*` lines). Add:

```ruby
    # THE TRANSITION (block types plan, Tasks 2 to 10): today's lines and
    # tokens of a built-in that declares nothing yet. Read only for a type
    # whose definition has no `theme_methods` (no `tokens`); each type's
    # conversion deletes its entry, and Task 10 deletes both constants.
    WRITTEN_BLOCK_THEMED_TOKENS = {
      "code" => %w[syn-comment syn-keyword syn-string syn-constant syn-tag syn-attribute syn-embed]
    }.freeze

    def self.path_of(component) = component.name.underscore

    # Every component whose template a theme may replace, with the methods
    # it may call: each registered block type's line (its `theme_methods`),
    # in registration order, then the post components. Read on every call,
    # never kept in a constant: a constant is read when this file loads,
    # before `to_prepare` has registered anything.
    def self.components
      blocks = ::BlockTypes.all.filter_map do |definition|
        next unless definition.component

        path = path_of(definition.component)
        methods = definition.theme_methods || WRITTEN_BLOCK_LINES[path]
        [ path, methods ] if methods
      end
      blocks.to_h.merge(POST_COMPONENTS).freeze
    end

    def self.themed_tokens
      SHARED_THEMED_TOKENS + ::BlockTypes.all.flat_map { |definition| definition.themed_tokens.presence || WRITTEN_BLOCK_THEMED_TOKENS.fetch(definition.name, []) }
    end

    def self.fixed_tokens = SHARED_FIXED_TOKENS + ::BlockTypes.all.flat_map(&:fixed_tokens)

    def self.tokens = (themed_tokens + fixed_tokens).map { |name| "--th-#{name}" }

    # The default template a theme's `components/<path>.html.erb` replaces:
    # the CMS's own under `root`, else the registered type's component's
    # template (an engine's, beside its source).
    def self.template_for(path, root: Rails.root)
      file = Pathname(root).join("app/components/#{path}.html.erb")
      return file if file.file?

      definition = ::BlockTypes.all.find { |each| each.component && path_of(each.component) == path }
      definition&.component_template || file
    end
```

  `OWN_TOKENS`, `TEMPLATES`, `OWN_PARTIALS`, `COMPONENT_HELPERS`, `HELPERS` and `RICH_TEXT` stay as they are.

- [ ] **Step 4: the readers.**
  - `app/values/theme/check.rb`: in `MAY_HOLD`, `"components holds <component path>.html.erb for the components Theme::Contract.components names"`. In `misplaced`, before the generic message, a template under `components/` that the contract does not name gets the owner's answer 3:

```ruby
      if area == "components" && rest.end_with?(".html.erb")
        return "#{file} replaces the template of #{rest.delete_suffix(".html.erb")}, which no registered block or content type " \
               "hands out: the type it belongs to is not installed. Remove the template from the theme, or install the type."
      end
```

    and the `allowed` branch reads `Contract.components.key?(rest.delete_suffix(".html.erb"))`.
  - `app/values/theme/scaffold.rb`: `written += Contract.components.keys.map { |path| copy(Contract.template_for(path, root: root), target, "components/#{path}.html.erb") }` and `tokens = Contract.tokens.each_slice(4)…`; in the class comment, `Contract.components` for `Contract::COMPONENTS`.
  - `app/components/blocks/image_component.rb:51`: the comment names `Theme::Contract.components`.
  - Then `grep -rn "Contract::COMPONENTS\|Contract::TOKENS\|Contract::THEMED_TOKENS\|Contract::FIXED_TOKENS\|ALLOWED_ACTIONS" app lib config` lists only `held_fields.rb` and `code_limit_controller.js` / `code_field.rb` (Task 4's).

- [ ] **Step 5: the theme prepared after the types (decision 6).** In `config/initializers/theme.rb`, replace the `booted` local and the whole `to_prepare` block (with its comment) by:

```ruby
# Prepared at the END of the registration block in config/initializers/types.rb,
# not here (block types spec, decision 6): the check reads the theme contract,
# and the contract's block lines are read from the registered types. An order
# written in one block is read; one that depended on these two files' names
# was not. What stays here is what is done once at boot (the watched folder,
# the asset paths above) and the flag that tells the boot's prepare from a
# reload's: `after_initialize` runs once, after the boot's own prepare, so the
# flag is false for exactly that first run (`Theme.prepare` says why the two
# differ).
Rails.application.config.x.theme_booted = false
Rails.application.config.after_initialize { Rails.application.config.x.theme_booted = true }
```

  In `config/initializers/types.rb`, as the last lines inside the `to_prepare` block (after the AI providers):

```ruby
  # The site's theme, LAST (block types spec, decision 6): its check reads
  # `Theme::Contract`, whose block lines are the types registered above. The
  # first run raises and every later one does not (`Theme.prepare`);
  # `bin/rails theme:check` is the one boot that does not raise either
  # (`ThemeFolder.checking`).
  Theme.current = Theme.prepare(ThemeFolder.current, reload: Rails.application.config.x.theme_booted || ThemeFolder.checking?)
  # Not under `theme:check`, which says the list itself, once and whole.
  Rails.logger.error("[ContentSpiel] #{Theme.current.refusal.message}") if Theme.current.refusal && !ThemeFolder.checking?
```

  `test/lib/theme_guards_test.rb`: the `ALLOWED` key becomes `"config/initializers/types.rb"` with the regexp `/\A\s*Theme\.current = Theme\.prepare\(ThemeFolder\.current, reload: Rails\.application\.config\.x\.theme_booted \|\| ThemeFolder\.checking\?\)\z/`, and the synthetic sources of its "the guard can fail" tests (lines 85, 97, 114, 121) name `config/initializers/types.rb` and the new line, so each still shows a second swap being found.

- [ ] **Step 6: the tests that read the contract.**
  - `test/values/theme/contract_test.rb`: `registry_components` no longer skips names with a slash (spec: "derived over every registered type, outside ones included"): `blocks = BlockTypes.all.map(&:component)`, `posts` as before over every content type. Every `Theme::Contract::COMPONENTS` becomes `Theme::Contract.components`, `THEMED_TOKENS` `themed_tokens`, `FIXED_TOKENS` `fixed_tokens`, `TOKENS` `tokens`. The message of `assert_every_registered_component_is_listed` says: "Theme::Contract.components has no entry for …: a block type hands that component out without `theme_methods`, so a theme cannot replace its template. Declare `t.theme_methods` in its definition, with the methods its template may call". Update the `marquee` and `gallery` tests' expected texts to that message (the marquee type declares no `theme_methods` and has no written line, so it is still missing: the test still fails as it says). "every listed component has its default template" reads `Theme::Contract.template_for(path)`. The token test keeps reading `tokens.css` for now (Task 3 derives it).
  - `test/values/theme/check_test.rb`: line 41 reads `Theme::Contract.components.keys`. Add:

```ruby
  # The owner's answer 3 (block types spec): a gem removed from a site leaves
  # its theme's template of the gem's block behind, and the check refuses it
  # by name, at the image's build, and says what to do.
  test "a template of a component no registered type hands out is refused by name, and the message says to remove it or install the type" do
    with_theme_copy do |dir|
      dir.join("components/blocks").mkpath
      dir.join("components/blocks/marquee_component.html.erb").write("<p>marquee</p>")

      problems = Theme::Check.problems(ThemeFolder.new(dir))

      assert_includes problems, "components/blocks/marquee_component.html.erb replaces the template of blocks/marquee_component, " \
                                "which no registered block or content type hands out: the type it belongs to is not installed. " \
                                "Remove the template from the theme, or install the type."
    end
  end
```

    Any existing expectation in `check_test.rb` of the generic "is not part of the theme contract" text for a misspelt `components/…html.erb` is updated to the new text (a misspelt component template is exactly "a component nobody hands out"); a misspelt file that is not an `.html.erb` keeps the generic text.
  - `test/values/theme/scaffold_test.rb` (lines 75, 83, 90, 110, 132), `test/integration/theme_pages_test.rb:515`, `test/lib/theming_reference_test.rb`: the methods for the constants. `theming_reference_test.rb` holds the reference's tables **to the ledger** (spec, "Tests"): the tokens table against `(ContractLedger::THEMED_TOKENS + ContractLedger::FIXED_TOKENS).map { "--th-#{_1}" }`, the components table against `ContractLedger::COMPONENTS`, the Code section against `ContractLedger::COMPONENTS.fetch("blocks/code_component")`.
  - `test/integration/theme_pages_test.rb:329-390`: the comment above the resets says the theme is prepared last in the types' block (`config/initializers/types.rb`); both literal lists become derived: `names = BlockTypes.names` before the resets, and `assert_equal names, BlockTypes.names` after the reload.

- [ ] **Step 7: the reference.** In `docs/reference/theming.md`, every `Theme::Contract::COMPONENTS` / `THEMED_TOKENS` / `FIXED_TOKENS` / `TOKENS` becomes the method, with one sentence where the contract is introduced ("The contract"): the block types' lines and tokens are read from their declarations, the built-ins' part is held by the ledger, the tables below are written by hand and held to the ledger by `theming_reference_test.rb`. Lines 49 and 82 ("`Theme.load`, in the `to_prepare` of `config/initializers/theme.rb`"; "filled by a block that runs after the theme's"): the theme is prepared last in `config/initializers/types.rb`'s block, after the types it checks against, and `Theme.prepare` still does not raise on a reload because a raise would end the reload's prepare chain (the slots' and any later block). Add `config/initializers/types.rb` to the `> Describes:` line.

- [ ] **Step 8: run.**

```sh
PGGSSENCMODE=disable bin/rails test test/values/theme test/lib/theming_reference_test.rb test/lib/theme_guards_test.rb test/lib/dependency_direction_test.rb test/integration/theme_pages_test.rb test/lib/production_boot_test.rb test/values/theme_test.rb
```

  Expected: 0 failures, 0 errors; the ledger green proves the derived contract is today's names in today's order, and the scaffold's byte-for-byte test proves `theme:new` writes what it wrote.

- [ ] **Step 9: commit.**

```bash
git add app/values/theme config/initializers/types.rb config/initializers/theme.rb app/components/blocks/image_component.rb docs/reference/theming.md test/support/contract_ledger.rb test/test_helper.rb test/values/theme test/lib/theming_reference_test.rb test/lib/theme_guards_test.rb test/integration/theme_pages_test.rb
git commit -m "ref: the theme contract's block lines are read from the registry, held by a ledger, and the theme is prepared after the types

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 3: the stylesheet build imports each type's stylesheet

**Files:**
- Modify: `lib/theme_css.rb` (`entry`, `write_entry`, `build`, `watch`, `watched`, `keep_stamped`, `build_for_watch`, `sources_glance`, `current_entry?`, the module comment), `lib/tasks/theme_css.rake`, `app/models/block_types.rb`, `docs/reference/theming.md` ("The stylesheet: `ThemeCss`")
- Modify tests: `test/lib/theme_css_test.rb`, `test/integration/design_tokens_test.rb`, `test/values/theme/contract_test.rb` (the colour-literal test's stylesheet list; the token test)

**Interfaces:**
- Consumes: `definition.stylesheet_path(root:)`, `definition.component_template` (Task 1).
- Produces:

```ruby
ThemeCss::Block                     # Data.define(:stylesheet, :source): absolute Pathnames, either may be nil
ThemeCss.entry(folder, root:, blocks: [])        # String
ThemeCss.build(folder, root:, executable:, blocks: [])
ThemeCss.watch(folder, root:, executable:, blocks: [], every: 1, log: …)
ThemeCss.sources_glance(folder, root:, blocks: [])
BlockTypes.theme_css_blocks(root: Rails.root)    # Array<ThemeCss::Block>, registration order
```

- [ ] **Step 1: write the failing tests.** In `test/lib/theme_css_test.rb`:

```ruby
  # Block types spec, decision 7, and the owner's answer 4: the default
  # theme's own file first (its tokens, prose and sections), then each
  # registered type's stylesheet once, in registration order, then the
  # theme's; a component outside app/components/blocks (an engine's) has its
  # folder scanned, and an outside stylesheet's folder is watched.
  test "the entry imports the default theme, each registered stylesheet once in registration order, then the theme's, and scans an outside component's folder" do
    Dir.mktmpdir("gem") do |dir|
      gem = Pathname(dir)
      gem.join("album.css").write("")
      default = ROOT.join("app/assets/tailwind/themes/default")
      blocks = [
        ThemeCss::Block.new(stylesheet: default.join("code.css"), source: nil),
        ThemeCss::Block.new(stylesheet: nil, source: nil),
        ThemeCss::Block.new(stylesheet: gem.join("album.css"), source: gem),
        ThemeCss::Block.new(stylesheet: default.join("code.css"), source: nil)
      ]
      relative = ->(path) { Pathname(path).relative_path_from(ROOT.join("tmp/theme")).to_s }

      assert_equal <<~CSS, ThemeCss.entry(ThemeFolder.new(PLAIN), root: ROOT, blocks: blocks)
        @import "../../app/assets/tailwind/themes/default/theme.css";
        @import "../../app/assets/tailwind/themes/default/code.css";
        @import "#{relative.(gem.join("album.css"))}";
        @import "../../test/fixtures/themes/plain/assets/stylesheets/theme.css";
        @source "../../app/assets/tailwind/themes/default";
        @source "#{relative.(gem)}";
        @source "../../test/fixtures/themes/plain/assets/stylesheets";
        @source "../../test/fixtures/themes/plain/views";
        @source "../../test/fixtures/themes/plain/components";
        @source "../../test/fixtures/themes/plain/javascript";
      CSS
    end
  end

  # Review focus 4: a theme re-colours a block by declaring its token again,
  # which works only while the theme's stylesheet comes last.
  test "a theme's stylesheet is imported after every type's, so a block token it declares again wins" do
    imports = ThemeCss.entry(ThemeFolder.new(PLAIN), root: ROOT, blocks: BlockTypes.theme_css_blocks).scan(/^@import "([^"]+)";$/).flatten

    assert_equal "../../test/fixtures/themes/plain/assets/stylesheets/theme.css", imports.last
    assert_equal "../../app/assets/tailwind/themes/default/theme.css", imports.first
  end

  test "a stylesheet the entry imports is watched: a change to it is a change of the sources" do
    Dir.mktmpdir("gem") do |dir|
      sheet = Pathname(dir).join("album.css")
      sheet.write("a {}")
      blocks = [ ThemeCss::Block.new(stylesheet: sheet, source: Pathname(dir)) ]
      before = ThemeCss.sources_glance(ThemeFolder.new(nil), root: ROOT, blocks: blocks)
      sheet.write("a { color: red; }")

      assert_not_equal before, ThemeCss.sources_glance(ThemeFolder.new(nil), root: ROOT, blocks: blocks)
    end
  end
```

  In `test/integration/design_tokens_test.rb`, beside the Code block's stylesheet test (whose `assert_includes … %(@import "./code.css";)` line stays until Task 8):

```ruby
  # Block types spec, "Tests": derived from the registry, so a type's
  # stylesheet is in the build because it declared it, and in it once.
  test "the public stylesheet's entry imports every registered type's stylesheet once, and the default theme's file imports none that a type declares" do
    blocks = BlockTypes.theme_css_blocks
    entry = ThemeCss.entry(ThemeFolder.new(nil), root: Rails.root, blocks: blocks)
    theme_css = Rails.root.join(ThemeCss::DEFAULT).read

    blocks.filter_map(&:stylesheet).each do |path|
      relative = path.relative_path_from(Rails.root.join(ThemeCss::ENTRY).dirname).to_s
      assert_equal 1, entry.scan(%(@import "#{relative}";)).size, "#{path.basename} is imported once by the entry"
      assert_not_includes theme_css, %(@import "./#{path.basename}";), "#{path.basename} is a type's: the entry imports it, not theme.css"
    end
  end
```

  In `test/values/theme/contract_test.rb`, the colour-literal test's list becomes derived: `styles = (Rails.root.glob("app/assets/tailwind/themes/default/*.css") - [ TOKENS_CSS ] + BlockTypes.all.filter_map(&:stylesheet_path)).uniq` (today the same four files). The token test ("every token is defined, a themed one for light and for dark, and no other --th- name is") is renamed "every declared token is defined, a themed one for light and for dark, and no --th- name is undeclared" and reads, besides `tokens.css` for the built-ins (as it does), each registered type with an owner's own stylesheet for that type's tokens: its three blocks (`:root, [data-theme="light"]`, `[data-theme="dark"]`, `:root`) must define exactly its `themed_tokens` (light and dark) and `fixed_tokens`. Today no type has an owner, so this half is exercised from Task 6 on (its gallery fixture).

- [ ] **Step 2: run them.** `PGGSSENCMODE=disable bin/rails test test/lib/theme_css_test.rb test/integration/design_tokens_test.rb`. Expected: errors, `NameError: uninitialized constant ThemeCss::Block` and `NoMethodError: undefined method 'theme_css_blocks'`.

- [ ] **Step 3: implement `lib/theme_css.rb`.**
  - Below the constants:

```ruby
  # A registered block type's part of the build (block types spec, decision
  # 7): its stylesheet, imported after the default theme's own and before the
  # theme's, and the folder of its component when that is not
  # app/components/blocks (which the default theme's own `@source` line
  # scans), so utilities in an engine's template are built. Handed in by the
  # caller (lib/tasks/theme_css.rake, from `BlockTypes.theme_css_blocks`):
  # this file loads before the application and reads no registry.
  Block = Data.define(:stylesheet, :source)
```

  - `entry(folder, root:, blocks: [])`: after `imports = [ default ]` and `sources = [ default.dirname ]`, before the theme's lines:

```ruby
    blocks.each do |block|
      next unless block.stylesheet

      imports << Pathname(block.stylesheet)
      sources << Pathname(block.stylesheet).dirname
    end
    sources.concat(blocks.filter_map { |block| block.source && Pathname(block.source) })
```

    and the last line takes `imports.uniq` and `sources.uniq`. A built-in's stylesheet is in the default folder, so its `@source` line is the default's and is not written twice.
  - `blocks:` (default `[]`) is threaded through `write_entry`, `build`, `build_for_watch`, `watch`, `watched`, `keep_stamped` (into its `write_entry` and `current_entry?` calls) and `current_entry?`. `sources_glance(folder, root:, blocks: [])` adds every block stylesheet's file, by name, size and time, to the default theme's (the existing `styles` list is the default folder; append `blocks.filter_map(&:stylesheet)` stat'ed the same way, deduplicated by path).
  - The module comment's entry diagram gains the line `@import "<a type's stylesheet>";  each registered block type's, in registration order (block types spec, decision 7)` between the two imports, and one paragraph: the default theme's own stylesheets come first by this fixed rule whatever the registration order (the owner's answer 4); `theme_css:watch` reads the types once when it starts, so a new type's stylesheet needs the watch restarted.

- [ ] **Step 4: implement the caller.** `app/models/block_types.rb`:

```ruby
  # What the public stylesheet's build needs of the registered types, as
  # data for lib/theme_css.rb (block types spec, decision 7): each type's
  # stylesheet, and its component's folder where that is not
  # app/components/blocks.
  def self.theme_css_blocks(root: Rails.root)
    scanned = Pathname(root).join("app/components/blocks")
    all.map do |definition|
      folder = definition.component_template&.dirname
      ThemeCss::Block.new(stylesheet: definition.stylesheet_path(root: root), source: (folder unless folder.nil? || folder == scanned))
    end
  end
```

  `lib/tasks/theme_css.rake`: `ThemeCss.build(ThemeFolder.current, root: Rails.root, executable: Tailwindcss::Ruby.executable, blocks: BlockTypes.theme_css_blocks)` and the same keyword in `watch`. The rake file's top comment: the entry also holds each registered type's stylesheet.

- [ ] **Step 5: the reference.** `docs/reference/theming.md`, "The stylesheet: `ThemeCss`": the entry with the types' stylesheets between the two imports, the fixed order and why (the owner's answer 4), what `BlockTypes.theme_css_blocks` hands over and why `lib/` does not read the registry, and that the `@theme inline` mapping stays hand-written for the shared tokens (a type's tokens are not utilities; one that wants one writes its own `@theme inline` in its stylesheet).

- [ ] **Step 6: run.** `PGGSSENCMODE=disable bin/rails test test/lib/theme_css_test.rb test/integration/design_tokens_test.rb test/values/theme test/lib/tailwind_sources_test.rb`. Expected: 0 failures, 0 errors.

- [ ] **Step 7: the stylesheet is the same (no test may run meanwhile).**

```sh
bin/rails tailwindcss:build
cmp app/assets/builds/theme.css "$SNAP/theme.before.css" && echo SAME
```

  Expected: `SAME` (no type declares a stylesheet yet, so the entry is today's). `$SNAP` is the folder the controller named in Task 0; ask the controller for it. A difference is reported to the controller with `diff <(tr '}' '\n' < "$SNAP/theme.before.css") <(tr '}' '\n' < app/assets/builds/theme.css)`, not committed.

- [ ] **Step 8: commit.**

```bash
git add lib/theme_css.rb lib/tasks/theme_css.rake app/models/block_types.rb docs/reference/theming.md test/lib/theme_css_test.rb test/integration/design_tokens_test.rb test/values/theme/contract_test.rb
git commit -m "ref: the public stylesheet's entry imports each registered block type's stylesheet, after the default theme's and before the theme's

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 4: the tile draws a type's summary, and the held form's allow-list reads the types

**Files:**
- Modify: `app/components/admin/editor_screen/tile_summary_component.rb`, `app/components/admin/editor_screen/held_fields.rb`, `app/components/admin/fields/code_field.rb:84` and `app/javascript/controllers/admin/editor/code_limit_controller.js:12` (comments naming `ALLOWED_ACTIONS`), `docs/reference/live-editing.md` and `docs/reference/content-blocks-and-types.md` (each mention of `ALLOWED_ACTIONS` and of the tile's per-type branch)
- Modify tests: `test/components/admin/editor_screen/tile_summary_component_test.rb`, `test/components/admin/editor_screen/held_fields_test.rb`, `test/integration/admin/editing_test.rb:437`, `test/system/admin/editing_holds_test.rb:751`

**Interfaces:**
- Consumes: `definition.summary`, `definition.read_only_actions` (Task 1).
- Produces:

```ruby
Admin::EditorScreen::TileSummaryComponent::LOOKS   # { text: nil, word: nil, mono: "font-cs-mono", hint: "text-meta" }
# A summary part: [:text, String] | [:mono, String] | [:word, Symbol key, **values] | [:hint, Symbol key, **values]
# :word and :hint are looked up under admin.components.editor_screen.tile_summary.types.<type, "/" as ".">.<key>
Admin::EditorScreen::HeldFields::CMS_ACTIONS       # the CMS's four
Admin::EditorScreen::HeldFields::WRITTEN_TYPE_ACTIONS  # transition: %w[admin--editor--code-limit#update], deleted in Task 8
Admin::EditorScreen::HeldFields.allowed_actions    # Array<String>, frozen: CMS_ACTIONS + WRITTEN_TYPE_ACTIONS + every type's read_only_actions, uniq
Admin::EditorScreen::HeldFields.rules              # { allowed_actions: allowed_actions, readonly_types:, hidden_types: }
```

- [ ] **Step 1: write the failing tests.** In `test/components/admin/editor_screen/tile_summary_component_test.rb`:

```ruby
  # Block types spec, decision 8: a type's tile line is data its definition
  # answers, drawn here; its words are CS Studio's, under the type's own
  # scope (a slash in the name read as a dot). Parts of one look stand as
  # one: the line's markup is what it was when the tile wrote them itself.
  test "a type's summary is drawn part by part: text and words plain, code in the monospace face, a hint in the meta colour" do
    I18n.backend.store_translations(:en, admin: { components: { editor_screen: { tile_summary: { types: { test: { quote: { by: "by %{who}", none: "Nothing yet" } } } } } } })
    with_test_types do
      BlockTypes.fetch("test/quote").summary(->(block, locale:) { [ [ :word, :by, { who: "Ada" } ], [ :text, " · " ], [ :mono, "q = 1" ] ] })
      render_summary block("test/quote")
      assert_equal "by Ada · q = 1", page.find(line).text
      assert_selector "#{line} > span.font-cs-mono", exact_text: "q = 1", count: 1
      assert_equal "by Ada · ", Nokogiri::HTML5.fragment(rendered_content).at_css(line).children.first.text, "the plain parts are one text, as before"

      BlockTypes.fetch("test/quote").summary(->(block, locale:) { [ [ :hint, :none ] ] })
      render_summary block("test/quote")
      assert_selector "#{line} > span.text-meta", exact_text: "Nothing yet"
    end
  ensure
    I18n.reload!
  end

  test "a summary that answers a part of no known kind raises and names the kinds" do
    with_test_types do
      BlockTypes.fetch("test/quote").summary(->(block, locale:) { [ [ :bold, "x" ] ] })
      error = assert_raises(ArgumentError) { render_summary block("test/quote") }
      assert_includes error.message, "text, word, mono, hint"
    end
  end
```

  (`block`, `render_summary` and `line` are the file's own helpers; if `block` builds through `page.content_blocks.build`, a `test/quote` block needs only `block_type`. Add `include TestTypes` to the class if it is not there; the same in `held_fields_test.rb` for the test below.)

  In `test/components/admin/editor_screen/held_fields_test.rb`, replace the rules test and add:

```ruby
  # The CMS's own four, decided HERE (the file's rule: a new survivor fails
  # until someone classifies it). A type's own read-only actions are its
  # definition's (block types spec, decision 10), checked against its
  # controller file below.
  CMS = %w[
    admin--editor--slug-preview#update
    admin--rich-text--editor#containFocus
    admin--ui--menu#select
    admin--ui--menu#close
  ].freeze

  test "the rules the browser's freeze reads are this module's own lists, and nothing else" do
    rules = Admin::EditorScreen::HeldFields.rules

    assert_equal %i[allowed_actions hidden_types readonly_types], rules.keys.sort
    assert_equal Admin::EditorScreen::HeldFields.allowed_actions, rules[:allowed_actions]
    assert_same Admin::EditorScreen::HeldFields::READONLY_TYPES, rules[:readonly_types]
    assert_same Admin::EditorScreen::HeldFields::HIDDEN_TYPES, rules[:hidden_types]
  end

  test "the allow-list is the CMS's four and every type's declared read-only actions, each a method of a controller file" do
    assert_equal CMS, Admin::EditorScreen::HeldFields::CMS_ACTIONS
    declared = BlockTypes.all.flat_map(&:read_only_actions)
    assert_equal (CMS + Admin::EditorScreen::HeldFields::WRITTEN_TYPE_ACTIONS + declared).uniq, Admin::EditorScreen::HeldFields.allowed_actions

    (declared + Admin::EditorScreen::HeldFields::WRITTEN_TYPE_ACTIONS).each do |action|
      identifier, method = action.split("#")
      file = Rails.root.join("app/javascript/controllers", "#{identifier.split("--").join("/").tr("-", "_")}_controller.js")
      assert file.file?, "#{action} names no controller file (#{file.relative_path_from(Rails.root)})"
      assert_match(/^\s*(?:async\s+)?#{Regexp.escape(method)}\s*\(/, file.read, "#{action}: the controller defines no #{method}")
    end
  end

  test "an action a type declares survives in a held form, and only while the type declares it" do
    html = %(<input type="text" name="block[settings][text]" data-action="input->admin--ui--char-count#update">)
    assert_empty Nokogiri::HTML5.fragment(held(html)).css("[data-action]")

    with_test_types do
      BlockTypes.fetch("test/quote").read_only_actions("admin--ui--char-count#update")
      assert_equal "input->admin--ui--char-count#update", Nokogiri::HTML5.fragment(held(html)).at_css("input")["data-action"]
    end
  end
```

  The file's `ALLOWED` list (used by `assert_survives`) becomes `ALLOWED = (CMS.map { … with its event, as the file writes them today } + [ "input->admin--editor--code-limit#update" ]).freeze` until Task 8, where the Code line comes from the type's declaration: write it as the four event-qualified CMS tokens plus `"input->admin--editor--code-limit#update"` with the comment "the Code type's, until it declares it (block types plan, Task 8)".

  `test/integration/admin/editing_test.rb:437` and `test/system/admin/editing_holds_test.rb:751` read `Admin::EditorScreen::HeldFields.allowed_actions`.

- [ ] **Step 2: run them.** `PGGSSENCMODE=disable bin/rails test test/components/admin/editor_screen/tile_summary_component_test.rb test/components/admin/editor_screen/held_fields_test.rb`. Expected: failures and errors (`NoMethodError: undefined method 'allowed_actions'`; the summary is not drawn).

- [ ] **Step 3: implement the tile.** In `TileSummaryComponent`, extend the class comment ("WHAT THE LINE IS"): a type that declares `summary` answers its own line as parts (decision 8); a type without one keeps the rules from the columns it uses. Add:

```ruby
      # A summary part's kind => the class it is drawn in (nil: plain). The
      # set is closed; a type's summary answers nothing else (block types
      # spec, decision 8; `:hint` is the meta colour the Code block's "Empty"
      # was drawn in before the line moved into the type).
      LOOKS = { text: nil, word: nil, mono: "font-cs-mono", hint: "text-meta" }.freeze
```

  In `content`, as the second branch (after `definition.nil?`): `elsif definition.summary then drawn(definition.summary.call(block, locale: locale))`. The `capability?(:code)` and `capability?(:lists_posts)` branches stay until Tasks 8 and 9. Then:

```ruby
      # A type's parts as `[text, class]`, its words looked up under the
      # type's own scope, and parts of one look joined, so the markup is what
      # the tile drew when it wrote the line itself.
      def drawn(parts)
        Array(parts).map do |kind, value, values = {}|
          look = LOOKS.fetch(kind) { raise ArgumentError, "#{block.block_type}'s summary answered a part of kind #{kind.inspect}: a part is one of #{LOOKS.keys.join(", ")}" }
          [ %i[word hint].include?(kind) ? word(value, **values) : value.to_s, look ]
        end.slice_when { |a, b| a.last != b.last }.map { |run| [ run.map(&:first).join, run.first.last ] }
      end

      def word(key, **values)
        t("admin.components.editor_screen.tile_summary.types.#{block.block_type.tr("/", ".")}.#{key}", **values)
      end
```

  `parts` already accepts an Array from `content`.

- [ ] **Step 4: implement the allow-list.** In `held_fields.rb`, replace `ALLOWED_ACTIONS` (and update its comment: the CMS's own here, a type's in its definition, reviewed with the type):

```ruby
      # `identifier#method` of the CMS's own actions that survive: reading, or
      # moving focus. A block type's own are its definition's
      # `read_only_actions` (block types spec, decision 10).
      CMS_ACTIONS = %w[
        admin--editor--slug-preview#update
        admin--rich-text--editor#containFocus
        admin--ui--menu#select
        admin--ui--menu#close
      ].freeze
      # THE TRANSITION (block types plan, Task 8 deletes it): the Code type's
      # counter, until the type declares it.
      WRITTEN_TYPE_ACTIONS = %w[admin--editor--code-limit#update].freeze

      def self.allowed_actions = (CMS_ACTIONS + WRITTEN_TYPE_ACTIONS + ::BlockTypes.all.flat_map(&:read_only_actions)).uniq.freeze

      def self.rules = { allowed_actions: allowed_actions, readonly_types: READONLY_TYPES, hidden_types: HIDDEN_TYPES }
```

  Line 97 reads a local `allowed = allowed_actions` taken once per call, not the constant. The two comments in `code_field.rb` and `code_limit_controller.js` name `HeldFields.allowed_actions` and the type's `read_only_actions`.

- [ ] **Step 5: the references.** `docs/reference/live-editing.md` ("A form someone else holds") and `docs/reference/content-blocks-and-types.md` ("Blocks in CS Studio", the tile): `HeldFields.allowed_actions`, the CMS's four plus each type's `read_only_actions`; the tile draws a type's `summary` parts (the four kinds, the words' scope), else its rules from the columns. The recipe itself is Task 12's.

- [ ] **Step 6: run.**

```sh
PGGSSENCMODE=disable bin/rails test test/components/admin/editor_screen test/integration/admin/editing_test.rb test/integration/admin/content_blocks_test.rb test/lib/source_layout_test.rb test/lib/admin_i18n_test.rb
bin/rails tailwindcss:build && bin/rails theme_css:build
PGGSSENCMODE=disable bin/rails test test/system/admin/editing_holds_test.rb
PGGSSENCMODE=disable bin/rails test test/system/admin/editing_held_test.rb
```

  Expected: 0 failures, 0 errors. Every pre-existing tile and held-form test passes with its expectations unchanged: that is this task's proof that an editor sees nothing new.

- [ ] **Step 7: commit.**

```bash
git add app/components/admin/editor_screen/tile_summary_component.rb app/components/admin/editor_screen/held_fields.rb app/components/admin/fields/code_field.rb app/javascript/controllers/admin/editor/code_limit_controller.js docs/reference/live-editing.md docs/reference/content-blocks-and-types.md test/components/admin/editor_screen test/integration/admin/editing_test.rb test/system/admin/editing_holds_test.rb
git commit -m "ref: the tile draws a block type's summary parts, and the held form's allow-list adds each type's read-only actions

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 5: the sample helper and the shared tests that read it

**Files:**
- Create: `test/support/block_samples.rb`, `test/integration/block_samples_test.rb`, `test/components/admin/editor_screen/block_samples_card_test.rb`
- Modify: `test/test_helper.rb` (require and include), `test/support/test_types.rb` (`test/quote` gains `theme_methods` and a `sample`), `test/integration/public_canary_test.rb`, `test/values/theme/scaffold_test.rb`, `test/services/translation_state_parity_test.rb`

**Interfaces:**
- Consumes: `definition.sample` (`Sample#settings`, `#translations`, `#body`, `#image`, `#shows`), `definition.fields`, `definition.uses_columns`, `capability?(:container)`.
- Produces (in every `ActiveSupport::TestCase` and integration test, through `test_helper.rb`):

```ruby
BlockSamples#sampled_types                       # Array of definitions with a sample (transition: Task 10 makes it BlockTypes.all)
BlockSamples#sample_block(page, type, section: nil)   # => the saved ContentBlock, through ContentBlocks::Save; records the type
BlockSamples#sample_every_type(page)             # every sampled type at the top level; each container's sample holds every other in its first column
BlockSamples#assert_every_type_built(names = sampled_types.map(&:name))
```

- [ ] **Step 1: the helper,** `test/support/block_samples.rb`:

```ruby
# One block of a type, filled from its definition's sample (block types spec,
# decision 14), so every shared test builds it the same way and a type nobody
# wrote a row for is in every shared test from the day it is registered.
#
# Written through `ContentBlocks::Save`, as an editor's save is: a translated
# schema field goes in its language's `settings`, `caption` and `alt` are the
# columns, `body` is Markdown written in the default language, `image: true`
# attaches a new library image.
#
# `assert_every_type_built` ends each shared test: it compares the types this
# test built with the registry, in the test and not after the run, because
# the suite runs in parallel workers.
module BlockSamples
  # THE TRANSITION (block types plan, Task 10 makes this BlockTypes.all): the
  # types that declare a sample yet.
  def sampled_types = BlockTypes.all.select(&:sample)

  def sample_block(page, type, section: nil)
    definition = BlockTypes.fetch(type)
    sample = definition.sample or flunk("#{definition.name} declares no sample")
    fields = definition.fields.map(&:name)

    default = Locales.default
    # A translated schema field of the default language is saved with the
    # untranslated ones, as the editor's default-language card sends it; in
    # another language it goes in that language's `settings`.
    own_default = sample.translations.fetch(default, {}).transform_keys(&:to_s).slice(*fields)
    attributes = { block_type: definition.name, settings: sample.settings.merge(own_default) }
    attributes.merge!(section_id: section.id, section_column: 1) if section
    attributes[:media_asset_id] = create_media_asset.id if sample.image

    translations = sample.translations.to_h do |locale, values|
      values = values.transform_keys(&:to_s)
      own = locale == default ? {} : values.slice(*fields)
      [ locale, values.except(*fields).transform_keys(&:to_sym).merge(own.any? ? { settings: own } : {}) ]
    end
    translations[default] = (translations[default] || {}).merge(body: rich_doc(sample.body)) if sample.body

    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: attributes, translations: translations)
    assert result.ok?, "the sample of #{definition.name} does not save: #{result.errors.to_sentence}"
    (@built_block_types ||= []) << definition.name
    result.record
  end

  def sample_every_type(page)
    containers, others = sampled_types.partition { |definition| definition.capability?(:container) }
    others.each { |definition| sample_block(page, definition.name) }
    containers.each do |container|
      section = sample_block(page, container.name)
      others.each { |definition| sample_block(page, definition.name, section: section) }
    end
  end

  def assert_every_type_built(names = sampled_types.map(&:name))
    missing = names - Array(@built_block_types).uniq
    assert_empty missing, "this shared test built no block of #{missing.join(", ")}: build every type with sample_block or sample_every_type"
  end
end
```

  `test/test_helper.rb`: `require_relative "support/block_samples"` beside `support/test_types`, and `include BlockSamples` directly below `include ContentHelper` (inside `ActiveSupport::TestCase`, so integration tests have it too). `TestTypes` is NOT included globally (each test class that calls `with_test_types` writes `include TestTypes`): every new test file below that calls it says so.

- [ ] **Step 2: `test/quote` declares its two lines.** In `test/support/test_types.rb`, inside the `test/quote` registration:

```ruby
      t.theme_methods :block, :page, :settings
      t.sample settings: { "cite" => "https://example.com/source" },
               translations: { "en" => { text: "A line worth quoting" } },
               shows: [ "A line worth quoting" ]
```

- [ ] **Step 3: write the derived public smoke test,** `test/integration/block_samples_test.rb`:

```ruby
require "test_helper"

# THE DERIVED PUBLIC SMOKE TEST (block types spec, "New guards"): every
# registered block type's sample saves, publishes and draws its words, at the
# top level and in a column, and the page draws them from the published copy.
# A type joins this by declaring its sample; nobody writes a row for it.
# `test/quote` (test/support/test_types.rb) is registered too, so the test
# also runs a type with an owner's name.
class BlockSamplesTest < ActionDispatch::IntegrationTest
  include TestTypes

  CANARY = "SAMPLE-CANARY-41d0".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    create_post(title: "A listed post")
  end

  def path_of(page) = PublicSite::Urls.new.path_for(page.reload, "en")

  test "every registered type has a sample that saves, publishes and draws its words, at the top level and in a column, from the copy" do
    with_test_types do
      page = create_page(title: "Samples")
      sample_every_type(page)
      publish_changes(page)

      get path_of(page)
      assert_response :success
      main = Nokogiri::HTML5(response.body).at_css("main").to_html
      sampled_types.each do |definition|
        definition.sample.shows.each { |text| assert_includes main, text, "#{definition.name}'s sample draws #{text.inspect}" }
      end
      column = Nokogiri::HTML5(response.body).css(".content-section__column").first&.to_html.to_s
      sampled_types.reject { |definition| definition.capability?(:container) }.each do |definition|
        next if sampled_types.none? { |each| each.capability?(:container) }

        definition.sample.shows.each { |text| assert_includes column, text, "#{definition.name}'s sample draws #{text.inspect} in a column" }
      end

      # Around the services and without publishing, as the canary does at
      # full depth: every setting, and the caption where the type uses one.
      page.content_blocks.find_each do |block|
        columns = { settings: block.settings.to_h.transform_values { CANARY } }
        columns[:caption] = { "en" => CANARY } if block.definition&.uses_columns&.include?("caption")
        block.update_columns(columns)
      end
      get path_of(page)
      assert_not_includes response.body, CANARY, "the page is drawn from the copy, not from the rows"

      assert_every_type_built
    end
  end

  # Review focus 3: a sample that leaves a column its type uses empty would
  # let every shared test pass while that column is never compared.
  test "a sample fills every column its type uses and names at least one text the public page shows" do
    with_test_types do
      sampled_types.each do |definition|
        sample = definition.sample
        definition.uses_columns.each do |column|
          filled =
            case column
            when "body" then sample.body.present?
            when "image" then sample.image
            else sample.translations.fetch("en", {}).transform_keys(&:to_s)[column].present?
            end
          assert filled, "#{definition.name}'s sample leaves #{column} empty, so no shared test compares it"
        end
        assert_not_empty sample.shows
      end
    end
  end
end
```

- [ ] **Step 4: write the card's derived test,** `test/components/admin/editor_screen/block_samples_card_test.rb`:

```ruby
require "test_helper"

# The editor half of the derived smoke test (block types spec, "New guards"):
# each registered type's card, drawn from its sample, has a control for every
# field of its schema, and the same card held by someone else
# (`HeldFields`) keeps every name and value it had.
class Admin::EditorScreen::BlockSamplesCardTest < ActiveSupport::TestCase
  include ComponentTestHelper
  include TestTypes

  def named(html) = Nokogiri::HTML5.fragment(html).css("[name]").map { |node| [ node["name"], node["value"] || node.text ] }

  test "every type's card draws a control for each field of its schema, and its held form keeps every name and value" do
    with_test_types do
      page = create_page(title: "Cards")
      sampled_types.each do |definition|
        block = sample_block(page, definition.name)
        as_owner { render_inline Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en", editable: true) }
        html = rendered_content

        definition.fields.reject(&:group?).each do |field|
          assert Nokogiri::HTML5.fragment(html).at_css("[name*='[#{field.name}]']"), "#{definition.name}'s card has no control for #{field.name}"
        end
        assert_equal named(html), named(Admin::EditorScreen::HeldFields.call(html)), "#{definition.name}'s held form changed a name or a value"
      end
      assert_every_type_built
    end
  end
end
```

- [ ] **Step 5: the shared tests read the samples.**
  - `test/integration/public_canary_test.rb`, in `build_site` after `@resume`: `@samples = live_page("Samples") { |page| sample_every_type(page) }`. At the end of the test that builds the site and overwrites the rows (the one that calls `build_site`): `assert_every_type_built`. The canary overwrites every live block's rows generically, so the samples page is covered with nothing more.
  - `test/values/theme/scaffold_test.rb`, in `setup` after `wide_page`: `@samples = create_page(title: "Samples"); sample_every_type(@samples); publish_changes(@samples)`. In the byte-for-byte test: `"/samples"` joins `paths`, the words hash gains `"/samples" => sampled_types.flat_map { |definition| definition.sample.shows }`, and the test ends with `assert_every_type_built`. Its name gains "and a sample of every type".
  - `test/services/translation_state_parity_test.rb` (add `include TestTypes` to the class if it is not there), a derived case after the Code block's:

```ruby
  # Block types spec, "Tests": every type whose sample has translations is
  # tracked like any block, the stored state equal to a recomputation, when
  # the sample's values are written in a second language and then changed in
  # the first.
  test "every type whose sample has translations keeps the stored state equal to a recomputation" do
    as_owner do
      with_test_types do
        typed = sampled_types.select { |definition| definition.sample.translations.any? }
        typed.each do |definition|
          page = create_page(title: "Parity #{definition.name}", translations: { "de" => { title: "Paritat" }, "es" => { title: "Paridad" } })
          block = sample_block(page, definition.name)
          assert_parity page

          english = definition.sample.translations.fetch("en").transform_keys(&:to_s)
          own = english.slice(*definition.fields.map(&:name))
          german = english.except(*own.keys).transform_keys(&:to_sym).merge(own.any? ? { settings: own } : {})
          assert ContentBlocks::Save.call(block, translations: { "de" => german }).ok?
          assert_parity page
        end
        assert_every_type_built(typed.map(&:name))
      end
    end
  end
```

- [ ] **Step 6: run.**

```sh
PGGSSENCMODE=disable bin/rails test test/integration/block_samples_test.rb test/components/admin/editor_screen/block_samples_card_test.rb test/integration/public_canary_test.rb test/values/theme/scaffold_test.rb test/services/translation_state_parity_test.rb test/models test/integration/open_types_test.rb
```

  Expected: 0 failures, 0 errors. Until Task 7 only `test/quote` has a sample, so the canary's and the scaffold's derived parts build nothing yet and pass; the two new files prove the helper on `test/quote`. If `ComponentTestHelper` and `with_test_types` clash with the card test's `as_owner` (a `Current` set inside a render), report it to the controller rather than changing the helper.

- [ ] **Step 7: commit.**

```bash
git add test/support/block_samples.rb test/support/test_types.rb test/test_helper.rb test/integration/block_samples_test.rb test/components/admin/editor_screen/block_samples_card_test.rb test/integration/public_canary_test.rb test/values/theme/scaffold_test.rb test/services/translation_state_parity_test.rb
git commit -m "test: the shared tests build one block of every type from its sample, and say which type they missed

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 6: the registration hook for outside types

**Files:**
- Create: `lib/content_spiel/plugins.rb`, `test/lib/content_spiel/plugins_test.rb`, `test/support/gallery_album.rb`, `test/fixtures/block_types/gallery/album_component.rb`, `test/fixtures/block_types/gallery/album_component.html.erb`, `test/fixtures/block_types/gallery/album.css`
- Modify: `config/application.rb`, `config/initializers/types.rb`, `app/models/content_model/block_type_definition.rb` (`finalize!`), `test/test_helper.rb`, `test/models/content_model/block_type_definition_test.rb`, `test/lib/admin_namespace_shadow_test.rb`, `test/lib/public_readers_test.rb`, `docs/reference/theming.md` (outside types' lines), `docs/reference/content-blocks-and-types.md` (a short section "Block types from outside")

**Interfaces:**
- Consumes: `BlockTypes.register`, `ContentModel::DuplicateType`, `definition.owner`, `stylesheet_path`, `themed_tokens`, `fixed_tokens` (Task 1), `Theme::Contract` (Task 2), `BlockTypes.theme_css_blocks` (Task 3), `sample_block` (Task 5).
- Produces:

```ruby
ContentSpiel::Plugins.block_types { |types| types.register("owner/name") { |t| … } }  # => the kept Hook
ContentSpiel::Plugins.register_block_types(registry)   # called by config/initializers/types.rb after the built-ins
ContentSpiel::Plugins.remove(hook)                     # test seam
ContentSpiel::Plugins::Hook                            # Data.define(:block, :location)
ContentSpiel::Plugins::Registrar#register(name, &definition)
GalleryAlbum#with_gallery_album { … }                  # test/support/gallery_album.rb: gallery/album registered through the hook
ContentModel::BlockTypeDefinition::COLOUR_LITERAL      # /#\h{3,8}\b|\brgba?\(|\bhsla?\(|\boklch\(/
```

- [ ] **Step 1: the fixture type** (an engine's files, in a folder of their own, loaded only by the tests that register it). `test/fixtures/block_types/gallery/album_component.rb`:

```ruby
# An outside block type's component, as an engine would ship it, for the
# hook's tests (block types spec, decision 11). Not autoloaded: required by
# test/support/gallery_album.rb.
module Gallery
  class AlbumComponent < ApplicationComponent
    def initialize(block:, page:)
      @block = block
      @page = page
    end

    def render? = title.present?

    private

    attr_reader :block, :page

    def title = block.settings_object(fallback: true)&.title
  end
end
```

  `album_component.html.erb`:

```erb
<figure class="content-block content-block--gallery-album"><figcaption><%= title %></figcaption></figure>
```

  `album.css`:

```css
/* The test album's tokens, defined from the theme's base tokens only
   (block types spec, decision 3): a theme that re-colours its base
   re-colours this block. */
:root, [data-theme="light"] { --th-gallery-frame: var(--th-line); }
[data-theme="dark"] { --th-gallery-frame: var(--th-line-strong); }
.content-block--gallery-album { border: 1px solid var(--th-gallery-frame); }
```

  `test/support/gallery_album.rb`:

```ruby
# `with_gallery_album { … }`: `gallery/album`, an outside type, registered
# through `ContentSpiel::Plugins.block_types` as an engine registers one, for
# the block; the hook is removed and the registries prepared again afterwards.
module GalleryAlbum
  ROOT = Rails.root.join("test/fixtures/block_types/gallery")

  def with_gallery_album
    require ROOT.join("album_component").to_s
    hook = ContentSpiel::Plugins.block_types do |types|
      types.register "gallery/album" do |t|
        t.label "Album"
        t.field :title, :string, translated: true
        t.component Gallery::AlbumComponent
        t.theme_methods :block, :page, :title
        t.tokens themed: %w[gallery-frame]
        t.stylesheet ROOT.join("album.css")
        t.sample translations: { "en" => { title: "Holiday pictures" } }, shows: [ "Holiday pictures" ]
      end
    end
    Rails.application.reloader.prepare!
    yield hook
  ensure
    ContentSpiel::Plugins.remove(hook) if hook
    Rails.application.reloader.prepare!
  end
end
```

  `test/test_helper.rb`: `require_relative "support/gallery_album"` beside `support/test_types`; a test class that uses it writes `include GalleryAlbum` (as `TestTypes` is included per class).

- [ ] **Step 2: write the failing tests,** `test/lib/content_spiel/plugins_test.rb`:

```ruby
require "test_helper"

# The one registration hook for code outside the CMS (block types spec,
# decision 11). An engine's own `to_prepare` runs before the application's,
# whose first line is `reset!`, so a gem that registered there would be
# wiped on every prepare: the hook KEEPS the block and the application's
# registration block replays it after the built-ins, every time.
class ContentSpiel::PluginsTest < ActionDispatch::IntegrationTest
  include GalleryAlbum

  BUILT_INS = %w[rich_text image code post_list section].freeze

  # The error the next prepare raises for a kept hook; the hook is taken out
  # and the registries prepared again, whatever happened.
  def refusal_of(hook)
    assert_raises(StandardError) { Rails.application.reloader.prepare! }
  ensure
    ContentSpiel::Plugins.remove(hook)
    Rails.application.reloader.prepare!
  end

  test "a type registered through the hook survives a reload, after the built-ins, and the theme check still knows its template" do
    with_gallery_album do
      assert_equal BUILT_INS + %w[gallery/album], BlockTypes.names
      Rails.application.reloader.prepare!
      assert_equal BUILT_INS + %w[gallery/album], BlockTypes.names, "a reload resets the registry and replays the hook"
      assert_equal %w[block page title], Theme::Contract.components.fetch("gallery/album_component")
      assert_includes Theme::Contract.tokens, "--th-gallery-frame"

      with_theme_copy do |dir|
        dir.join("components/gallery").mkpath
        dir.join("components/gallery/album_component.html.erb").write(GalleryAlbum::ROOT.join("album_component.html.erb").read)
        assert_empty Theme::Check.problems(ThemeFolder.new(dir)), "a theme may replace an outside type's template while the type is registered"
      end
    end
  end

  test "a bare name, a second owner in one call and a duplicate are refused, and the message names the place of the call" do
    line = __LINE__ + 1
    bare = ContentSpiel::Plugins.block_types { |types| types.register("album") { |t| TestTypes.declare(t) } }
    error = refusal_of(bare)
    assert_includes error.message, "album"
    assert_includes error.message, "owner/name"
    assert_includes error.message, "#{__FILE__}:#{line}"

    line = __LINE__ + 1
    two = ContentSpiel::Plugins.block_types do |types|
      types.register("gallery/album") { |t| TestTypes.declare(t) }
      types.register("slides/deck") { |t| TestTypes.declare(t) }
    end
    error = refusal_of(two)
    assert_includes error.message, "slides/deck"
    assert_includes error.message, "gallery"
    assert_includes error.message, "#{__FILE__}:#{line}"

    line = __LINE__ + 1
    twice = ContentSpiel::Plugins.block_types { |types| 2.times { types.register("gallery/album") { |t| TestTypes.declare(t) } } }
    error = refusal_of(twice)
    assert_kind_of ContentModel::DuplicateType, error
    assert_includes error.message, "#{__FILE__}:#{line}"
  end

  test "an outside type may not claim :container or :lists_posts" do
    saved = BlockTypes.all.dup
    %i[container lists_posts].each do |capability|
      error = assert_raises(ArgumentError) do
        BlockTypes.register("gallery/band") { |t| TestTypes.declare(t); t.capability capability; t.columns ->(_) { 1 } }
      end
      assert_includes error.message, ":#{capability}"
    end
  ensure
    BlockTypes.reset!
    saved.each { |definition| BlockTypes.registry_put(definition) }
  end

  # Review focus 1, and the owner's answer 3.
  test "a block of an outside type that is no longer registered is dormant: the page answers, the editor names it, the copy stays, and a theme's template of it is refused by name" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    page = nil
    copies = nil
    with_gallery_album do
      page = create_page(title: "Album page")
      sample_block(page, "gallery/album")
      publish_changes(page)
      get PublicSite::Urls.new.path_for(page.reload, "en")
      assert_includes response.body, "Holiday pictures"
      copies = Publishing::Version.where(record_type: "Page", record_id: page.id).pluck(:id, :blocks)
    end

    assert_nil BlockTypes.find("gallery/album")
    get PublicSite::Urls.new.path_for(page.reload, "en")
    assert_response :success
    assert_not_includes response.body, "Holiday pictures"
    sign_in_as users(:one)
    get admin_page_path(page)
    assert_response :success
    assert_includes response.body, "Unavailable type — gallery/album"
    assert_equal copies, Publishing::Version.where(record_type: "Page", record_id: page.id).pluck(:id, :blocks), "removing a gem moves no published copy"

    with_theme_copy do |dir|
      dir.join("components/gallery").mkpath
      dir.join("components/gallery/album_component.html.erb").write("<p>album</p>")
      assert_includes Theme::Check.problems(ThemeFolder.new(dir)).join("\n"),
        "components/gallery/album_component.html.erb replaces the template of gallery/album_component, which no registered block or content type hands out"
    end
  end

  test "theme:new copies an outside type's template and names its token; the build imports its stylesheet and scans its folder" do
    with_gallery_album do
      Dir.mktmpdir("theme") do |dir|
        written = Theme::Scaffold.write(File.join(dir, "site-theme"))
        assert_includes written, "components/gallery/album_component.html.erb"
        assert_equal GalleryAlbum::ROOT.join("album_component.html.erb").read, File.read(File.join(dir, "site-theme/components/gallery/album_component.html.erb"))
        assert_includes File.read(File.join(dir, "site-theme/assets/stylesheets/theme.css")), "--th-gallery-frame"
      end

      entry = ThemeCss.entry(ThemeFolder.new(nil), root: Rails.root, blocks: BlockTypes.theme_css_blocks)
      relative = ->(path) { path.relative_path_from(Rails.root.join("tmp/theme")).to_s }
      assert_includes entry, %(@import "#{relative.(GalleryAlbum::ROOT.join("album.css"))}";)
      assert_includes entry, %(@source "#{relative.(GalleryAlbum::ROOT)}";)
    end
  end
end
```

  In `test/models/content_model/block_type_definition_test.rb` add:

```ruby
  test "an outside type's token names start with its owner, and its stylesheet is an absolute path that holds no colour literal" do
    saved = BlockTypes.all.dup
    error = assert_raises(ArgumentError) { BlockTypes.register("gallery/album") { |t| TestTypes.declare(t); t.tokens themed: %w[frame] } }
    assert_includes error.message, "gallery-"

    error = assert_raises(ArgumentError) { BlockTypes.register("gallery/album") { |t| TestTypes.declare(t); t.stylesheet "album.css" } }
    assert_includes error.message, "absolute"

    Dir.mktmpdir do |dir|
      sheet = Pathname(dir).join("album.css")
      sheet.write(%(:root { --th-gallery-frame: #ff0000; }))
      error = assert_raises(ArgumentError) { BlockTypes.register("gallery/album") { |t| TestTypes.declare(t); t.tokens themed: %w[gallery-frame]; t.stylesheet sheet } }
      assert_includes error.message, "colour"
      assert_includes error.message, "var()"
    end
  ensure
    BlockTypes.reset!
    saved.each { |definition| BlockTypes.registry_put(definition) }
  end
```

  `TestTypes.declare(t)` is defined in Task 10; define it in this task already (Task 10 then only uses it more widely), in `test/support/test_types.rb` inside `module TestTypes`:

```ruby
  # The two lines every block type declares (block types spec, decision 2),
  # for a type a test registers to look at one other thing.
  def self.declare(t)
    t.theme_methods :block, :page
    t.sample shows: [ "content-block" ]
  end
```

  `test/lib/admin_namespace_shadow_test.rb`: `ContentSpiel` joins the names the first test asserts are derived. `test/lib/public_readers_test.rb`: the component folders the guard reads gain the folder of every registered block type's component (`BlockTypes.all.filter_map { |d| d.component_template&.dirname }`, relative to the root where inside it), so an engine's component is in the guard's reach; the constant `COMPONENT_FOLDERS` stays for the four built-in folders, the method that uses it adds the derived ones.

- [ ] **Step 3: run them.** `PGGSSENCMODE=disable bin/rails test test/lib/content_spiel/plugins_test.rb test/models/content_model/block_type_definition_test.rb`. Expected: errors, `NameError: uninitialized constant ContentSpiel::Plugins`.

- [ ] **Step 4: the hook,** `lib/content_spiel/plugins.rb`:

```ruby
# The one registration hook for code outside the CMS (block types spec,
# decision 11): an engine calls
#
#   ContentSpiel::Plugins.block_types do |types|
#     types.register "gallery/album" do |t| … end
#   end
#
# from an `initializer` of its own (Rails' convention). The hook KEEPS the
# block, for the life of the process, and config/initializers/types.rb calls
# every kept block after the built-ins on every `to_prepare`, so a reload
# registers the outside types again against freshly loaded classes, as it
# does the built-ins. An engine's own `to_prepare` would not do: it runs
# before the application's, whose first line is `reset!`.
#
# Required from config/application.rb BEFORE `Bundler.require`, so a gem may
# name the hook whenever its own files are loaded; therefore plain Ruby,
# naming no application constant when it loads, and not reloaded (the kept
# blocks outlive every reload). A name `Admin::ContentSpiel` would shadow
# this module (test/lib/admin_namespace_shadow_test.rb).
module ContentSpiel
  module Plugins
    Hook = Data.define(:block, :location)

    # What a hook's block is handed: `register` with the registry's own
    # signature, refusing a bare name (the built-ins') and a second owner in
    # one call.
    class Registrar
      def initialize(registry, location)
        @registry = registry
        @location = location
        @owner = nil
      end

      def register(name, &definition)
        name = name.to_s
        owner, rest = name.split("/", 2)
        raise ArgumentError, "#{name.inspect}: a block type from outside is named owner/name (gallery/album); a bare name is a built-in's" if rest.nil?

        @owner ||= owner
        raise ArgumentError, "#{name.inspect}: one call of the hook registers the types of one owner, and #{@owner.inspect} came first" unless owner == @owner

        @registry.register(name, &definition)
      end
    end

    @hooks = []

    class << self
      def block_types(&block)
        raise ArgumentError, "ContentSpiel::Plugins.block_types takes a block" unless block

        Hook.new(block: block, location: caller_locations(1, 1).first.then { |place| "#{place.path}:#{place.lineno}" }).tap { |hook| @hooks << hook }
      end

      # Every kept block, in the order the hooks were called (the Gemfile's
      # order), each with a registrar of its own. Whatever a block raises is
      # raised again, as the same class, with the place of the hook's call in
      # the message, so a site's log names the gem that stopped the boot.
      def register_block_types(registry)
        @hooks.each do |hook|
          hook.block.call(Registrar.new(registry, hook.location))
        rescue StandardError => error
          raise error.exception("#{error.message} (ContentSpiel::Plugins.block_types, called at #{hook.location})")
        end
      end

      # Tests only: a hook a test kept is taken out again.
      def remove(hook) = @hooks.delete(hook)
    end
  end
end
```

  `config/application.rb`, directly above `Bundler.require(*Rails.groups)`:

```ruby
# Before the gems (block types spec, decision 11): an engine may name
# `ContentSpiel::Plugins.block_types` whenever its own files are loaded. Plain
# Ruby, and not reloaded although lib/ is autoloaded (lib/content_spiel/plugins.rb).
require_relative "../lib/content_spiel/plugins"
```

  `config/initializers/types.rb`, directly after `BlockTypes::Section.register`:

```ruby

  # Block types from outside the CMS, after every built-in, in the order
  # their hooks were called (lib/content_spiel/plugins.rb). That is the
  # picker's order too.
  ContentSpiel::Plugins.register_block_types(BlockTypes)
```

  The header comment of `types.rb` gains: outside types are replayed here, the theme is prepared last.

- [ ] **Step 5: the outside type's refusals.** In `BlockTypeDefinition`, a constant `COLOUR_LITERAL = /#\h{3,8}\b|\brgba?\(|\bhsla?\(|\boklch\(/` and, at the end of `finalize!` (after the existing checks):

```ruby
      refuse_outside! if owner
```

```ruby
    private

    # An outside type (a name with an owner) reaches only what has a seam
    # (block types spec, decisions 3 and 12): no capability, since
    # `:container` is bound to the section classes and `BlockOutline`, and
    # `:lists_posts` to `BlockTypes::PostList`'s criteria, which decide
    # posts' addresses; tokens named after its owner, so two gems cannot
    # claim one name and none a built-in's; a stylesheet of its own, given
    # as an absolute path, whose colours are the theme's base tokens.
    def refuse_outside!
      %i[container lists_posts].each do |capability|
        raise ArgumentError, "#{name}: a block type from outside may not claim :#{capability} (it has no seam for one yet)" if capability?(capability)
      end
      foreign = (themed_tokens + fixed_tokens).reject { |token| token.start_with?("#{owner}-") }
      raise ArgumentError, "#{name}: its tokens are named after its owner (#{owner}-…): #{foreign.inspect}" if foreign.any?
      return if stylesheet.nil?

      raise ArgumentError, "#{name}: a stylesheet from outside is an absolute path under its own root (Engine.root.join(...))" unless Pathname(stylesheet).absolute?
      if Pathname(stylesheet).read.match?(COLOUR_LITERAL)
        raise ArgumentError, "#{name}: its stylesheet holds a colour literal; an outside type's colours are defined from the theme's " \
                             "base tokens, as var() or color-mix() of them, so a theme that re-colours its base re-colours the block"
      end
    end
```

- [ ] **Step 6: the references.** `docs/reference/theming.md`, "The contract": a paragraph "An outside type's lines" (decision 5): binding for the site that installs it, its gem's promise and not the CMS's; the check lets a theme replace its template exactly while it is registered; `theme:new` copies its template and names its tokens; the reference's tables are the built-ins' and held to the ledger; a gem documents its own lines; a theme that still replaces a removed type's template is refused (owner's answer 3). `docs/reference/content-blocks-and-types.md`, a short section "Block types from outside" after "Sections": the hook, its rules (order, names, duplicates, no capability, the four columns, tokens from base tokens), the dormant block (decision 13), and that step 2 (installing a gem in a site's image, an engine's scripts, the stamp, a fixture engine) is not built.

- [ ] **Step 7: run.**

```sh
PGGSSENCMODE=disable bin/rails test test/lib/content_spiel/plugins_test.rb test/models/content_model test/lib/admin_namespace_shadow_test.rb test/lib/public_readers_test.rb test/lib/dependency_direction_test.rb test/values/theme test/lib/theme_css_test.rb test/lib/production_boot_test.rb
bin/rails zeitwerk:check
```

  Expected: 0 failures, 0 errors; `All is good!` (the explicitly required file under the autoloaded `lib/` is accepted, as `lib/telemetry/path_scrubber.rb` is).

- [ ] **Step 8: commit.**

```bash
git add lib/content_spiel config/application.rb config/initializers/types.rb app/models/content_model/block_type_definition.rb test/lib/content_spiel test/support/gallery_album.rb test/support/test_types.rb test/fixtures/block_types test/test_helper.rb test/models/content_model/block_type_definition_test.rb test/lib/admin_namespace_shadow_test.rb test/lib/public_readers_test.rb docs/reference/theming.md docs/reference/content-blocks-and-types.md
git commit -m "feat: ContentSpiel::Plugins.block_types, the one registration hook for a block type from outside, replayed after the built-ins

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 7: Rich text and Image declare their lines

**Files:**
- Modify: `app/models/block_types/rich_text.rb`, `app/models/block_types/image.rb`, `app/values/theme/contract.rb` (their two `WRITTEN_BLOCK_LINES` entries go), `test/models/built_in_types_test.rb`

**Interfaces:**
- Consumes: Task 1's declarations; Task 2's ledger; Task 5's shared tests.
- Produces: `BlockTypes.fetch(:rich_text)` and `BlockTypes.fetch(:image)` with `theme_methods` and `sample`; no `summary` (the tile's column rules are right for both, decision 8), no tokens, no stylesheet, no actions.

- [ ] **Step 1: write the failing test.** In `test/models/built_in_types_test.rb`:

```ruby
  test "rich text and image declare their contract lines and a sample, and need no summary, token, stylesheet or action of their own" do
    rich_text = BlockTypes.fetch(:rich_text)
    image = BlockTypes.fetch(:image)

    assert_equal %w[block page], rich_text.theme_methods
    assert_equal %w[block page asset alt caption sizes], image.theme_methods
    [ rich_text, image ].each do |definition|
      assert_nil definition.summary
      assert_empty definition.themed_tokens + definition.fixed_tokens + definition.read_only_actions
      assert_nil definition.stylesheet
    end
    assert rich_text.sample.body.present?
    assert image.sample.image
    assert_equal %w[alt caption], image.sample.translations.fetch("en").keys.map(&:to_s).sort
  end
```

- [ ] **Step 2: run it.** `PGGSSENCMODE=disable bin/rails test test/models/built_in_types_test.rb`. Expected: FAIL (`theme_methods` is nil).

- [ ] **Step 3: implement.** In `rich_text.rb`, after `t.component`:

```ruby
        t.theme_methods :block, :page
        t.sample body: "Sample paragraph with **strong words**.", shows: [ "Sample paragraph with", "<strong>strong words</strong>" ]
```

  In `image.rb`, after `t.component`:

```ruby
        t.theme_methods :block, :page, :asset, :alt, :caption, :sizes
        t.sample image: true, translations: { "en" => { caption: "Sample caption words", alt: "Sample alt words" } },
                 shows: [ "Sample caption words", %(alt="Sample alt words") ]
```

  Delete the `blocks/rich_text_component` and `blocks/image_component` entries of `Theme::Contract::WRITTEN_BLOCK_LINES`.

- [ ] **Step 4: run the proofs.**

```sh
PGGSSENCMODE=disable bin/rails test test/models/built_in_types_test.rb test/values/theme test/lib/theming_reference_test.rb test/integration/block_samples_test.rb test/components/admin/editor_screen/block_samples_card_test.rb test/integration/public_canary_test.rb test/services/translation_state_parity_test.rb test/integration/public_blocks_test.rb
```

  Expected: 0 failures, 0 errors. The ledger is unchanged and green (the declared lines are today's), the scaffold's byte-for-byte test now draws both samples on `/samples` under the copied theme as under the default, and the canary overwrites both samples' rows.

- [ ] **Step 5: commit.**

```bash
git add app/models/block_types/rich_text.rb app/models/block_types/image.rb app/values/theme/contract.rb test/models/built_in_types_test.rb
git commit -m "ref: Rich text and Image declare their contract lines and a sample

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 8: the Code block declares everything, and the `:code` capability goes

**Files:**
- Modify: `app/models/block_types/code.rb`, `app/models/content_model/block_type_definition.rb` (the `:code` branch of `finalize!` and its comment), `app/values/theme/contract.rb` (the Code line and `WRITTEN_BLOCK_THEMED_TOKENS` go), `app/components/admin/editor_screen/held_fields.rb` (`WRITTEN_TYPE_ACTIONS` goes), `app/components/admin/editor_screen/tile_summary_component.rb` (`code_line` and its branch go), `config/locales/admin/editor_screen.en.yml`, `app/assets/tailwind/themes/default/theme.css` (its `@import "./code.css";` line goes), `docs/reference/content-blocks-and-types.md` ("The Code block": capability, tile, stylesheet), `docs/reference/theming.md` (`code.css` is the type's stylesheet, imported by the entry)
- Modify tests: `test/models/built_in_types_test.rb`, `test/integration/design_tokens_test.rb`, `test/components/admin/editor_screen/held_fields_test.rb`, `test/components/admin/editor_screen/tile_summary_component_test.rb`, `test/integration/public_canary_test.rb`, `test/values/theme/scaffold_test.rb`

**Interfaces:**
- Consumes: Tasks 1–5.
- Produces: `BlockTypes::Code.summary(block, locale:)` → parts; tile words `tile_summary.types.code.empty` ("Empty"); `BlockTypes.fetch(:code).stylesheet == "code.css"`; `read_only_actions == %w[admin--editor--code-limit#update]`.

- [ ] **Step 1: write the failing tests.** In `test/models/built_in_types_test.rb`, the Code test's `assert code.capability?(:code)` becomes:

```ruby
    assert_not code.capability?(:code), "the capability's one reader was the tile's branch, which is the type's summary now"
    assert_equal %w[block page lines code language language_label filename caption string], code.theme_methods
    assert_equal CodeHighlight::ROLES.map { |role| "syn-#{role}" }, code.themed_tokens
    assert_equal "code.css", code.stylesheet
    assert_equal %w[admin--editor--code-limit#update], code.read_only_actions
    assert_equal [ "show.html.erb", %(<span class="syn-) ], code.sample.shows
```

  Delete the test "a type with the code capability and without its three fields is refused, and the message names what is missing" (the capability is gone, decision 9). In `tile_summary_component_test.rb` add (review focus 5):

```ruby
  test "a code block whose stored language is not on the list reads as plain text: its first line alone" do
    render_summary block("code", settings: { "language" => "xojo", "code" => "x = 1\ny = 2" })
    assert_equal "x = 1", page.find(line).text
    assert_selector "#{line} > span.font-cs-mono", exact_text: "x = 1"
    assert_no_selector attention
  end
```

  In `design_tokens_test.rb`, the Code stylesheet test's first assertion becomes `assert_not_includes Rails.root.join(ThemeCss::DEFAULT).read, "code.css", "the Code type's stylesheet is imported by the entry, as the type declares it"` and `assert_equal Rails.root.join("app/assets/tailwind/themes/default/code.css"), BlockTypes.fetch(:code).stylesheet_path`; its name says "declared by the type and imported by the entry". In `held_fields_test.rb`, the `ALLOWED` list's Code token now carries the comment "the Code type's declared action", and the allow-list test drops `WRITTEN_TYPE_ACTIONS`.

- [ ] **Step 2: run them.** `PGGSSENCMODE=disable bin/rails test test/models/built_in_types_test.rb test/integration/design_tokens_test.rb`. Expected: failures (the capability is still there; `theme_methods` nil).

- [ ] **Step 3: implement the type** (`app/models/block_types/code.rb`). The class comment: `:code` is no longer a capability; the tile asks the type's `summary`. The registration, exactly as the spec's decision 1 (with `t.capability :code` removed):

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

  and the summary, moved from `TileSummaryComponent#code_line` with its comment (design answer C7). The first line is cut at the type's own `SUMMARY_LENGTH`, not at `TileSummaryComponent::LENGTH`: a model may not name a component (`test/lib/dependency_direction_test.rb`), and the tile cuts its whole line at the same count anyway:

```ruby
    # The first line of code is cut at this many characters, as the tile cuts
    # every line (`Admin::EditorScreen::TileSummaryComponent::LENGTH`, 80).
    SUMMARY_LENGTH = 80

    # The tile's line of a closed Code block, as parts (block types spec,
    # decision 8; design answer C7): its file name if it has one; otherwise
    # its language as an editor reads it and the first line of its code,
    # without the indentation it starts with, in the monospace face, or that
    # line alone for plain text. A block with no file name and no code says
    # "Empty" in the meta colour, whatever language is chosen, and is not
    # marked: an empty block is the state the picker leaves it in.
    def self.summary(block, locale:)
      settings = block.settings_object(locale: locale)
      name = settings&.filename.presence
      return [ [ :text, name ] ] if name

      first = settings&.code.to_s.lines.first.to_s.strip.truncate(SUMMARY_LENGTH).presence
      return [ [ :hint, :empty ] ] unless first

      language = CodeHighlight.label(settings&.language)
      [ ([ :text, "#{language} · " ] if language), [ :mono, first ] ].compact
    end
```

- [ ] **Step 4: the hand-written entries go.**
  - `block_type_definition.rb`: the `:code` branch of `finalize!` and the paragraph about it in the comment.
  - `contract.rb`: the `blocks/code_component` entry of `WRITTEN_BLOCK_LINES` (with its comment, which moves to the Code type's `theme_methods` line in `code.rb`), and `WRITTEN_BLOCK_THEMED_TOKENS` with its use in `themed_tokens` (which becomes `SHARED_THEMED_TOKENS + ::BlockTypes.all.flat_map(&:themed_tokens)`).
  - `held_fields.rb`: `WRITTEN_TYPE_ACTIONS` and its use.
  - `tile_summary_component.rb`: `code_line` and the `capability?(:code)` branch; the class comment's "a code block's file name or its language and first line" now says the line of a type with a summary is the type's.
  - `editor_screen.en.yml`: `empty_code: "Empty"` leaves `tile_summary` for `types: code: empty: "Empty"`, with a comment above `types:`: "A block type's own words on its tile, by type (a slash in its name read as a dot): read by the tile for the parts its `summary` answers (block types spec, decision 8)". If `test/lib/source_layout_test.rb` or `admin_i18n_test.rb` reports a key under `types` as unread (the tile reads it by an absolute key built from the type), add `types` to that guard's list of keys read by a computed name, with the reason.
  - `theme.css`: delete `@import "./code.css";`.

- [ ] **Step 5: the shared tests' Code rows go** (spec, Risks: the sample now carries them). `public_canary_test.rb`: delete the `block(page, "code", …)` row of `@alpha` (the samples page has a Code block, top level and in a column). `scaffold_test.rb`: delete the `add.("code", { settings: { "language" => "erb", "filename" => "show.html.erb", … } }, …)` row and its words in the `/wide` list (`"content-block--code"`, `"show.html.erb"`, `%(<span class="syn-embed">)`, `"A template"`); keep the plain `add.("code", { settings: { "code" => "plain words" } })` row and its words `%(data-code-copy-target="strip")` and `"plain words"` (it is more than one of each: a bare head strip). Update the `wide_page` comment.

- [ ] **Step 6: run.**

```sh
PGGSSENCMODE=disable bin/rails test test/models test/values test/lib test/components test/integration/design_tokens_test.rb test/integration/public_canary_test.rb test/integration/public_blocks_test.rb test/integration/theme_pages_test.rb test/integration/block_samples_test.rb test/integration/admin/content_blocks_test.rb test/integration/admin/editing_test.rb test/integration/public_javascript_test.rb test/services/translation_state_parity_test.rb
```

  Expected: 0 failures, 0 errors; the tile's Code test (`"a code block is its file name; else its language and its first line of code, …"`) passes with its expectations unchanged.

- [ ] **Step 7: the stylesheet is the same, then the browser files (nothing else running).**

```sh
bin/rails tailwindcss:build
cmp app/assets/builds/theme.css "$SNAP/theme.before.css" && echo SAME
bin/rails theme_css:build
PGGSSENCMODE=disable bin/rails test test/system/code_block_test.rb
PGGSSENCMODE=disable bin/rails test test/system/admin/editing_holds_test.rb
PGGSSENCMODE=disable bin/rails test test/system/admin/sections_test.rb
```

  Expected: `SAME` (code.css moved from the end of `theme.css` to directly after it in the entry, which is the same place in the output); every browser test passes. A difference in the stylesheet is reported to the controller with the `diff` of Task 3 Step 7 before anything is committed.

- [ ] **Step 8: commit.**

```bash
git add app/models/block_types/code.rb app/models/content_model/block_type_definition.rb app/values/theme/contract.rb app/components/admin/editor_screen/held_fields.rb app/components/admin/editor_screen/tile_summary_component.rb config/locales/admin/editor_screen.en.yml app/assets/tailwind/themes/default/theme.css docs/reference/content-blocks-and-types.md docs/reference/theming.md test
git commit -m "ref: the Code block declares its line, tokens, stylesheet, tile line, read-only action and sample; the :code capability goes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 9: Post list and Section declare their lines

**Files:**
- Modify: `app/models/block_types/post_list.rb`, `app/models/block_types/section.rb`, `app/values/theme/contract.rb` (the last two `WRITTEN_BLOCK_LINES` entries go; the constant is then empty and stays until Task 10), `app/components/admin/editor_screen/tile_summary_component.rb` (`listing` and its branch go), `config/locales/admin/editor_screen.en.yml`, `docs/reference/content-blocks-and-types.md` (the tile in "Sections")
- Modify tests: `test/models/built_in_types_test.rb`, `test/components/admin/editor_screen/tile_summary_component_test.rb`

**Interfaces:**
- Consumes: Tasks 1–5, 8 (the tile's `types` scope).
- Produces: `BlockTypes::PostList.summary(block, locale:)`; tile words `types.post_list.any_type` ("All posts") and `types.post_list.tag` ("tag %{name}"). Section declares no `stylesheet` and no `summary` (departure 1).

- [ ] **Step 1: write the failing tests.** `built_in_types_test.rb`:

```ruby
  test "post list and section declare their contract lines and a sample; the list's tile line is its own, the section brings no stylesheet" do
    list = BlockTypes.fetch(:post_list)
    section = BlockTypes.fetch(:section)

    assert_equal %w[block page list_component], list.theme_methods
    assert_equal %w[block page columns layout background width], section.theme_methods
    assert list.summary
    assert_nil section.summary, "a section's tile is its lanes"
    assert_nil section.stylesheet, "sections.css is the default theme's own stylesheet, imported by theme.css before every type's"
    assert_equal({ "content_type" => "blog" }, list.sample.settings)
    assert_equal "tinted", section.sample.settings.fetch("background")
  end
```

  `tile_summary_component_test.rb` (review focus 5):

```ruby
  test "a post list naming a content type that is no longer registered reads as its stored name" do
    render_summary block("post_list", settings: { "content_type" => "retired", "tag" => "old" })
    assert_equal "retired · tag old", page.find(line).text
  end
```

- [ ] **Step 2: run them.** `PGGSSENCMODE=disable bin/rails test test/models/built_in_types_test.rb test/components/admin/editor_screen/tile_summary_component_test.rb`. Expected: the declaration test fails; the tile test passes already (it pins today's behaviour before the move).

- [ ] **Step 3: implement.** `post_list.rb`, after `t.component`:

```ruby
        t.theme_methods :block, :page, :list_component
        t.summary ->(block, locale:) { PostList.summary(block, locale: locale) }
        t.sample settings: { "content_type" => "blog" }, shows: [ "content-block--post-list" ]
```

  and, moved from `TileSummaryComponent#listing` with its comment:

```ruby
    # The tile's line of a closed post list (block types spec, decision 8):
    # the content type it lists, or "All posts", then its tag. A content
    # type that is no longer registered reads as its stored name, as the
    # block card's own field shows it.
    def self.summary(block, locale:)
      settings = block.settings_object(locale: locale)
      type = settings&.content_type.presence
      tag = settings&.tag.presence

      [ (type ? [ :text, ContentTypes.find(type)&.label || type ] : [ :word, :any_type ]),
        *([ [ :text, " · " ], [ :word, :tag, { name: tag } ] ] if tag) ]
    end
```

  `section.rb`, after `t.component`:

```ruby
        t.theme_methods :block, :page, :columns, :layout, :background, :width
        t.sample settings: { "layout" => "two", "background" => "tinted", "width" => "content" }, shows: [ "content-section--tinted" ]
```

  `contract.rb`: delete the two entries; `WRITTEN_BLOCK_LINES` is `{}.freeze` with its comment saying Task 10 deletes it. `tile_summary_component.rb`: delete `listing` and the `capability?(:lists_posts)` branch. `editor_screen.en.yml`: `any_type` and `tag` leave `tile_summary` for `types: post_list: { any_type: "All posts", tag: "tag %{name}" }`.

- [ ] **Step 4: run.**

```sh
PGGSSENCMODE=disable bin/rails test test/models test/values test/lib test/components test/integration/public_canary_test.rb test/integration/public_blocks_test.rb test/integration/theme_pages_test.rb test/integration/block_samples_test.rb test/integration/admin/content_blocks_test.rb test/services/translation_state_parity_test.rb test/queries/post_graph
bin/rails tailwindcss:build && bin/rails theme_css:build
PGGSSENCMODE=disable bin/rails test test/system/admin/sections_test.rb
```

  Expected: 0 failures, 0 errors; the tile's post-list test and the sections browser file pass unchanged; the samples page now holds a section with every other type in its first column, so `block_samples_test.rb`'s "in a column" half is exercised.

- [ ] **Step 5: commit.**

```bash
git add app/models/block_types/post_list.rb app/models/block_types/section.rb app/values/theme/contract.rb app/components/admin/editor_screen/tile_summary_component.rb config/locales/admin/editor_screen.en.yml docs/reference/content-blocks-and-types.md test/models/built_in_types_test.rb test/components/admin/editor_screen/tile_summary_component_test.rb
git commit -m "ref: Post list and Section declare their contract lines and a sample; the list's tile line is its own

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 10: every block type declares its theme methods and a sample; the transition ends

**Files:**
- Modify: `app/models/content_model/block_type_definition.rb` (`finalize!`), `app/values/theme/contract.rb` (`WRITTEN_BLOCK_LINES` and its use go), `test/support/block_samples.rb`, and every test that registers a block type of its own: `test/integration/admin/translation_status_test.rb:102`, `test/values/theme/contract_test.rb:59`, `test/models/content_block_test.rb:166`, `test/models/built_in_types_test.rb:38`, `test/models/content_model/registry_test.rb` (lines 15, 30, 39, 61), `test/models/translations/tracker_test.rb:173`; `test/models/content_model/block_type_definition_test.rb`

**Interfaces:**
- Consumes: `TestTypes.declare(t)` (Task 6).
- Produces: `finalize!` refuses a block type without `theme_methods` or `sample` (decision 2, owner's answer 6); `sampled_types` is `BlockTypes.all`; `Theme::Contract.components` reads only declarations.

- [ ] **Step 1: write the failing test.** In `block_type_definition_test.rb`:

```ruby
  test "a block type without theme methods or a sample is refused, and the message says what to declare" do
    saved = BlockTypes.all.dup
    error = assert_raises(ArgumentError) { BlockTypes.register(:test_bare) { |t| t.label "Bare"; t.sample shows: [ "x" ] } }
    assert_includes error.message, "theme_methods"
    error = assert_raises(ArgumentError) { BlockTypes.register(:test_bare) { |t| t.label "Bare"; t.theme_methods :block, :page } }
    assert_includes error.message, "sample"
    assert_nil BlockTypes.find(:test_bare)
  ensure
    BlockTypes.reset!
    saved.each { |definition| BlockTypes.registry_put(definition) }
  end
```

- [ ] **Step 2: run it.** `PGGSSENCMODE=disable bin/rails test test/models/content_model/block_type_definition_test.rb`. Expected: FAIL (no refusal).

- [ ] **Step 3: implement.** In `finalize!`, after the `:container` and `:lists_posts` checks and before `refuse_outside!` (so their own messages stay what their tests expect):

```ruby
      # Required of every block type (block types spec, decision 2): a theme
      # must be able to replace the public template, which needs its line in
      # the contract; and the sample is what puts the type into every shared
      # test, the canary above all.
      raise ArgumentError, "#{name}: a block type declares `theme_methods`, the methods its public template may call" if theme_methods.nil?
      raise ArgumentError, "#{name}: a block type declares a `sample`, one filled block of itself, for the shared tests" if sample.nil?
```

  `contract.rb`: delete `WRITTEN_BLOCK_LINES`; `components` reads `definition.theme_methods` only. `block_samples.rb`: `def sampled_types = BlockTypes.all` with the transition comment replaced by "every type declares a sample (decision 2)", and `assert_every_type_built(names = BlockTypes.names)`.

- [ ] **Step 4: the tests' own types.** Each `BlockTypes.register` in the files listed under **Files** that is expected to succeed gains `TestTypes.declare(t);` (inline blocks) or the line `TestTypes.declare(t)` (multi-line blocks); one that is expected to raise for another reason first keeps raising for it (the order in `finalize!` above). The `marquee` test in `contract_test.rb` becomes:

```ruby
  # Departure 6 (block types plan): with `theme_methods` required, a type
  # whose template a theme could not replace is refused when it is
  # registered, before any list is asked.
  test "a block type registered without theme methods is refused at registration, and the message says what to declare" do
    error = assert_raises(ArgumentError) do
      BlockTypes.register("marquee") { |t| t.label "Marquee"; t.component unlisted_component("Blocks::MarqueeComponent"); t.sample shows: [ "x" ] }
    end
    assert_includes error.message, "theme_methods"
  ensure
    Rails.application.reloader.prepare!
  end
```

  Then: `grep -rn "BlockTypes.register" test | grep -v "declare\|theme_methods"` lists only registrations that raise before the requirement (each checked by reading the test) and `test/support/test_types.rb` / `test/support/gallery_album.rb` (which declare in full).

- [ ] **Step 5: run.**

```sh
PGGSSENCMODE=disable bin/rails test test/models test/values test/lib test/components test/integration/admin/translation_status_test.rb test/integration/open_types_test.rb test/integration/public_canary_test.rb test/integration/block_samples_test.rb test/integration/theme_pages_test.rb test/services/translation_state_parity_test.rb test/mcp
```

  Expected: 0 failures, 0 errors. `grep -rn "WRITTEN_" app test` prints nothing.

- [ ] **Step 6: commit.**

```bash
git add app/models/content_model/block_type_definition.rb app/values/theme/contract.rb test
git commit -m "feat: every block type declares its theme methods and a sample, and the contract reads nothing else

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 11: `bin/rails generate block_type <name>`

**Files:**
- Create: `lib/generators/block_type/block_type_generator.rb`, `lib/generators/block_type/templates/{definition.rb,component.rb,component.html.erb,stylesheet.css,preview.rb,definition_test.rb,component_test.rb}.tt`, `lib/generators/block_type/USAGE`, `test/lib/generators/block_type_generator_test.rb`
- Modify: `config/application.rb` (`autoload_lib(ignore: %w[assets tasks generators])`), `config/initializers/types.rb` (the marker line), `config/locales/public.en.yml` and `config/locales/admin/editor_screen.en.yml` (a marker line each)

**Interfaces:**
- Consumes: everything Tasks 1–10 built; `sample_block` (Task 5).
- Produces: `BlockTypeGenerator` (`Rails::Generators::NamedBase`), its three markers as constants: `TYPES_MARKER`, `PUBLIC_MARKER`, `TILE_MARKER`.

- [ ] **Step 1: the markers.** `config/initializers/types.rb`, directly below `BlockTypes::Section.register`: `  # bin/rails generate block_type adds a built-in's line above this one.` `config/locales/public.en.yml`, as the first line under `blocks:`: `      # bin/rails generate block_type adds a type's scope below this line.` `editor_screen.en.yml`, as the first line under `tile_summary: types:`: the same words at that indentation. (Match each file's own indentation; the constants below hold exactly what is written.)

- [ ] **Step 2: write the failing test,** `test/lib/generators/block_type_generator_test.rb`:

```ruby
require "test_helper"
require "rails/generators/test_case"
require "generators/block_type/block_type_generator"

# `bin/rails generate block_type <name>` (block types spec, "The generator"):
# a built-in type of this repository, which registers, joins the contract
# and every shared test, and passes the guards as written. The whole suite
# cannot run in a test, so the generated files are written into a temporary
# folder, loaded, registered and put through the derived checks here; the
# whole suite is run once with a generated type by hand (the plan's Task 11).
class BlockTypeGeneratorTest < Rails::Generators::TestCase
  tests BlockTypeGenerator
  destination Rails.root.join("tmp/generators")
  setup :prepare_destination

  MARKED = %w[config/initializers/types.rb config/locales/public.en.yml config/locales/admin/editor_screen.en.yml].freeze

  setup do
    MARKED.each { |file| FileUtils.mkdir_p(File.dirname(File.join(destination_root, file))); FileUtils.cp(Rails.root.join(file), File.join(destination_root, file)) }
  end

  test "it writes the definition, its line, the component, the stylesheet, the scopes, a preview and two tests" do
    run_generator %w[callout]

    assert_file "app/models/block_types/callout.rb", /BlockTypes.register :callout/, /t.theme_methods :block, :page/, /t.stylesheet "callout.css"/, /t.sample /
    assert_file "config/initializers/types.rb", /BlockTypes::Callout.register\n  # bin\/rails generate block_type adds/
    assert_file "app/components/blocks/callout_component.rb", /def initialize\(block:, page:\)/, /def render\?/
    assert_file "app/components/blocks/callout_component.html.erb", /content-block content-block--callout/
    assert_file "app/assets/tailwind/themes/default/callout.css", /\.content-block--callout/
    assert_file "config/locales/public.en.yml", /adds a type's scope below this line.\n\s+callout: \{\}/
    assert_file "config/locales/admin/editor_screen.en.yml", /adds a type's scope below this line.\n\s+callout: \{\}/
    assert_file "test/components/previews/blocks/callout_component_preview.rb"
    assert_file "test/models/block_types/callout_test.rb"
    assert_file "test/components/blocks/callout_component_test.rb"
  end

  test "a locale file without its marker gets nothing, and the generator says so" do
    File.write(File.join(destination_root, "config/locales/public.en.yml"), "en:\n  public:\n    blocks: {}\n")
    output = run_generator %w[callout]

    assert_includes output, "config/locales/public.en.yml has no marker line"
    assert_file "config/locales/public.en.yml", "en:\n  public:\n    blocks: {}\n"
  end

  # `debug: true` makes Thor raise the refusal instead of printing it to
  # standard error, which `run_generator` does not capture.
  test "a name with an owner, and one that is no type name, are refused" do
    assert_includes assert_raises(Thor::Error) { run_generator %w[gallery/album], debug: true }.message, "an outside type is an engine's"
    assert_no_file "app/models/block_types/album.rb"
    assert_includes assert_raises(Thor::Error) { run_generator %w[Call-Out], debug: true }.message, "lowercase"
  end

  test "a generated type registers, joins the contract and every shared test, and its sample draws its words" do
    run_generator %w[callout]
    load File.join(destination_root, "app/components/blocks/callout_component.rb")
    load File.join(destination_root, "app/models/block_types/callout.rb")
    BlockTypes::Callout.register

    assert_equal %w[block page], Theme::Contract.components.fetch("blocks/callout_component")
    page = create_page(title: "Callout")
    block = sample_block(page, "callout")
    render = ApplicationController.render(Blocks::CalloutComponent.new(block: block, page: page), layout: false)
    BlockTypes.fetch(:callout).sample.shows.each { |text| assert_includes render, text }
    assert_includes Admin::EditorScreen::HeldFields.allowed_actions, "admin--ui--menu#close"
  ensure
    Blocks.send(:remove_const, :CalloutComponent) if Blocks.const_defined?(:CalloutComponent, false)
    BlockTypes.send(:remove_const, :Callout) if BlockTypes.const_defined?(:Callout, false)
    Rails.application.reloader.prepare!
  end
end
```

  (If `ApplicationController.render` cannot render the component without the public URL helpers, render it with `ComponentPreviewsController.render`, the controller `ComponentTestHelper` names for the same reason.)

- [ ] **Step 3: run it.** `PGGSSENCMODE=disable bin/rails test test/lib/generators/block_type_generator_test.rb`. Expected: error, `LoadError: cannot load such file -- generators/block_type/block_type_generator`.

- [ ] **Step 4: the generator,** `lib/generators/block_type/block_type_generator.rb`. **Do not write the word `Component` with a capital in this `.rb` file** (`test/lib/dependency_direction_test.rb` reads `lib/` for `…Component` constants); the templates are `.tt` files and are not read by it.

```ruby
require "rails/generators/named_base"

# `bin/rails generate block_type callout` (block types spec, "The
# generator"): a built-in block type of this repository, in the places Rails
# expects (decision 15), with the two lines every type declares filled in.
# An engine's generator, for an `owner/name` type, is step 2. In lib/generators,
# Rails' place for a generator, which `autoload_lib` ignores.
class BlockTypeGenerator < Rails::Generators::NamedBase
  source_root File.expand_path("templates", __dir__)

  TYPES_MARKER = "  # bin/rails generate block_type adds a built-in's line above this one.\n".freeze
  PUBLIC_MARKER = "      # bin/rails generate block_type adds a type's scope below this line.\n".freeze
  TILE_MARKER = "            # bin/rails generate block_type adds a type's scope below this line.\n".freeze

  def refuse_a_name_that_is_not_a_built_ins
    raise Thor::Error, "#{name}: an outside type is an engine's (owner/name), and its generator is not built yet" if name.include?("/")
    raise Thor::Error, "#{name}: a block type's name is lowercase words joined by underscores (callout, pull_quote)" unless name.match?(/\A[a-z][a-z0-9_]*\z/)
  end

  def definition
    template "definition.rb", "app/models/block_types/#{file_name}.rb"
    insert_into_file "config/initializers/types.rb", "  BlockTypes::#{class_name}.register\n", before: TYPES_MARKER
  end

  def public_render
    template "component.rb", "app/components/blocks/#{file_name}_component.rb"
    template "component.html.erb", "app/components/blocks/#{file_name}_component.html.erb"
    template "stylesheet.css", "app/assets/tailwind/themes/default/#{file_name}.css"
  end

  def scopes
    scope "config/locales/public.en.yml", PUBLIC_MARKER, "      #{file_name}: {}\n"
    scope "config/locales/admin/editor_screen.en.yml", TILE_MARKER, "            #{file_name}: {}\n"
  end

  def tests_and_preview
    template "preview.rb", "test/components/previews/blocks/#{file_name}_component_preview.rb"
    template "definition_test.rb", "test/models/block_types/#{file_name}_test.rb"
    template "component_test.rb", "test/components/blocks/#{file_name}_component_test.rb"
  end

  private

  # A scope goes below the file's marker line; a file without one gets
  # nothing, and the generator says where to write it by hand.
  def scope(file, marker, line)
    path = File.join(destination_root, file)
    if File.exist?(path) && File.read(path).include?(marker)
      insert_into_file file, line, after: marker
    else
      say_status :skip, "#{file} has no marker line (#{marker.strip}): add the #{file_name} scope by hand", :yellow
    end
  end
end
```

  The indentations are the files' own at `61a85d01`: in `public.en.yml` `blocks:` is at 4 spaces, so a type's scope (and the marker) at 6; in `editor_screen.en.yml` `tile_summary:` is at 8 and `types:` (Task 8) at 10, so a type's scope and the marker at 12. Check both files before writing Step 1, and keep each constant equal to its marker line character for character.

  `templates/definition.rb.tt` (the spec's table: one `:text` field, `theme_methods :block, :page`, the stylesheet, a sample with the field filled and in `shows`):

```erb
module BlockTypes
  # A <%= human_name.downcase %> block. Say here what it is for, where each of
  # its values is stored and why (docs/reference/content-blocks-and-types.md,
  # "Adding a block type").
  module <%= class_name %>
    def self.register
      BlockTypes.register :<%= file_name %> do |t|
        t.label "<%= human_name %>"
        t.field :text, :text, translated: true
        t.component Blocks::<%= class_name %>Component
        t.theme_methods :block, :page
        t.stylesheet "<%= file_name %>.css"
        t.sample translations: { "en" => { text: "A sample <%= human_name.downcase %>" } }, shows: [ "A sample <%= human_name.downcase %>" ]
      end
    end
  end
end
```

  `templates/component.rb.tt`:

```erb
module Blocks
  # The <%= human_name.downcase %> block on the public site. A theme may replace
  # its template and call only what the type's `theme_methods` names.
  class <%= class_name %>Component < ApplicationComponent
    def initialize(block:, page:)
      @block = block
      @page = page
    end

    def render? = block.settings_object(fallback: true)&.text.present?

    private

    attr_reader :block, :page
  end
end
```

  `templates/component.html.erb.tt` (the template calls `block` only, so the line is `:block, :page`; the outer class is `content-block content-block--<name>` as the spec's table writes it, the name as it is, underscore included):

```erb
<div class="content-block content-block--<%= file_name %>"><%%= block.settings_object(fallback: true).text %></div>
```

  `templates/stylesheet.css.tt`:

```erb
/* The <%= human_name.downcase %> block's public styles. Every colour is a --th- token:
   a built-in's token values are written in tokens.css, light and dark, and
   declared in the type's `tokens` (block types spec, decision 3). */
.content-block--<%= file_name %> {
}
```

  `templates/preview.rb.tt` (as `rich_text_component_preview.rb` is, its block from the sample):

```erb
require_relative "../preview_fixtures"

module Blocks
  class <%= class_name %>ComponentPreview < ViewComponent::Preview
    def default
      page = PreviewFixtures.page(title: "<%= human_name %> preview")
      sample = BlockTypes.fetch(:<%= file_name %>).sample
      block = page.content_blocks.create!(block_type: :<%= file_name %>, position: 0)
      block.assign_settings(sample.translations.fetch("en").transform_keys(&:to_s), locale: "en")
      block.save!

      render Blocks::<%= class_name %>Component.new(block: block, page: page)
    end
  end
end
```

  `templates/definition_test.rb.tt`:

```erb
require "test_helper"

class BlockTypes::<%= class_name %>Test < ActiveSupport::TestCase
  test "<%= file_name %> is one translated text, nothing required" do
    definition = BlockTypes.fetch(:<%= file_name %>)

    assert_equal [ %w[text text] ], definition.fields.map { |field| [ field.name, field.type.to_s ] }
    assert definition.fields.none?(&:required?)
    assert definition.fields.all?(&:translated?)
    assert_equal Blocks::<%= class_name %>Component, definition.component
  end
end
```

  `templates/component_test.rb.tt`:

```erb
require "test_helper"

class Blocks::<%= class_name %>ComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper

  def block_with(text)
    block = ContentBlock.new(owner: root_page, block_type: "<%= file_name %>")
    block.assign_settings({ "text" => text }, locale: "en")
    block
  end

  test "the sample's text is drawn in the block's element" do
    render_inline Blocks::<%= class_name %>Component.new(block: block_with("A sample <%= human_name.downcase %>"), page: root_page)
    assert_selector ".content-block--<%= file_name %>", text: "A sample <%= human_name.downcase %>"
  end

  test "an empty block draws nothing" do
    render_inline Blocks::<%= class_name %>Component.new(block: block_with(""), page: root_page)
    assert_no_selector ".content-block--<%= file_name %>"
  end

  test "text that looks like markup is text" do
    render_inline Blocks::<%= class_name %>Component.new(block: block_with("<script>x</script>"), page: root_page)
    assert_no_selector "script", visible: :all
    assert_includes rendered_content, "&lt;script&gt;"
  end
end
```

  `USAGE`: one paragraph naming what is written and that an `owner/name` type is an engine's (step 2).

  `config/application.rb`: `config.autoload_lib(ignore: %w[assets tasks generators])`.

- [ ] **Step 5: run the generator's test.** `PGGSSENCMODE=disable bin/rails test test/lib/generators/block_type_generator_test.rb test/lib/dependency_direction_test.rb test/lib/source_layout_test.rb`. Expected: 0 failures, 0 errors.

- [ ] **Step 6: a generated type passes the suite's guards and shared tests (by hand, not committed).**

```sh
bin/rails generate block_type callout
PGGSSENCMODE=disable bin/rails test test/models/block_types/callout_test.rb test/components/blocks/callout_component_test.rb test/values/theme test/lib test/integration/block_samples_test.rb test/components/admin/editor_screen test/integration/public_canary_test.rb test/services/translation_state_parity_test.rb test/integration/design_tokens_test.rb
bin/rails zeitwerk:check
bin/rails destroy block_type callout
git status --short
```

  Expected: 0 failures and 0 errors with `callout` registered, except the ledger, which must fail naming `blocks/callout_component` (a new type is a new promise: that failure is the moment the release note is written, and is the ledger working); `All is good!`; after `destroy`, `git status --short` lists only this task's own files. If any other test fails, the generator writes something wrong: fix the template, not the test.

- [ ] **Step 7: commit.**

```bash
git add lib/generators config/application.rb config/initializers/types.rb config/locales/public.en.yml config/locales/admin/editor_screen.en.yml test/lib/generators
git commit -m "feat: bin/rails generate block_type writes a built-in block type that joins the contract and every shared test

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 12: the documents, the whole check, the comparison, and the roadmap

**Files:** Modify `docs/reference/content-blocks-and-types.md`, `docs/reference/theming.md` (what earlier tasks left), `CLAUDE.md`, `docs/superpowers/specs/2026-10-13-block-types-declare-what-they-bring-design.md`; then, in its own commit, `docs/roadmap.md`.

**Interfaces:** consumes everything as built. Read the branch's diff first (`git diff main...HEAD --stat`, then the files): describe the code that is there, not this plan.

- [ ] **Step 1: the recipe.** In `docs/reference/content-blocks-and-types.md`, "Adding a block type: what the Code block touched" becomes "Adding a block type", the spec's rewritten recipe (steps 0 to 11, "The recipe, rewritten"), each step with the test it needs and the guard that is red until it is done, as built: the generator (Task 11) and what it writes; the six declarations and which list reads each; the ledger (a new type fails it until its line and tokens are written there, with the release note); the derived shared tests (`test/support/block_samples.rb`, and which tests end with `assert_every_type_built`); a sample that fills every column it uses. The paragraph "What a type no longer touches" from the spec, checked against the code. The Code block's history stays as its own section above. To the `> Describes:` line add `lib/content_spiel/plugins.rb`, `lib/generators/block_type/`, `test/support/block_samples.rb`.

- [ ] **Step 2: `docs/reference/theming.md`.** Read it whole: no mention of a removed constant, of the theme prepared in `theme.rb`, or of `code.css` imported by `theme.css` is left (`grep -n "COMPONENTS\|THEMED_TOKENS\|FIXED_TOKENS\|Contract::TOKENS\|initializers/theme.rb\|code.css" docs/reference/theming.md` and read each hit). In "What a change can break silently": the ledger and its test; the outside type's lines and the check's refusal of a removed type's template, with the tests of Tasks 2 and 6.

- [ ] **Step 3: `CLAUDE.md`.** Check every test name against the files before writing it.
  - The contract rule ("A name in `Theme::Contract` …"): "A new block type joins by its component's line in `COMPONENTS` and its tokens' lines" becomes "joins by its declarations (`theme_methods`, `tokens`), and by the ledger (`test/support/contract_ledger.rb`)" with `test/values/theme/contract_ledger_test.rb`: "the built-in types' part of the contract is the ledger: a name added, renamed or removed is a release note".
  - The theme rule ("`Theme.with` and `Theme.current=` are the tests' and the one assignment in `config/initializers/theme.rb`") names `config/initializers/types.rb`, where the theme is prepared last.
  - The held-form rule ("Its `data-action` tokens are an allow-list (`ALLOWED_ACTIONS`)"): `HeldFields.allowed_actions`, the CMS's four and each type's `read_only_actions`, with the tests of Task 4.
  - A new rule for the hook: an outside block type is registered only through `ContentSpiel::Plugins.block_types`, replayed after the built-ins on every prepare; a name with an owner, one owner per call, a duplicate raised with the place of the call; no `:container` or `:lists_posts`; tokens named after the owner and defined from the theme's base tokens (`test/lib/content_spiel/plugins_test.rb` and `block_type_definition_test.rb`, each test by name).
  - A new rule for the samples: every block type declares `theme_methods` and a `sample`; every shared test that builds a site ends with `assert_every_type_built`; a sample fills every column its type uses (`test/integration/block_samples_test.rb`, by name).
  - "Where a class goes": `lib/` names `ContentSpiel::Plugins` (required before `Bundler.require`) and `lib/generators` (Rails' place for a generator, ignored by `autoload_lib`).
  - The reference index's content-blocks line gains `lib/content_spiel/plugins.rb`, `lib/generators/block_type/`, `test/support/block_samples.rb`.
  - `grep -n "capability :code\|capability?(:code)\|ALLOWED_ACTIONS\|Contract::COMPONENTS\|THEMED_TOKENS" CLAUDE.md docs/reference` prints nothing.
  - Run `PGGSSENCMODE=disable bin/rails test test/lib`: the layout guard reads `CLAUDE.md` and `docs/reference` for Stimulus identifiers.

- [ ] **Step 4: the spec's "As built".** Status line: "built (plan `docs/superpowers/plans/2026-10-13-block-types-declare-what-they-bring.md`)". A last section, "As built": the twelve departures of this plan as they finally were, and whatever the build changed beyond them; for each, which document now describes the code.

- [ ] **Step 5: commit the documents.**

```bash
git add docs/reference/content-blocks-and-types.md docs/reference/theming.md CLAUDE.md docs/superpowers/specs/2026-10-13-block-types-declare-what-they-bring-design.md
git commit -m "docs: block types declare what they bring — the recipe, the rules with their tests, and the spec as built

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

- [ ] **Step 6: the whole check (the controller's; nothing else running, the machine quiet: `sysctl -n vm.loadavg`).**

```sh
PGGSSENCMODE=disable bin/rails test
bin/rails tailwindcss:build && bin/rails theme_css:build
PGGSSENCMODE=disable PARALLEL_WORKERS=6 bin/rails test:system
bin/theme-build-check
bin/rubocop
bin/brakeman
bin/bundler-audit
bin/importmap audit
bin/rails zeitwerk:check
```

  Expected: 0 failures and 0 errors twice; `bin/theme-build-check` ends 0 (run alone); no offences; brakeman exits 0 with `config/brakeman.ignore` untouched; no vulnerabilities; `All is good!`.

- [ ] **Step 7: the after-snapshot and the comparison (the controller's).** With the same development database Task 0 read:

```sh
bin/rails tailwindcss:build
cmp app/assets/builds/theme.css "$SNAP/theme.before.css" && echo "stylesheet SAME"
bin/rails runner "$SNAP/pages.rb" "$SNAP/after"
diff -r "$SNAP/before" "$SNAP/after" && echo "pages SAME"
```

  Expected: `stylesheet SAME` and `pages SAME`. A difference that is only a relative time ("3 days ago") moving with the clock is noted and accepted; any other difference stops the pull request and goes to the owner. The result goes into the pull request's description ("Before and after: the built stylesheet and N public pages of the seeded site, identical"). Then `rm -r "$SNAP"`.

- [ ] **Step 8: the roadmap, ALONE in its own commit.** Re-read `docs/roadmap.md` whole first (it changes often). Then:
  - "Shipped": a row, "Block types declare what they bring (step 1): six declarations on a block type, the contract, the stylesheet build, the tile, the held form's allow-list and the shared tests derived from them, a ledger for the built-ins' names, `bin/rails generate block_type`, and one hook for an outside type (`ContentSpiel::Plugins.block_types`)", with the spec's file name.
  - "Next", item 2 (the catalogue): one sentence that a new block type is now the generator and one definition (link the recipe), and that the Note block is the first to be built this way.
  - Step 2 of the spec ("Step 2, named"), as one entry under "Content model and extension" with each of its points and what would start it (a first outside author).
  - "Known gaps": the outside type's capabilities and columns not opened; an outside type's scripts not loaded; the stamp does not cover the types' stylesheets; `theme_css:watch` reads the types once when it starts.

```bash
git add docs/roadmap.md
git commit -m "docs: roadmap — block types declare what they bring (step 1) shipped; step 2 named

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

- [ ] **Step 9: the pull request's "Documentation" section.** Name these guide pages (in `contentspiel-docs`, written there after this is merged, from this pull request; the spec's last paragraph):
  - Integrators, theming: `theming/the-token-contract` (the block tokens are defined from the theme's base tokens, so re-colouring the base re-colours every block; every block's tokens as the contract now derives them) and `theming/rendering-blocks-and-pages` with the block and template reference (every block's template methods as derived).
  - New, for someone working on the CMS: "Adding a block type", from the rewritten recipe (it replaces the Code block's walk-through where the two overlap).
  - New, marked as step 2's: a short page saying the CMS can be extended with a block type from outside and that how a site installs one is not built yet.
  - Editors: none (nothing a person sees changed).

---

## Self-review: where each part of the spec is built

| Spec | Task |
|---|---|
| Decision 1, the six declarations, the fixed Code lines | Task 1 (shapes), Task 8 (the Code lines exactly) |
| Decision 2, `theme_methods` and `sample` required, `test/quote` gains both | Task 5 (`test/quote`), Task 10 (the requirement) |
| Decision 3, colours: CS Studio's in the editor, the theme's base tokens on the site; built-ins' values in `tokens.css`; an outside type's from base tokens, named after its owner, no literal | Task 6 (refusals, fixture), Task 3 (token test), Task 8 (Code tokens unchanged in `tokens.css`) |
| Decision 4, the contract as methods, the shared constants, the ledger | Task 2 |
| Decision 5, an outside type's lines: the check, `theme:new`, the scaffold test over every type; the reference held to the ledger | Task 2 (methods, reference test), Task 6 (outside type through all three) |
| Decision 6, the theme prepared after the types | Task 2 |
| Decision 7 and the owner's answer 4, the stylesheet build | Task 3 (mechanism), Task 8 (`code.css`); departure 1 for `sections.css` |
| Decision 8, the tile's parts | Task 4 (mechanism), Tasks 8, 9 (the two types' summaries); departure 3 |
| Decision 9 and the owner's answer 2, the `:code` capability goes | Task 8 |
| Decision 10, the allow-list | Task 4, Task 8 |
| Decision 11 and the owner's answer 5, the hook | Task 6; departure 11 |
| Decision 12, what an outside type may use | Task 1 (`uses`), Task 6 (capabilities) |
| Decision 13 and the owner's answer 3, the dormant block and the refused template | Task 2 (the message), Task 6 (the whole path) |
| Decision 14, the sample and `test/support/block_samples.rb` | Task 5 |
| Decision 15, built-ins stay where Rails puts them | every task; Task 11 (the generator writes there) |
| Decision 16, one commit per type, the mechanism first | Tasks 1–6, then 7, 8, 9 (two trivial types per task twice, Code alone), 10; departure 2 |
| "Where each derived list sits" | Tasks 2, 3, 4, 5, 6 |
| The generator | Task 11; departure 7 |
| "Tests": every row of the table | Task 2 (theme_pages, contract `registry_components`, theming_reference), Task 3 (contract stylesheet list, tokens, design_tokens import), Task 4 (tile, held_fields), Task 5 (scaffold, canary, parity, public_blocks' derived test as `block_samples_test.rb`), Task 6 (public_readers), Task 8 (design_tokens Code), unchanged rows untouched |
| "New guards" | Task 2 (ledger), Task 5 (samples tests, `assert_every_type_built`), Task 6 (plugins_test, owner rules), Task 10 (requirement), Task 3 (`lib/theme_css` entry test), Task 1 (`uses`) |
| "How the reviewer sees that no behaviour changed" | Task 0, Tasks 2–10 (ledger, scaffold, canary), Tasks 3, 8, 12 (stylesheet), Task 12 (pages) |
| The owner's answers 1–6 | 1: decision 3 rows; 2: Task 8; 3: Tasks 2, 6; 4: Task 3, departure 1; 5: Task 6; 6: Tasks 5, 10 |
| "What the Note block changes" | not this plan (the Note's own pull request); Task 4 leaves `LOOKS` open for its `:icon` |
| "The recipe, rewritten", Documentation | Task 12 (and the folded reference edits in Tasks 2, 3, 4, 6, 8, 9) |
| "Step 2, named" | not built; Task 12 Step 8 records it on the roadmap |

**Without a task:** the guide pages (named in Task 12 Step 9), the Note block's changes (its own pull request), everything under "Step 2, named".

**Names, checked across tasks:** `theme_methods`, `tokens(themed:, fixed:)`, `themed_tokens`, `fixed_tokens`, `stylesheet`, `stylesheet_path(root:)`, `summary`, `read_only_actions`, `sample` / `Sample#settings, #translations, #body, #image, #shows`, `owner`, `component_template`, `COLUMNS`, `COLOUR_LITERAL` (Task 1, 6; read in 2–11); `Theme::Contract.components`, `.themed_tokens`, `.fixed_tokens`, `.tokens`, `.path_of`, `.template_for`, `SHARED_THEMED_TOKENS`, `SHARED_FIXED_TOKENS`, `POST_COMPONENTS`, `WRITTEN_BLOCK_LINES` (deleted in 10), `WRITTEN_BLOCK_THEMED_TOKENS` (deleted in 8), `ContractLedger::COMPONENTS / THEMED_TOKENS / FIXED_TOKENS` in `test/support/contract_ledger.rb` (Task 2); `ThemeCss::Block`, `ThemeCss.entry(folder, root:, blocks:)`, `BlockTypes.theme_css_blocks(root:)` (Task 3, used in 6, 8); `TileSummaryComponent::LOOKS` and the parts `[:text, s]`, `[:mono, s]`, `[:word, key, values]`, `[:hint, key, values]` (Task 4, used in 8, 9); `HeldFields::CMS_ACTIONS`, `WRITTEN_TYPE_ACTIONS` (deleted in 8), `.allowed_actions` (Task 4); `sampled_types`, `sample_block(page, type, section:)`, `sample_every_type(page)`, `assert_every_type_built(names)` (Task 5, used in 6, 7–11); `TestTypes.declare(t)` (Task 6, used in 10); `ContentSpiel::Plugins.block_types`, `.register_block_types(registry)`, `.remove(hook)`, `Hook`, `Registrar` (Task 6); `with_gallery_album` (Task 6); `BlockTypes::Code.summary`, `SUMMARY_LENGTH`, `BlockTypes::PostList.summary` (Tasks 8, 9); the tile keys `types.code.empty`, `types.post_list.any_type`, `types.post_list.tag` (Tasks 8, 9); `BlockTypeGenerator::TYPES_MARKER`, `PUBLIC_MARKER`, `TILE_MARKER` (Task 11); `Rails.application.config.x.theme_booted` (Task 2).
