# Contrast and buttons — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every boundary in CS Studio and on the default site that identifies a control or a state reaches 3:1, every text 4.5:1, dark mode's grounds step apart, one button system (one primary, outlined secondaries, a clear disabled look, inverted selected states, outline-free badges), block-type icons and the page tree's state marks, and the four small editor fixes, with every promised ratio held by a test.

**Architecture:** Token values change in `app/assets/tailwind/content-spiel.css` (CS Studio, three new tokens: `--cs-field-line`, `--cs-graph-page`, `--cs-graph-tree`) and in the default theme's `tokens.css` (values only, no new `--th-` token). Two contrast tests share one measuring module: `test/lib/admin_contrast_test.rb` (new) for CS Studio, `test/integration/design_tokens_test.rb` for the site. Static guards in `test/lib/admin_design_rules_test.rb` hold the rules a class string can break (control outlines, label sizes). A block type declares its icon (`t.icon`), read by one component in three places; the tree's chips become one mark component.

**Tech Stack:** Rails 8.1, ViewComponent, Tailwind 4 (`tailwindcss-ruby` 4.3; `not-disabled:`, `not-aria-busy:`, opacity modifiers and `--text-*--font-weight` are used), Stimulus, the Mind graph's canvas modules, Minitest + fixtures, Capybara on Cuprite.

**Spec:** `docs/superpowers/specs/2026-10-15-contrast-and-buttons-design.md` (read it whole: the token tables, the 21 Rulings and "What is not in this pull request" bind every task). The design answers it rests on are `.superpowers/design-answers/2026-10-15-contrast-and-icons.md`.

## Global Constraints

- Read `CLAUDE.md` first; its rules bind. Read `docs/reference/design-system.md` before Tasks 1–4 and 9, `docs/reference/theming.md` before Task 8, `docs/reference/cs-studio-shell-and-dashboard.md` before Tasks 6 and 7, `docs/reference/content-blocks-and-types.md` before Task 5, `docs/reference/publishing.md` ("Publishing::State") before Task 6, `docs/reference/i18n.md` before Tasks 3 and 6.
- Token values are the spec's tables, exactly: light `--cs-field-line: #808186`, dark `#74757b`; light `--cs-line-strong: rgba(20,20,23,0.28)`, `--cs-line: rgba(20,20,23,0.14)`, `--cs-sunken: #e6e4dd`, `--cs-meta: #5f6065`, `--cs-dim: #46474c`; dark `--cs-paper: #0c0d0f`, `--cs-chrome: #111214`, `--cs-surface: #1b1c20`, `--cs-sunken: #28292e`, `--cs-line-strong: rgba(237,237,238,0.26)`, `--cs-line: rgba(237,237,238,0.13)`, `--cs-meta: #9c9da3`, `--cs-cat-5: oklch(0.74 0.07 260)`; `--cs-graph-page` light `var(--cs-ink)`, dark `#d9d9dc`; `--cs-graph-tree` light `var(--cs-dim)`, dark `rgba(169,170,175,0.6)`. Site: light `--th-sunken: #e6e4dd`, `--th-line: rgba(20,20,23,0.14)`; dark `--th-line: rgba(237,237,238,0.13)`, `--th-band-strong: #34353a`, `--th-on-band-strong: #ededee`, `--th-on-band-strong-dim: #c0c1c6`, `--th-on-band-strong-accent: oklch(0.82 0.09 250)`.
- **No `--th-` token is added, renamed or removed** (`Theme::Contract` is a promise to themes outside this repository). Changing a value and a contract row's description is allowed.
- Colour literals live only in `content-spiel.css` and `tokens.css`; CS Studio sources use tokens (`test/lib/admin_design_rules_test.rb`); no `dark:` variant but `dark:scheme-dark`.
- New CS Studio strings are locale keys; this plan adds none (the tree marks read the status chip's and the unpublished chip's existing keys by their full names, Ruling 9).
- Never define an `Admin::` constant named after a top-level domain (`test/lib/admin_namespace_shadow_test.rb`).
- Every test command is prefixed `PGGSSENCMODE=disable`. One file: `PGGSSENCMODE=disable bin/rails test <path>`. Before a system test or a test that fetches a built stylesheet (`design_tokens_test.rb`): `bin/rails tailwindcss:build && bin/rails theme_css:build`, and **never a build while tests run**. Never two test runs at once (worktrees share the test databases). A system test is run one file at a time; the full browser suite is Task 10's, at `PARALLEL_WORKERS=6`, on a quiet machine (`sysctl -n vm.loadavg`).
- System tests: `press`, not `click`; no fixed `sleep`; a test that resizes the window or changes an element's style for a measurement puts it back in an `ensure`; any JavaScript error fails the test.
- Commits: one per task, conventional subject (`feat:`, `fix:`, `test:`, `docs:`), never `--no-verify`, ending with exactly:

```
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT
```

- Scratch files only in a `mktemp -d` directory, deleted by name. Nothing is pushed.
- No guide text in this repository: the guide pages are named in the PR's "Documentation" section only (Task 10).

## Review Focus

1. **A busy button.** `admin--ui--busy` disables "Test connection" while its request is out; under the new disabled look it must keep its variant's colours beside the spinner, and turn into the disabled look only when it is disabled for another reason (Task 3: `"Test connection keeps its look while it is busy"`).
2. **A long save message in a card's header.** Moving the status line into the header row must not push the "⋯" menu out of a narrow card when the line says "SAVED · ALSO CHANGED ELSEWHERE — RELOAD TO SEE THE LATEST" (Task 9: `"a long save message wraps in the header and leaves the menu inside the card"`).
3. **An outside type with no icon.** A block type registered through the hook names no icon: its tile must keep its visible name, and the picker and the card must draw it without an empty gap or a raise (Task 5: `"a type that names no icon keeps its name on the tile and draws no icon anywhere"`).
4. **A scheduled page with unpublished changes in the tree.** One mark, not two, and both facts in its name (Task 6: `"a scheduled page with unpublished changes has one mark that names both"`).
5. **A selected filter pill with the keyboard's focus, in dark.** The accent ring is 1.96:1 on a dark selected pill: the paper ring must be what is drawn (Task 4: `"a selected pill reached with the keyboard is ringed in paper"`, and Task 1's paper-on-ink ratio).

---

### Task 1: The measuring, and CS Studio's tokens

**Files:**
- Create: `test/support/contrast_measure.rb`
- Modify: `test/test_helper.rb` (require it, beside the other `require_relative "support/…"` lines)
- Modify: `test/integration/design_tokens_test.rb` (include the module; delete its private `resolve_colour`, `mix`, `oklch_to_linear_srgb`, `contrast`)
- Create: `test/lib/admin_contrast_test.rb`
- Modify: `app/assets/tailwind/content-spiel.css` (both colour blocks)
- Modify: `app/assets/tailwind/content-spiel.tailwind.css` (the `@theme inline` map)

**Interfaces:**
- Produces: `ContrastMeasure#resolve_colour(tokens, name, under: nil, inside: {})` → linear sRGB `[r, g, b]` (reads hex, `oklch()`, `var(--th-…|--cs-…)`, `color-mix(in srgb, var(…) N%, transparent)` and `rgba(r,g,b,a)`; the last two need `under:`), `ContrastMeasure#contrast(one, other)` → Float, `ContrastMeasure#mix(top, under, share)`; `AdminContrastTest#schemes` → `{ light: {…}, dark: {…} }`; `AdminContrastTest#each_scheme { |scheme, colour| }` where `colour.(name, under: nil)` takes a token NAME for `under`; the utility `border-field-line` (`--color-field-line`); `text-label` at weight 500.

- [ ] **Step 1: Take the measuring out of `design_tokens_test.rb` into a module, and teach it `rgba()`**

Create `test/support/contrast_measure.rb`:

```ruby
# Contrast as WCAG 2.x measures it, for the two tests that hold the tokens'
# pairs: CS Studio's (`test/lib/admin_contrast_test.rb`) and the default
# theme's (`test/integration/design_tokens_test.rb`). Taken out of the
# second so both measure alike (contrast and buttons spec, "Testing").
module ContrastMeasure
  TOKEN = /--(?:th|cs)-[\w-]+/

  # A token's colour as linear-light sRGB, following `var()` to its value.
  # Hex and `oklch()` are the two notations the opaque tokens use; a colour
  # thinned out with `color-mix(… <share>%, transparent)` or written as
  # `rgba()` is painted over `under`, which a caller that expects one hands in.
  #
  # `inside` is what a band declares for everything in it. A name it
  # declares is the band's value, whose own `var()`s are read inside the
  # band too; any other name is the page's, computed on the page with the
  # page's values, as a custom property is inherited: computed.
  def resolve_colour(tokens, name, under: nil, inside: {})
    return resolve_colour(tokens, name, under: under) if inside.any? && !inside.key?(name)

    value = inside.fetch(name) { tokens.fetch(name) }.to_s.strip
    case value
    when /\Avar\((#{TOKEN})\)\z/o then resolve_colour(tokens, $1, under: under, inside: inside)
    when /\A#(\h{6})\z/ then $1.scan(/../).map { |pair| decode(pair.hex / 255.0) }
    when /\Aoklch\(([\d.]+) ([\d.]+) ([\d.]+)\)\z/ then oklch_to_linear_srgb($1.to_f, $2.to_f, $3.to_f)
    when /\Acolor-mix\(in srgb, var\((#{TOKEN})\) ([\d.]+)%, transparent\)\z/o
      under or flunk("#{name} is a thinned colour and nothing was named for it to be painted over")
      mix(resolve_colour(tokens, $1, inside: inside), under, $2.to_f / 100)
    when /\Argba\((\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\)\z/
      under or flunk("#{name} is a translucent colour and nothing was named for it to be painted over")
      mix([ $1, $2, $3 ].map { |channel| decode(channel.to_i / 255.0) }, under, $4.to_f)
    else flunk("#{name} is neither a hex colour, oklch(), rgba() nor a colour thinned with color-mix(): #{value}")
    end
  end

  # `color-mix(in srgb, top <share>, transparent)` (or `rgba()`) painted over
  # `under`: mixed in the encoded values, as a browser does, from and to
  # linear light.
  def mix(top, under, share)
    top.zip(under).map { |one, other| decode(encode(one) * share + encode(other) * (1 - share)) }
  end

  def contrast(one, other)
    light, dark = [ one, other ].map { |rgb| rgb.zip([ 0.2126, 0.7152, 0.0722 ]).sum { |value, weight| value * weight } }.minmax.reverse
    (light + 0.05) / (dark + 0.05)
  end

  # Björn Ottosson's OKLab to linear sRGB matrices; out-of-gamut channels
  # are clipped, as a browser does when it paints the colour on an sRGB
  # screen.
  def oklch_to_linear_srgb(lightness, chroma, hue)
    a = chroma * Math.cos(hue * Math::PI / 180)
    b = chroma * Math.sin(hue * Math::PI / 180)
    l = (lightness + 0.3963377774 * a + 0.2158037573 * b)**3
    m = (lightness - 0.1055613458 * a - 0.0638541728 * b)**3
    s = (lightness - 0.0894841775 * a - 1.2914855480 * b)**3
    [ 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
      -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
      -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s ].map { |channel| channel.clamp(0.0, 1.0) }
  end

  private

  def decode(value) = value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4

  def encode(value) = value <= 0.0031308 ? value * 12.92 : 1.055 * value**(1 / 2.4) - 0.055
end
```

In `test/test_helper.rb`, after `require_relative "support/log_capture"`, add:

```ruby
require_relative "support/contrast_measure"
```

In `test/integration/design_tokens_test.rb`: add `include ContrastMeasure` as the first line of the class body, and delete the four private methods `resolve_colour`, `mix`, `oklch_to_linear_srgb` and `contrast` (with their comments). Keep `helpers`, `theme_tokens`, `band_values`, `stylesheet` and `code_grounds`.

- [ ] **Step 2: Run the site's test to see the move changed nothing**

Run: `bin/rails tailwindcss:build && bin/rails theme_css:build && PGGSSENCMODE=disable bin/rails test test/integration/design_tokens_test.rb`
Expected: PASS (every test as before).

- [ ] **Step 3: Write the failing CS Studio contrast test**

Create `test/lib/admin_contrast_test.rb`:

```ruby
require "test_helper"

# Contrast and buttons spec, "C1": CS Studio's token pairs, measured as
# `design_tokens_test.rb` measures the site's. Text is 4.5:1 (WCAG 1.4.3);
# a boundary that identifies a control or a state is 3:1 (1.4.11); a
# boundary that only groups is held above the floor it reached, so a later
# change cannot quietly take it back, and below 3:1, where it would be an
# outline.
class AdminContrastTest < ActiveSupport::TestCase
  include ContrastMeasure

  STYLESHEET = Rails.root.join("app/assets/tailwind/content-spiel.css")
  GROUNDS = %w[--cs-paper --cs-surface --cs-sunken --cs-chrome].freeze
  # Where a control stands: a card (surface), the page (paper), the
  # toolbar and a tinted card (sunken).
  FIELD_GROUNDS = %w[--cs-paper --cs-surface --cs-sunken].freeze

  # `content-spiel.css`'s two colour blocks as { "--cs-name" => "value" }.
  def schemes
    css = STYLESHEET.read.gsub(%r{/\*.*?\*/}m, "")
    { light: css[/:root, \[data-theme="light"\]\s*\{(.*?)\}/m, 1], dark: css[/\[data-theme="dark"\]\s*\{(.*?)\}/m, 1] }
      .transform_values { |block| block.scan(/(--cs-[\w-]+):\s*([^;]+);/).to_h.transform_values(&:strip) }
  end

  # Each scheme's name and a lambda: a token's colour, a translucent one
  # painted over the token named `under`.
  def each_scheme
    schemes.each do |scheme, tokens|
      yield scheme, ->(name, under: nil) { resolve_colour(tokens, name, under: under && resolve_colour(tokens, under)) }
    end
  end

  def assert_ratio(minimum, one, other, message)
    ratio = contrast(one, other)
    assert_operator ratio, :>=, minimum, "#{message} is #{ratio.round(2)}:1"
  end

  test "ink, dim, meta and the accent are 4.5:1 or better on every ground, in both schemes" do
    each_scheme do |scheme, colour|
      GROUNDS.product(%w[--cs-ink --cs-dim --cs-meta --cs-accent]).each do |ground, ink|
        assert_ratio(4.5, colour.(ink), colour.(ground), "#{ink} on #{ground} (#{scheme})")
      end
    end
  end

  test "dim stays a step above meta on every ground" do
    each_scheme do |scheme, colour|
      GROUNDS.each do |ground|
        assert_operator contrast(colour.("--cs-dim"), colour.(ground)), :>, contrast(colour.("--cs-meta"), colour.(ground)), "#{ground} (#{scheme})"
      end
    end
  end

  test "a control's outline, --cs-field-line, is 3:1 or better on every ground a control stands on" do
    each_scheme do |scheme, colour|
      FIELD_GROUNDS.each { |ground| assert_ratio(3.0, colour.("--cs-field-line"), colour.(ground), "--cs-field-line on #{ground} (#{scheme})") }
    end
  end

  # The translated dot (ok), the scheduled dot (warn), the changes dot (dim)
  # and the draft ring (meta), on a card and in the tree's column.
  test "a state mark is 3:1 or better on the surface and the tree's chrome" do
    each_scheme do |scheme, colour|
      %w[--cs-surface --cs-chrome].product(%w[--cs-ok --cs-warn --cs-dim --cs-meta]).each do |ground, mark|
        assert_ratio(3.0, colour.(mark), colour.(ground), "#{mark} on #{ground} (#{scheme})")
      end
    end
  end

  test "a selected state is seen: the tree row's ink bar, a selected pill's words and its paper focus ring, and the accent ring at rest" do
    each_scheme do |scheme, colour|
      assert_ratio(3.0, colour.("--cs-ink"), colour.("--cs-sunken"), "the selected row's bar (#{scheme})")
      assert_ratio(4.5, colour.("--cs-paper"), colour.("--cs-ink"), "a selected pill's words and ring (#{scheme})")
      assert_ratio(3.0, colour.("--cs-accent"), colour.("--cs-surface"), "the focus ring on a pill at rest (#{scheme})")
    end
    dark = schemes[:dark]
    assert_operator contrast(resolve_colour(dark, "--cs-accent"), resolve_colour(dark, "--cs-ink")), :<, 3.0,
      "the reason for the paper ring: the accent on a dark selected pill is too faint"
  end

  test "a line that only groups is stronger than it was and still no outline" do
    each_scheme do |scheme, colour|
      surface = colour.("--cs-surface")
      line = contrast(colour.("--cs-line", under: "--cs-surface"), surface)
      strong = contrast(colour.("--cs-line-strong", under: "--cs-surface"), surface)
      assert_operator line, :>=, 1.3, "--cs-line (#{scheme}) is #{line.round(2)}:1"
      assert_operator strong, :>=, 1.8, "--cs-line-strong (#{scheme}) is #{strong.round(2)}:1"
      assert_operator strong, :<, 3.0, "a strong line at 3:1 would be an outline: that is --cs-field-line (#{scheme})"
    end
  end

  test "the grounds step apart: sunken from surface in both schemes, and dark's surface from its paper" do
    each_scheme { |scheme, colour| assert_ratio(1.15, colour.("--cs-sunken"), colour.("--cs-surface"), "sunken against surface (#{scheme})") }
    dark = schemes[:dark]
    assert_operator contrast(resolve_colour(dark, "--cs-surface"), resolve_colour(dark, "--cs-paper")), :>=, 1.12
  end

  test "each of the six type hues is 3:1 or better on the surface, and cat-5 has left cat-1's side in dark" do
    each_scheme do |scheme, colour|
      (1..6).each { |slot| assert_ratio(3.0, colour.("--cs-cat-#{slot}"), colour.("--cs-surface"), "--cs-cat-#{slot} (#{scheme})") }
    end
    assert_equal "oklch(0.74 0.07 260)", schemes[:dark]["--cs-cat-5"]
  end

  test "the measuring can fail: the grouping line is no outline, a translucent colour needs a ground, and an unread notation is refused" do
    tokens = { "--cs-surface" => "#ffffff", "--cs-line" => "rgba(20,20,23,0.14)", "--cs-odd" => "hsl(0 0% 50%)" }
    surface = resolve_colour(tokens, "--cs-surface")

    assert_operator contrast(resolve_colour(tokens, "--cs-line", under: surface), surface), :<, 3.0
    assert_raises(Minitest::Assertion) { resolve_colour(tokens, "--cs-line") }
    assert_raises(Minitest::Assertion) { resolve_colour(tokens, "--cs-odd") }
  end

  test "the map gives the field line a utility and every label its weight" do
    map = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read
    assert_includes map, "--color-field-line: var(--cs-field-line);"
    assert_includes map, "--text-label--font-weight: 500;"
  end
end
```

- [ ] **Step 4: Run it to see it fail**

Run: `PGGSSENCMODE=disable bin/rails test test/lib/admin_contrast_test.rb`
Expected: FAIL — the field-line test errors with `KeyError: key not found: "--cs-field-line"`; the line test says `--cs-line (light) is 1.23:1`; the grounds test says the dark surface against its paper is 1.07; the hues test expects `oklch(0.74 0.07 260)`; the map test misses `--color-field-line`. "The measuring can fail" passes.

- [ ] **Step 5: Change the tokens**

In `app/assets/tailwind/content-spiel.css`, light block (`:root, [data-theme="light"] {`), replace:

```css
  --cs-sunken: #ecebe6;
  --cs-ink: #141417;
  --cs-dim: #55565b;
  --cs-meta: #6c6d72;
  --cs-line: rgba(20,20,23,0.10);
  --cs-line-strong: rgba(20,20,23,0.20);
```

with:

```css
  --cs-sunken: #e6e4dd;
  --cs-ink: #141417;
  --cs-dim: #46474c;
  --cs-meta: #5f6065;
  /* A line that only groups (a card, a table's rows) and a stronger one (a
     panel, a table's header rule, a chip that is no control): decoration,
     below 3:1 on purpose. Everything pressed or typed into is outlined in
     `--cs-field-line`, 3:1 or better on paper, surface and sunken in both
     schemes (contrast and buttons spec, C1 and Ruling 1;
     `test/lib/admin_contrast_test.rb`). */
  --cs-line: rgba(20,20,23,0.14);
  --cs-line-strong: rgba(20,20,23,0.28);
  --cs-field-line: #808186;
```

Dark block (`[data-theme="dark"] {`), replace:

```css
  --cs-paper: #0f1012;
  --cs-surface: #17181b;
  --cs-sunken: #212226;
  --cs-ink: #ededee;
  --cs-dim: #a9aaaf;
  --cs-meta: #8e8f95;
  --cs-line: rgba(237,237,238,0.09);
  --cs-line-strong: rgba(237,237,238,0.18);
```

with:

```css
  --cs-paper: #0c0d0f;
  --cs-surface: #1b1c20;
  --cs-sunken: #28292e;
  --cs-ink: #ededee;
  --cs-dim: #a9aaaf;
  --cs-meta: #9c9da3;
  --cs-line: rgba(237,237,238,0.13);
  --cs-line-strong: rgba(237,237,238,0.26);
  --cs-field-line: #74757b;
```

and in the same dark block replace `--cs-chrome: #131416;` with `--cs-chrome: #111214;` and `--cs-cat-5: oklch(0.74 0.07 230);` with `--cs-cat-5: oklch(0.74 0.07 260);   /* away from cat-1's teal (design answer D2) */`.

In `app/assets/tailwind/content-spiel.tailwind.css`, in `@theme inline`, after `--color-line-strong: var(--cs-line-strong);` add `--color-field-line: var(--cs-field-line);`, and after `--text-label: var(--cs-t-label);` add:

```css
  /* Every mono label is 11px at weight 500 (design answer C1: 10px thin
     read faint); an explicit `font-*` class beside it still wins. */
  --text-label--font-weight: 500;
```

- [ ] **Step 6: Run both contrast tests**

Run: `PGGSSENCMODE=disable bin/rails test test/lib/admin_contrast_test.rb test/lib/admin_design_rules_test.rb`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add test/support/contrast_measure.rb test/test_helper.rb test/integration/design_tokens_test.rb test/lib/admin_contrast_test.rb app/assets/tailwind/content-spiel.css app/assets/tailwind/content-spiel.tailwind.css
git commit -m "feat: CS Studio's tokens reach 3:1 where they mark a control, and every pair is measured

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 2: Controls outlined in the field line, labels at 11px, the translation circle

**Files:**
- Modify: `test/lib/admin_design_rules_test.rb` (`SOURCE_DIRECTORIES` gains `javascript/notes`; three tests)
- Modify (one line each, `border-line-strong` → `border-field-line`; the list is in Step 3): 41 lines in 31 files under `app/helpers`, `app/components/admin`, `app/views/admin` and `app/javascript`
- Modify: every file under the design rules' directories holding `text-[10px]` or a mono `text-[11px]` (Step 4)
- Modify: `app/assets/tailwind/content-spiel.tailwind.css` (`.cs-select`, `.cs-toggle`, the invalid-border fallback, the prefix input, two 10px counts)
- Modify: `app/components/admin/ui/translation_chip_component.rb`, `app/components/admin/ui/language_tabs_component.html.erb`
- Test: `test/components/admin/ui/translation_chip_component_test.rb`, `test/components/admin/ui/language_tabs_component_test.rb`

**Interfaces:**
- Consumes: `border-field-line`, `text-label` at 500 (Task 1).
- Produces: `AdminDesignRulesTest::CONTROL_SOURCES`, `CONTROL_STATE`, `STRONG_LINE_ALLOWED`; the translation chip's mark spans `[data-translation-mark=complete|missing]`.

- [ ] **Step 1: Write the failing guards**

In `test/lib/admin_design_rules_test.rb`, add `javascript/notes` to `SOURCE_DIRECTORIES` (after `javascript/mind_graph`; its `merge.js` builds markup), and add before the `private`-free end of the class:

```ruby
  # Contrast and buttons spec (C1): a boundary that identifies a control is
  # `--cs-field-line`, 3:1 on every ground; `--cs-line-strong` only groups.
  # Read line by line: a line whose classes make it pressable or typed into
  # (a hover, a focus, a checked state, a placeholder, a pointer cursor)
  # draws no strong line. A control whose line says none of those (a
  # segmented group's frame, the drop zone) is not seen here: the spec lists
  # them and review holds them. The public layouts are the theme's, whose
  # outline token is `--th-meta` (`design_tokens_test.rb`).
  CONTROL_SOURCES = (ADMIN_SOURCES + [ Rails.root.join("app/helpers/setup_helper.rb").to_s ])
    .reject { |path| path.start_with?(Rails.root.join("app/views/layouts/public").to_s) }
  CONTROL_STATE = /(?<![\w-])(?:hover|focus|focus-within|focus-visible|has-checked|has-\[:checked\]|placeholder):|\bcursor-pointer\b/
  STRONG_LINE_ALLOWED = {
    "data-mind-graph-card" => "the graph's card is a panel that takes the focus; its outline is the focus ring",
    'CARD = "group block w-full overflow-hidden' => "a media tile is told by its picture; its hover line only groups"
  }.freeze

  test "a pressable or typed-into element is outlined in border-field-line, never border-line-strong" do
    offences = CONTROL_SOURCES.flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, index|
        next unless line.include?("line-strong") && line.match?(CONTROL_STATE)
        next if STRONG_LINE_ALLOWED.keys.any? { |marker| line.include?(marker) }

        "#{Pathname(path).relative_path_from(Rails.root)}:#{index + 1}"
      end
    end
    assert_empty offences
  end

  test "every allowed strong line is still there" do
    STRONG_LINE_ALLOWED.each_key { |marker| assert CONTROL_SOURCES.any? { |path| File.read(path).include?(marker) }, marker }
  end

  test "the stylesheet's controls draw their outline in --cs-field-line, and no count is under 11px" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    rule = ->(selector) { css[/(?:^|\})\s*#{Regexp.escape(selector)}\s*\{([^}]*)\}/m, 1].to_s }

    assert_match(/border:\s*1px solid var\(--cs-field-line\);/, rule.(".cs-select"))
    assert_match(/border:\s*1px solid var\(--cs-field-line\);/, rule.(".cs-toggle"))
    assert_includes css, "var(--cs-field-invalid-border, var(--cs-field-line))"
    assert_match(/\.admin-prefix-input:not\(:focus-within\)\s*\{\s*border-color:\s*var\(--cs-field-line\);/, css)
    assert_no_match(/font-size:\s*10px/, css)
  end

  # Design answer C1: "10px thin looks faint: 11px at weight 500 everywhere".
  test "no text under 11px in CS Studio's markup, and a mono label is text-label" do
    assert_empty design_offences(/text-\[10px\]/)
    assert_empty design_offences(/font-cs-mono[^"'`]*text-\[11px\]|text-\[11px\][^"'`]*font-cs-mono/)
  end
```

In `test/components/admin/ui/translation_chip_component_test.rb`, replace the first two tests with:

```ruby
  test "done is a solid chip with a filled ok dot" do
    render_inline(Admin::Ui::TranslationChipComponent.new(state: :complete, locale: "de"))
    assert_selector ".admin-translation-chip.border-line-strong.text-ink[data-translation-state=complete][data-locale=de]", exact_text: "de"
    assert_selector ".admin-translation-chip [data-translation-mark=complete][class~='bg-ok'][class~='rounded-full'][aria-hidden=true]"
    assert_selector "[role=img][aria-label='Deutsch: translated'][title='Translated']"
  end

  test "missing is dashed with a hollow ring in the field line, 1.5px, never red" do
    render_inline(Admin::Ui::TranslationChipComponent.new(state: :missing, locale: "de"))
    assert_selector ".admin-translation-chip.border-dashed.text-meta", exact_text: "de"
    assert_selector ".admin-translation-chip [data-translation-mark=missing][class~='border-field-line'][class~='border-[1.5px]'][aria-hidden=true]"
    assert_selector "[aria-label='Deutsch: not translated'][title='Not translated']"
    assert_no_selector "[class*=danger]"
  end
```

In `test/components/admin/ui/language_tabs_component_test.rb`, replace `assert_selector "span.border-meta[data-language-state=missing]"` with:

```ruby
    assert_selector "span[data-language-state=missing][class~='border-field-line'][class~='border-[1.5px]']"
```

- [ ] **Step 2: Run them to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/lib/admin_design_rules_test.rb test/components/admin/ui/translation_chip_component_test.rb test/components/admin/ui/language_tabs_component_test.rb`
Expected: FAIL — the outline guard lists 30 lines (`app/helpers/setup_helper.rb:5`, `…:23`, `app/components/admin/ui/button_component.rb:17`, …); the stylesheet test misses `--cs-field-line` in `.cs-select`; the label test lists 24 `text-[10px]` and 12 mono `text-[11px]`; the chip and tab tests miss their marks.

- [ ] **Step 3: Outline every control in the field line**

These line numbers are `5e4db8ac`'s (no earlier task touches these files). Run from the worktree's root:

```bash
ruby -e '
  lines = {
    "app/helpers/setup_helper.rb" => [ 5, 23 ],
    "app/javascript/rich_text/popover.js" => [ 18, 23 ],
    "app/components/admin/ui/button_component.rb" => [ 17, 21 ],
    "app/components/admin/ui/chip_input_component.html.erb" => [ 20 ],
    "app/components/admin/ui/prefix_input_component.rb" => [ 31 ],
    "app/components/admin/ui/file_drop_component.html.erb" => [ 1, 6 ],
    "app/components/admin/ui/theme_switch_component.html.erb" => [ 2 ],
    "app/components/admin/ui/system_check_row_component.html.erb" => [ 19 ],
    "app/components/admin/editor_screen/header_component.html.erb" => [ 63, 110 ],
    "app/components/admin/editor_screen/new_post_form_component.html.erb" => [ 8 ],
    "app/components/admin/columns/rich_text_column_component.html.erb" => [ 45, 70 ],
    "app/components/admin/posts_screen/toolbar_component.html.erb" => [ 8, 13 ],
    "app/components/admin/media_library/toolbar_component.html.erb" => [ 15, 20 ],
    "app/views/admin/translations/index.html.erb" => [ 21 ],
    "app/components/admin/trash_screen/tabs_component.html.erb" => [ 1 ],
    "app/components/admin/audit_screen/toolbar_component.rb" => [ 24 ],
    "app/views/admin/mind_graph/show.html.erb" => [ 144, 204 ],
    "app/components/admin/shell/sidebar_component.html.erb" => [ 12 ],
    "app/components/admin/shell/top_bar_component.html.erb" => [ 13 ],
    "app/components/admin/notes_screen/drawer_component.html.erb" => [ 21 ],
    "app/components/admin/notes_screen/composer_component.html.erb" => [ 33 ],
    "app/components/admin/notes_screen/files_component.html.erb" => [ 17 ],
    "app/components/admin/translation_screen/translate_button_component.rb" => [ 41 ],
    "app/components/admin/translation_screen/suggestion_component.rb" => [ 48 ],
    "app/javascript/notes/merge.js" => [ 371 ],
    "app/javascript/mind_graph/card_notes.js" => [ 95, 105 ],
    "app/javascript/controllers/admin/translation/translate_controller.js" => [ 640 ],
    "app/javascript/media/upload_tiles.js" => [ 236 ],
    "app/views/admin/tags/index.html.erb" => [ 55 ],
    "app/components/admin/groups_screen/scope_editor_component.html.erb" => [ 11 ],
    "app/components/admin/groups_screen/scope_editor_component.rb" => [ 106 ]
  }
  lines.each do |path, numbers|
    source = File.readlines(path)
    numbers.each do |number|
      line = source.fetch(number - 1)
      abort "#{path}:#{number} holds no border-line-strong: #{line}" unless line.include?("border-line-strong")
      source[number - 1] = line.gsub("border-line-strong", "border-field-line")
    end
    File.write(path, source.join)
  end'
```

(The tags row's `hover:border-line-strong` becomes `hover:border-field-line` by the same substitution.)

In `app/assets/tailwind/content-spiel.tailwind.css`:
- in `.cs-select { … }` and in `.cs-toggle { … }` replace `border: 1px solid var(--cs-line-strong);` with `border: 1px solid var(--cs-field-line);` (two edits, each with its selector as context);
- replace `border-color: var(--cs-field-invalid-border, var(--cs-line-strong));` with `border-color: var(--cs-field-invalid-border, var(--cs-field-line));`;
- replace `.admin-column:not(:has(> [id$="-errors"] > p)) .admin-prefix-input:not(:focus-within) { border-color: var(--cs-line-strong); }` with the same rule ending `{ border-color: var(--cs-field-line); }`;
- replace `.admin-block-tile .admin-notes-marker { width: 18px; height: 18px; font-size: 10px; }` with `.admin-block-tile .admin-notes-marker { width: 18px; height: 18px; font-size: var(--cs-t-label); }`;
- replace `.admin-notes-marker--small[data-has-notes] { height: 18px; padding: 0 6px; font-size: 10px; }` with `.admin-notes-marker--small[data-has-notes] { height: 18px; padding: 0 6px; font-size: var(--cs-t-label); }`.

- [ ] **Step 4: Every mono label is `text-label`**

```bash
ruby -e '
  dirs = %w[views/admin views/layouts views/setup components/admin components/media components/public javascript/controllers javascript/media javascript/saving javascript/search javascript/rich_text javascript/mind_graph javascript/notes]
  Dir["app/{#{dirs.join(",")}}/**/*.{erb,rb,js}"].each do |path|
    text = File.read(path)
    changed = text.gsub("text-[10px]", "text-label").lines.map { |line| line.include?("font-cs-mono") ? line.gsub("text-[11px]", "text-label") : line }.join
    File.write(path, changed) if changed != text
  end'
git diff --stat
```

Expected: 24 lines with `text-[10px]` and 12 with mono `text-[11px]` changed (`git diff -U0 | grep -c "^+.*text-label"` is at least 36). The composer's hint (`text-[11px] text-meta`, no mono) is left as it is.

- [ ] **Step 5: Draw the translation circle**

In `app/components/admin/ui/translation_chip_component.rb`, replace the `STYLES` constant and `call` with:

```ruby
      # The mark after the language code (contrast and buttons spec, C1): a
      # translated language a filled dot in `ok`, a missing one a 1.5px ring
      # in the field line (3:1, a state mark), an outdated one the ↻ glyph.
      # The chip's own border is decoration. The mark is `aria-hidden`: the
      # chip's `aria-label` says the state.
      STYLES = {
        complete: { classes: "border-line-strong text-ink", mark: "size-[7px] rounded-full bg-ok" },
        missing: { classes: "border-dashed border-line-strong text-meta", mark: "size-[7px] rounded-full border-[1.5px] border-field-line" },
        outdated: { classes: "border-warn text-warn-ink", glyph: "↻" }
      }.freeze

      def call
        style = STYLES.fetch(@state)
        mark = style[:mark] && tag.span("", class: "inline-block shrink-0 #{style[:mark]}", aria: { hidden: true }, data: { translation_mark: @state })
        tag.span(safe_join([ @locale, mark || (" #{style[:glyph]}" if style[:glyph]) ].compact),
          class: "admin-translation-chip inline-flex items-center gap-1 rounded-cs border px-1 font-cs-mono text-label uppercase #{style[:classes]}",
          role: "img", title: tooltip,
          aria: { label: t(".aria_label.#{@state}", language: ::Locales.name(@locale, native: true)) },
          data: { locale: @locale, translation_state: @state })
      end
```

and update the class comment's "a glyph (none, ○, ↻)" to "a mark (a filled `ok` dot, a field-line ring, the ↻ glyph)".

In `app/components/admin/ui/language_tabs_component.html.erb`, replace `class: "size-[7px] shrink-0 rounded-full border border-meta"` with `class: "size-[7px] shrink-0 rounded-full border-[1.5px] border-field-line"`.

- [ ] **Step 6: Run the tests**

Run: `bin/rails tailwindcss:build && PGGSSENCMODE=disable bin/rails test test/lib/admin_design_rules_test.rb test/components/admin/ui test/components/admin/posts_screen test/integration/admin/posts_list_test.rb test/integration/admin/translations_overview_test.rb test/integration/design_tokens_test.rb`
Expected: PASS. If `test/components/admin/ui/button_component_test.rb` fails on `button.border-line-strong.text-danger-ink`, that selector now reads `button.border-field-line.text-danger-ink` (Task 3 rewrites the test; change only the class here).

- [ ] **Step 7: Commit**

```bash
git add -A app test
git commit -m "feat: every control is outlined in the field line, every label is 11px, and a translation's state is a dot or a ring

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 3: The button system and badges

**Files:**
- Modify: `app/components/admin/ui/button_component.rb`
- Modify: `app/javascript/controllers/admin/ui/busy_controller.js`
- Modify: `app/helpers/setup_helper.rb` (`setup_secondary_link_class`), `app/javascript/rich_text/popover.js` (`secondary`)
- Modify: `app/components/admin/editor_screen/publishing_state_component.html.erb` (Discard → `:ghost`)
- Modify: `app/components/admin/editor_screen/header_component.html.erb` ("View on site ↗")
- Modify: `app/views/admin/posts/index.html.erb` (the split button's divider)
- Modify: `app/components/admin/pages_screen/tree_component.html.erb` ("+ New page")
- Create: `app/components/admin/ui/badge_component.rb`, `test/components/admin/ui/badge_component_test.rb`, `test/components/previews/admin/ui/badge_component_preview.rb`
- Modify (badges): `app/components/admin/settings_screen/languages_card_component.html.erb:41`, `app/components/admin/groups_screen/list_component.html.erb:13`, `app/components/admin/users_screen/list_component.html.erb:15`, `app/components/admin/media_library/tile_component.html.erb:19-20`, `app/components/admin/notes_screen/thread_component.rb` (`origin_chip`)
- Modify (chips): `app/components/admin/ui/status_chip_component.html.erb`, `app/components/admin/ui/unpublished_chip_component.html.erb`, `app/components/admin/editor_screen/no_address_chip_component.html.erb`, `app/components/admin/ui/channel_chip_component.rb` and `.html.erb`, `app/javascript/mind_graph/card.js:161`
- Test: `test/components/admin/ui/button_component_test.rb`, `status_chip_component_test.rb`, `unpublished_chip_component_test.rb`, `channel_chip_component_test.rb`, `test/components/admin/editor_screen/header_component_test.rb`, `test/integration/admin/posts_list_test.rb`, `test/system/admin/ai_settings_test.rb`, `test/integration/design_tokens_test.rb`

**Interfaces:**
- Consumes: `border-field-line` (Task 1).
- Produces: `Admin::Ui::BadgeComponent.new(label:, tone: :neutral | :warn, **html)`, `BadgeComponent::TONES`; `ButtonComponent::VARIANT_CLASSES` with `not-disabled:hover:` hovers and the disabled look in `COMMON_CLASS`; `aria-busy="true"` on a busy button.

- [ ] **Step 1: Write the failing tests**

In `test/components/admin/ui/button_component_test.rb`, replace the `danger_text` test's first assertion with `assert_selector "button.border-field-line.text-danger-ink", text: "Move to trash"`, and add:

```ruby
  test "a secondary button is outlined in the field line and answers the pointer with an ink border, only while enabled" do
    render_inline Admin::Ui::ButtonComponent.new(label: "Preview", variant: :secondary)
    classes = page.find("button")["class"].split

    assert_includes classes, "border-field-line"
    assert_includes classes, "not-disabled:hover:border-ink"
    assert_not_includes classes, "hover:bg-sunken"
  end

  test "no variant answers the pointer while disabled: every hover is not-disabled:hover:" do
    Admin::Ui::ButtonComponent::VARIANT_CLASSES.each do |variant, classes|
      assert_empty classes.split.grep(/\Ahover:/), variant
    end
  end

  # Contrast and buttons spec (D1, Ruling 11): one disabled look for every
  # variant, sunken with meta words and a hairline, no accent and no opacity;
  # a busy button (`aria-busy`) keeps its variant's look.
  test "every variant is drawn disabled the same way, and a busy one is not" do
    Admin::Ui::ButtonComponent::VARIANT_CLASSES.each_key do |variant|
      render_inline Admin::Ui::ButtonComponent.new(label: "Save", variant: variant, disabled: true)
      classes = page.find("button[disabled]")["class"].split

      %w[disabled:not-aria-busy:border disabled:not-aria-busy:border-line disabled:not-aria-busy:bg-sunken disabled:not-aria-busy:text-meta aria-busy:cursor-progress].each do |name|
        assert_includes classes, name, variant
      end
      assert_empty classes.grep(/opacity-50/), variant
    end
  end
```

Create `test/components/admin/ui/badge_component_test.rb`:

```ruby
require "test_helper"

# Contrast and buttons spec (D1, Ruling 13): a badge says something and
# cannot be pressed, so it has a sunken fill and no outline; only a button has one.
class Admin::Ui::BadgeComponentTest < ViewComponent::TestCase
  test "a badge is a sunken mono label with no border, and passes its own attributes through" do
    render_inline Admin::Ui::BadgeComponent.new(label: "Default", data: { default_tag: true })
    classes = page.find("span[data-default-tag]", text: "Default")["class"].split

    assert_includes classes, "bg-sunken"
    assert_includes classes, "text-meta"
    assert_includes classes, "text-label"
    assert_empty classes.grep(/\Aborder/)
  end

  test "the warn tone is the warn tint with the warn ink" do
    render_inline Admin::Ui::BadgeComponent.new(label: "NO ALT", tone: :warn)
    assert_selector "span.bg-warn-tint.text-warn-ink", text: "NO ALT"
  end

  test "an unknown tone is a programming error" do
    assert_raises(ArgumentError) { Admin::Ui::BadgeComponent.new(label: "x", tone: :loud) }
  end
end
```

In `test/components/admin/ui/status_chip_component_test.rb` replace `".admin-status-chip.border-line-strong[data-status='#{status}']"` with `".admin-status-chip.bg-sunken:not([class*=border])[data-status='#{status}']"`. In `unpublished_chip_component_test.rb` replace `"span[data-unpublished-changes].border-line-strong"` with `"span[data-unpublished-changes].bg-sunken:not([class*=border])"`. In `channel_chip_component_test.rb` add to the test that asserts `.admin-channel-chip.text-meta` (line 15): `assert_selector ".admin-channel-chip.bg-sunken:not([class*=border])"`.

In `test/components/admin/editor_screen/header_component_test.rb` add:

```ruby
  test "a live record's Discard changes… is a ghost beside the one primary, and View on site is a plain link" do
    record = create_page(title: "About", published: true)
    render_header(record)

    assert_selector "header button.text-dim", text: "Discard changes…", visible: :all
    assert_no_selector "header button[class~='border-field-line']", text: "Discard changes…", visible: :all
    link = page.find("a[href='/about']", text: "View on site")
    assert_includes link["class"].split, "text-accent"
    assert_includes link["class"].split, "hover:underline"
    assert_not_includes link["class"].split, "underline"
  end
```

In `test/integration/admin/posts_list_test.rb` add:

```ruby
  test "the split button's divider is the on-accent colour at 40 percent" do
    get "/cs-studio/posts"
    assert_select "button[aria-label='Choose another type of post'][class~='border-on-accent/40']"
  end
```

In `test/system/admin/ai_settings_test.rb` add:

```ruby
  # Contrast and buttons spec, Ruling 11: a busy button is disabled but not
  # drawn as a disabled one; it keeps its variant's colours beside its spinner.
  test "Test connection keeps its look while it is busy" do
    site_settings(:default).update!(ai_api_key: KEY)
    GatedProvider.hold!
    visit "/cs-studio/settings"
    await_admin_controllers
    button = "button[form='settings-ai-test-form']"
    look = "(() => { const s = getComputedStyle(document.querySelector(#{button.to_json})); return [s.backgroundColor, s.color] })()"
    at_rest = page.evaluate_script(look)

    press "Test connection"
    assert_selector "#{button}[disabled][aria-busy='true']"
    assert_equal at_rest, page.evaluate_script(look)

    GatedProvider.release
    assert_selector "#{button}:not([aria-busy])", wait: 10
  end
```

In `test/integration/design_tokens_test.rb` add:

```ruby
  # The Tailwind 4 features the button system rests on are in the build.
  test "the product build carries the not-disabled hovers, the busy exception, the ink tint and the labels' weight" do
    css = stylesheet("tailwind.css")

    assert_match(/:not\(:disabled\)/, css)
    assert_match(/:not\(\[aria-busy=["']?true["']?\]\)/, css)
    assert_match(/\.text-label\s*\{[^}]*500/, css)
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bin/rails tailwindcss:build && PGGSSENCMODE=disable bin/rails test test/components/admin/ui test/components/admin/editor_screen/header_component_test.rb test/integration/admin/posts_list_test.rb test/integration/design_tokens_test.rb` and then `PGGSSENCMODE=disable bin/rails test test/system/admin/ai_settings_test.rb`
Expected: FAIL — `uninitialized constant Admin::Ui::BadgeComponent`, `hover:bg-sunken` in the secondary variant, the disabled classes missing, `opacity-50` present, the chips carry borders, Discard has `border-field-line`, View on site is `underline`, the divider is `border-on-accent`, the busy button has no `aria-busy`, the build has no `aria-busy` rule.

- [ ] **Step 3: The button component**

In `app/components/admin/ui/button_component.rb`, replace `VARIANT_CLASSES` and `COMMON_CLASS` with:

```ruby
      # Every hover is `not-disabled:hover:` (contrast and buttons spec, D1): a
      # disabled button never answers the pointer.
      VARIANT_CLASSES = {
        primary: "bg-accent text-on-accent not-disabled:hover:bg-accent-hover",
        # Outlined in the field line (3:1 on every ground); the pointer turns
        # the outline ink, and nothing else.
        secondary: "border border-field-line bg-surface text-ink not-disabled:hover:border-ink",
        # The trigger for a destructive action (spec §7): a secondary button --
        # same border, fill and hover -- whose label alone is red, so the one
        # solid red on screen is the confirm button inside the dialog it opens.
        danger_text: "border border-field-line bg-surface text-danger-ink not-disabled:hover:border-ink",
        # Solid red: a dialog's destructive confirm only. `text-white` is the
        # one literal colour the design allows (handoff §9 A1) -- on the red
        # fill white is right in both themes, unlike `on-accent`.
        danger: "bg-danger text-white not-disabled:hover:opacity-90",
        # Dialog Cancel, "Discard changes…" and other low-emphasis actions: no border, no fill.
        ghost: "text-dim not-disabled:hover:bg-sunken not-disabled:hover:text-ink"
      }.freeze

      # DISABLED is one look for every variant (D1): sunken, meta words, a
      # hairline, no accent and no opacity, so it can't read as a weak
      # primary (disabled is exempt from WCAG 1.4.11; the save bar's line says
      # why it is off). A BUSY button (`admin--ui--busy` sets `aria-busy`) is
      # disabled too but keeps its variant's look beside its spinner.
      COMMON_CLASS = "inline-flex cursor-pointer items-center justify-center gap-2 rounded-cs font-semibold transition-colors " \
                     "disabled:cursor-not-allowed disabled:not-aria-busy:border disabled:not-aria-busy:border-line " \
                     "disabled:not-aria-busy:bg-sunken disabled:not-aria-busy:text-meta aria-busy:cursor-progress".freeze
```

and in the class comment change "`:ghost` (a dialog's Cancel)" to "`:ghost` (a dialog's Cancel, the editors' Discard changes…)".

In `app/javascript/controllers/admin/ui/busy_controller.js`: in `begin`, after `button.disabled = true`, add `button.setAttribute("aria-busy", "true")`; in the `restore` closure, after `button.disabled = false`, add `button.removeAttribute("aria-busy")`; and add to the comment at the top: "It also says `aria-busy`, which keeps the button in its own colours: CS Studio's disabled look is for a button that is off, not one that is working."

In `app/helpers/setup_helper.rb`, `setup_secondary_link_class` becomes:

```ruby
  def setup_secondary_link_class
    "inline-block cursor-pointer rounded-cs border border-field-line px-4 py-2 text-ink hover:border-ink"
  end
```

In `app/javascript/rich_text/popover.js`, the `secondary:` entry becomes `secondary: "border border-field-line bg-surface text-ink hover:border-ink",`.

- [ ] **Step 4: Discard, View on site, the split button, + New page**

`app/components/admin/editor_screen/publishing_state_component.html.erb`: in the Discard button's render, `variant: :secondary` → `variant: :ghost`.

`app/components/admin/editor_screen/header_component.html.erb`: replace

```erb
        <%= link_to "View on site ↗", public_path, target: "_blank", rel: "noopener", class: "shrink-0 underline hover:text-ink" %>
```

with

```erb
        <%# A link like any other (design answer D1): sans, the accent, underlined under the pointer. %>
        <%= link_to "View on site ↗", public_path, target: "_blank", rel: "noopener", class: "shrink-0 font-cs text-[13px] text-accent hover:text-accent-hover hover:underline" %>
```

`app/views/admin/posts/index.html.erb`: in the menu's `button_class:`, `border-l border-on-accent` → `border-l border-on-accent/40`.

`app/components/admin/pages_screen/tree_component.html.erb`: replace the "+ New page" link's `class: "rounded-cs px-2 py-1 text-sm text-ink hover:bg-sunken"` with `class: "#{Admin::Ui::ButtonComponent::SMALL_CLASS} #{Admin::Ui::ButtonComponent::VARIANT_CLASSES[:secondary]}"` (a link keeps its `href` for the page without script; it only looks like the small button, as "New note" is one).

- [ ] **Step 5: The badge and the chips**

Create `app/components/admin/ui/badge_component.rb`:

```ruby
module Admin
  module Ui
    # A mono label that says something and cannot be pressed: DEFAULT,
    # BUILT-IN, OWNER, UNUSED, NO ALT, a note's language (contrast and
    # buttons spec, D1 and Ruling 13). A sunken fill and no border, so only a
    # button has an outline on a CS Studio screen. `:warn` is NO ALT's tint.
    # Anything else the caller needs on the tag (`data`, `id`) passes through.
    class BadgeComponent < AdminComponent
      TONES = { neutral: "bg-sunken text-meta", warn: "bg-warn-tint text-warn-ink" }.freeze
      CLASS = "inline-flex shrink-0 items-center rounded-cs px-1.5 py-0.5 font-cs-mono text-label uppercase tracking-mono".freeze

      def initialize(label:, tone: :neutral, **html)
        raise ArgumentError, "unknown badge tone #{tone.inspect}" unless TONES.key?(tone)

        @label = label
        @tone = tone
        @html = html
      end

      def call
        tag.span(@label, **@html, class: [ CLASS, TONES.fetch(@tone), @html[:class] ].compact.join(" "))
      end
    end
  end
end
```

Create `test/components/previews/admin/ui/badge_component_preview.rb`:

```ruby
module Admin
  module Ui
    # `Admin::Ui::BadgeComponent` (contrast and buttons spec, D1): neutral and warn.
    class BadgeComponentPreview < ViewComponent::Preview
      def neutral = render(Admin::Ui::BadgeComponent.new(label: "Default"))

      def warn = render(Admin::Ui::BadgeComponent.new(label: "NO ALT", tone: :warn))
    end
  end
end
```

Replace the badges' markup (each keeps its words and its data attribute):
- `languages_card_component.html.erb:41`: `<span class="rounded-cs border border-line-strong px-1.5 py-0.5 font-cs-mono text-label uppercase text-dim" data-default-tag>Default</span>` → `<%= render Admin::Ui::BadgeComponent.new(label: "Default", data: { default_tag: true }) %>`
- `groups_screen/list_component.html.erb:13`: the "Built-in" span → `<%= render Admin::Ui::BadgeComponent.new(label: "Built-in") %>`
- `users_screen/list_component.html.erb:15`: the "Owner" span inside the `if` → `<%= render Admin::Ui::BadgeComponent.new(label: "Owner") %>`
- `media_library/tile_component.html.erb:19-20`: the NO ALT span → `<%= render Admin::Ui::BadgeComponent.new(label: "NO ALT", tone: :warn) %>`, the UNUSED span → `<%= render Admin::Ui::BadgeComponent.new(label: "UNUSED") %>`
- `notes_screen/thread_component.rb` `origin_chip` → `render(Admin::Ui::BadgeComponent.new(label: written_on, data: { note_badge: "origin" }))`, and its comment becomes "A badge (`Admin::Ui::BadgeComponent`): it says the language the thread was written in and cannot be pressed."

The chips lose their border for the sunken fill:
- `status_chip_component.html.erb`: `rounded-cs border border-line-strong px-2` → `rounded-cs bg-sunken px-2`
- `unpublished_chip_component.html.erb` (full mode): `rounded-cs border border-line-strong px-2` → `rounded-cs bg-sunken px-2`
- `no_address_chip_component.html.erb`: `rounded-cs border border-line-strong px-2` → `rounded-cs bg-sunken px-2`
- `channel_chip_component.html.erb`: remove ` border` from the class string; `channel_chip_component.rb` `tone_class` → `channel == "mcp" ? "bg-accent-tint text-accent" : "bg-sunken text-meta"`
- `app/javascript/mind_graph/card.js:161`: `rounded-cs border border-line-strong px-2` → `rounded-cs bg-sunken px-2` (the card's copy of the status chip, kept in step by hand).

- [ ] **Step 6: Run the tests**

Run: `bin/rails tailwindcss:build && PGGSSENCMODE=disable bin/rails test test/components test/integration/admin test/integration/design_tokens_test.rb test/lib/admin_design_rules_test.rb test/lib/admin_i18n_test.rb` then `PGGSSENCMODE=disable bin/rails test test/system/admin/ai_settings_test.rb`, then `PGGSSENCMODE=disable bin/rails test test/system/admin/mind_graph_modules_test.rb` (the card's chip).
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A app test
git commit -m "feat: one button system: outlined secondaries with an ink hover, one disabled look, a busy button that keeps its own, and badges without an outline

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 4: Selected states: filter pills, the toolbar, the zoom buttons

**Files:**
- Modify: `app/components/admin/posts_screen/toolbar_component.rb` (`SEGMENT_CLASS`, and its comment)
- Modify: `app/components/admin/posts_screen/toolbar_component.html.erb`, `app/components/admin/media_library/toolbar_component.html.erb`, `app/views/admin/translations/index.html.erb` (the counts' `opacity-70`)
- Modify: `app/components/admin/trash_screen/tabs_component.rb` (`LINK_CLASS`, the current tab)
- Modify: `app/components/admin/columns/rich_text_column_component.rb` (`tool_button`), `.html.erb` (the Insert button's `button_class:`)
- Modify: `app/views/admin/mind_graph/show.html.erb` (the zoom group)
- Test: `test/components/admin/posts_screen/toolbar_component_test.rb`, `test/components/admin/columns/rich_text_column_component_test.rb`, `test/integration/admin/mind_graph_test.rb`, `test/system/admin/posts_list_test.rb`, `test/integration/design_tokens_test.rb`

**Interfaces:**
- Consumes: `border-field-line` on the groups and the toolbar (Task 2); the paper-on-ink ratio (Task 1).
- Produces: `Admin::PostsScreen::ToolbarComponent::SEGMENT_CLASS` with `has-[:checked]:bg-ink has-[:checked]:text-paper` and the paper ring; tool buttons with `aria-pressed:border-field-line aria-pressed:bg-surface`.

- [ ] **Step 1: Write the failing tests**

In `test/components/admin/posts_screen/toolbar_component_test.rb` add, inside the class:

```ruby
  # Contrast and buttons spec (D1): a selected pill is inverted, ink with
  # paper words (the accent tint was 1.13:1 against the others), and its
  # keyboard ring is paper, since the accent on dark ink is 1.96:1.
  test "a selected pill is inverted, its count with it, and its focus ring is paper" do
    classes = Admin::PostsScreen::ToolbarComponent::SEGMENT_CLASS.split

    %w[has-[:checked]:bg-ink has-[:checked]:text-paper has-[:checked]:has-[:focus-visible]:outline-paper has-[:checked]:has-[:focus-visible]:-outline-offset-4].each do |name|
      assert_includes classes, name
    end
    assert_empty classes.grep(/accent-tint/)
  end
```

In `test/components/admin/columns/rich_text_column_component_test.rb` add (rendered as the file's other tests render it, under the file's own setup):

```ruby
  test "the toolbar is sans; an active tool is a surface with a field-line border, and the pointer darkens the toolbar" do
    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", value: nil)
    heading = page.find("[role=toolbar] button[aria-label='Heading 2']")["class"].split

    assert_not_includes heading, "font-cs-mono"
    %w[border border-transparent hover:bg-ink/6 aria-pressed:border-field-line aria-pressed:bg-surface data-active:border-field-line data-active:bg-surface].each do |name|
      assert_includes heading, name
    end
    assert_empty heading.grep(/accent-tint/)
  end
```

In `test/integration/admin/mind_graph_test.rb` add:

```ruby
  test "the zoom buttons are 28px high with 13px labels, the figure 11px mono, in a group outlined in the field line" do
    sign_in_as(users(:one))
    get "/cs-studio/mind_graph"

    assert_select "[role=group][class~='border-field-line'] button[data-action='admin--mind-graph--graph#zoomIn'][class~='h-7'][class~='text-[13px]']"
    assert_select "[data-mind-graph-zoom][class~='text-label'][class~='font-cs-mono']"
  end
```

In `test/system/admin/posts_list_test.rb` add (the file's own setup signs in):

```ruby
  # Review focus 5: the accent ring would be 1.96:1 on a dark selected pill.
  test "a selected pill reached with the keyboard is ringed in paper, in both schemes" do
    visit "/cs-studio/posts"
    await_admin_controllers
    %w[light dark].each do |scheme|
      page.execute_script("document.documentElement.dataset.theme = #{scheme.to_json}")
      find_field("Search titles").send_keys(:tab)
      ring, paper = page.evaluate_script(<<~JS)
        (() => {
          const label = document.querySelector("label:has(#posts-scope-all)")
          const probe = document.createElement("span")
          probe.style.color = "var(--cs-paper)"
          document.body.append(probe)
          const colours = [ getComputedStyle(label).outlineColor, getComputedStyle(probe).color ]
          probe.remove()
          return colours
        })()
      JS
      assert_equal paper, ring, scheme
    end
  ensure
    page.execute_script("document.documentElement.dataset.theme = 'light'")
  end
```

In `test/integration/design_tokens_test.rb`, extend the build test of Task 3 with `assert_includes css, "bg-ink\\/6"` (the escaped class name in the built file).

- [ ] **Step 2: Run them to see them fail**

Run: `bin/rails tailwindcss:build && PGGSSENCMODE=disable bin/rails test test/components/admin/posts_screen/toolbar_component_test.rb test/components/admin/columns/rich_text_column_component_test.rb test/integration/admin/mind_graph_test.rb test/integration/design_tokens_test.rb` then `PGGSSENCMODE=disable bin/rails test test/system/admin/posts_list_test.rb`
Expected: FAIL — `accent-tint` in `SEGMENT_CLASS`, `font-cs-mono` on the tool button, no `h-7` zoom button, no `bg-ink\/6` in the build, the ring is the accent.

- [ ] **Step 3: Invert the pills**

In `app/components/admin/posts_screen/toolbar_component.rb`, replace `SEGMENT_CLASS` with:

```ruby
      # Selected is INVERTED (contrast and buttons spec, D1): ink with paper
      # words and count, the system's segmented look; the group around the
      # pills is outlined in the field line. The keyboard's ring is the
      # accent on a pill at rest and PAPER, 4px inside, on the selected one:
      # the accent on dark ink is 1.96:1 (`test/lib/admin_contrast_test.rb`).
      SEGMENT_CLASS = "flex cursor-pointer items-center gap-1.5 border-r border-line px-3 py-1.5 text-sm text-dim last:border-r-0 hover:bg-sunken " \
                      "has-[:checked]:bg-ink has-[:checked]:font-semibold has-[:checked]:text-paper has-[:checked]:hover:bg-ink " \
                      "has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:-outline-offset-2 has-[:focus-visible]:outline-accent " \
                      "has-[:checked]:has-[:focus-visible]:outline-paper has-[:checked]:has-[:focus-visible]:-outline-offset-4".freeze
```

In the three count spans (`posts_screen/toolbar_component.html.erb`, `media_library/toolbar_component.html.erb`, `admin/translations/index.html.erb`) replace `font-cs-mono text-label opacity-70` with `font-cs-mono text-label` (after Task 2 that is their class; the count is the pill's colour, paper when selected).

In `app/components/admin/trash_screen/tabs_component.rb`, the current tab's classes `bg-sunken font-semibold text-ink` become `bg-ink font-semibold text-paper` (the same control, Ruling 14).

- [ ] **Step 4: The toolbar and the zoom buttons**

In `app/components/admin/columns/rich_text_column_component.rb` `tool_button`, replace the class string with:

```ruby
          # Sans like every button (design answer D1). Active is a surface
          # with a field-line border and ink words (3:1 against the sunken
          # toolbar); the transparent border at rest keeps the size. The
          # pointer darkens the toolbar's ground by 6% of the ink.
          class: [ "admin-rich-text-button cursor-pointer whitespace-nowrap rounded-cs border border-transparent px-1.5 py-[3px] text-sm text-ink hover:bg-ink/6 aria-pressed:border-field-line aria-pressed:bg-surface data-active:border-field-line data-active:bg-surface", extra_class ].compact.join(" "),
```

In `rich_text_column_component.html.erb`, the Insert menu's `button_class:` becomes `"inline-flex cursor-pointer whitespace-nowrap items-center gap-1 rounded-cs px-2 py-1 text-sm text-ink hover:bg-ink/6"`.

In `app/views/admin/mind_graph/show.html.erb`, the zoom group's `class="inline-flex items-stretch overflow-hidden rounded-cs border border-field-line bg-surface text-sm text-ink"` becomes `class="inline-flex items-stretch overflow-hidden rounded-cs border border-field-line bg-surface text-[13px] text-ink"`, and `zoom_button` becomes:

```erb
            <% zoom_button = "inline-flex h-7 cursor-pointer items-center px-2.5 font-semibold hover:bg-sunken focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-accent" %>
```

(the figure between them is already `font-cs-mono text-label`).

- [ ] **Step 5: Run the tests**

Run: `bin/rails tailwindcss:build && PGGSSENCMODE=disable bin/rails test test/components test/integration/admin/mind_graph_test.rb test/integration/admin/posts_list_test.rb test/integration/design_tokens_test.rb test/lib/admin_design_rules_test.rb`, then one at a time: `PGGSSENCMODE=disable bin/rails test test/system/admin/posts_list_test.rb`, `… test/system/admin/rich_text_test.rb`, `… test/system/admin/media_library_test.rb`, `… test/system/admin/trash_test.rb`, `… test/system/admin/mind_graph_test.rb`.
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A app test
git commit -m "feat: selected pills are inverted with a paper focus ring, the toolbar shows what is on, and the zoom buttons are 28px

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 5: A block type declares its icon

**Files:**
- Modify: `app/models/content_model/block_type_definition.rb` (`ICONS`, `#icon`)
- Modify: `app/models/block_types/rich_text.rb`, `image.rb`, `code.rb`, `post_list.rb`, `section.rb` (one `t.icon` line each, after `t.label`)
- Modify: `app/views/admin/shared/_icon.html.erb` (`:posts` takes `size:`; four new branches)
- Create: `app/components/admin/editor_screen/block_icon_component.rb`
- Modify: `app/components/admin/editor_screen/block_picker_component.html.erb`, `block_card_component.html.erb`, `block_tile_component.html.erb`, `block_tile_component.rb`
- Test: `test/models/content_model/block_type_definition_test.rb`, `test/components/admin/editor_screen/block_icon_component_test.rb` (new), `block_picker_component_test.rb`, `block_card_component_test.rb`, `block_tile_component_test.rb`

**Interfaces:**
- Produces: `ContentModel::BlockTypeDefinition::ICONS = %w[pilcrow image code_xml posts columns_2]`; `definition.icon` → String or nil; `definition.icon "name"`; `Admin::EditorScreen::BlockIconComponent.new(definition:, place: :picker | :card | :tile)`, `BlockIconComponent::PLACES`; `[data-block-icon=<name>]` on the drawn span; `Admin::EditorScreen::BlockTileComponent#block_icon`, `#icon?`.

- [ ] **Step 1: Write the failing tests**

In `test/models/content_model/block_type_definition_test.rb` add:

```ruby
  test "a block type's icon is one CS Studio draws, or none" do
    definition = ContentModel::BlockTypeDefinition.new("x")
    assert_nil definition.icon

    definition.icon :pilcrow
    assert_equal "pilcrow", definition.icon
    error = assert_raises(ArgumentError) { ContentModel::BlockTypeDefinition.new("x").icon "rocket" }
    assert_match(/\Ax: icon is one of pilcrow, image, code_xml, posts, columns_2/, error.message)
  end
```

Create `test/components/admin/editor_screen/block_icon_component_test.rb`:

```ruby
require "test_helper"

# Contrast and buttons spec (C2, Rulings 6 and 7): a block type declares
# its icon, and CS Studio draws it in the picker (16px dim), on a card's
# head (14px dim) and on a section's tile (12px meta).
class Admin::EditorScreen::BlockIconComponentTest < ViewComponent::TestCase
  include GalleryAlbum

  test "every icon a block type may name is drawn by the icon partial" do
    ContentModel::BlockTypeDefinition::ICONS.each do |name|
      html = ApplicationController.render(partial: "admin/shared/icon", locals: { name: name.to_sym, size: "size-4" })
      assert_includes html, "<svg", name
      assert_includes html, "size-4", name
    end
  end

  test "every built-in block type declares its icon" do
    assert_equal({ "rich_text" => "pilcrow", "image" => "image", "code" => "code_xml", "post_list" => "posts", "section" => "columns_2" },
      BlockTypes.all.to_h { |type| [ type.name, type.icon ] }.slice(*BuiltInBlockTypes.names))
  end

  test "each place has its size and colour, and the icon is decoration" do
    { picker: %w[size-4 text-dim], card: %w[size-3.5 text-dim], tile: %w[size-3 text-meta] }.each do |place, (size, colour)|
      render_inline Admin::EditorScreen::BlockIconComponent.new(definition: BlockTypes.fetch(:code), place: place)
      assert_selector "span[data-block-icon=code_xml][aria-hidden=true][class~='#{colour}'] svg[class~='#{size}']"
    end
  end

  test "a type that names no icon draws nothing" do
    with_gallery_album do
      render_inline Admin::EditorScreen::BlockIconComponent.new(definition: BlockTypes.all.find { |type| type.name == "gallery/album" }, place: :picker)
      assert_no_selector "span"
    end
  end
end
```

In `block_picker_component_test.rb`, in the first test add:

```ruby
    assert_equal BlockTypes.all.map(&:icon), Capybara.string(rendered_content).all("#block-picker-end button").map { |button| button.first("[data-block-icon]", minimum: 0)&.[]("data-block-icon") }
```

and in the lane test add `assert_selector "#{picker} [role=menu] form button [data-block-icon]", count: offered.size, visible: :all`. The two existing label assertions stay as they are (an icon is a decorative `svg` with no text).

In `block_card_component_test.rb`, in "the header has a drag handle…" add:

```ruby
    assert_selector ".admin-block-card > div:first-child .admin-block-card__handle + [data-block-icon=pilcrow][class~='text-dim'] svg[class~='size-3.5']"
```

In `block_tile_component_test.rb` add (the class includes `GalleryAlbum` for the second test: add `include GalleryAlbum` beside `include ContentHelper`):

```ruby
  test "the tile shows the type's icon in place of its name, and the face is still named by the type" do
    render_tile

    assert_selector ".admin-block-tile__face [data-block-icon=image][class~='text-meta'] svg[class~='size-3']"
    assert_selector ".admin-block-tile__face .sr-only", text: "Image"
    assert_no_selector ".admin-block-tile__face span.font-semibold", text: "Image"
  end

  # Review focus 3.
  test "a type that names no icon keeps its name on the tile and draws no icon anywhere" do
    with_gallery_album do
      block = @editor_page.content_blocks.create!(block_type: "gallery/album", section: @section, section_column: 2, position: 0)
      render_tile(block)

      assert_selector ".admin-block-tile__face span.font-semibold", text: "Album"
      assert_no_selector "[data-block-icon]"
      render_inline Admin::EditorScreen::BlockPickerComponent.new(page: @editor_page, locale: "en")
      assert_selector "#block-picker-end button", text: "Album"
    end
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/models/content_model/block_type_definition_test.rb test/components/admin/editor_screen/block_icon_component_test.rb test/components/admin/editor_screen/block_picker_component_test.rb test/components/admin/editor_screen/block_card_component_test.rb test/components/admin/editor_screen/block_tile_component_test.rb`
Expected: FAIL — `undefined method 'icon'`, `uninitialized constant Admin::EditorScreen::BlockIconComponent`, `ArgumentError: unknown admin icon :pilcrow`.

- [ ] **Step 3: The declaration**

In `app/models/content_model/block_type_definition.rb`, after `SUMMARY_LENGTH = 80` add:

```ruby
    # The icons a block type may name (contrast and buttons spec, C2 and
    # Ruling 6): each is a branch of CS Studio's icon partial
    # (`app/views/admin/shared/_icon.html.erb`, Lucide), which a model may
    # not name; `block_icon_component_test.rb` draws every one. A type names
    # one or none; an outside type picks from the same list.
    ICONS = %w[pilcrow image code_xml posts columns_2].freeze
```

and after `def stylesheet … end` add:

```ruby
    # The icon CS Studio draws for the type in the picker, on a card's head
    # and on a section's tile: one of `ICONS`, or none.
    def icon(name = nil)
      return @icon if name.nil?
      refuse "icon is one of #{ICONS.join(", ")} (the icons CS Studio draws for a block type): #{name.inspect}" unless ICONS.include?(name.to_s)

      @icon = name.to_s
    end
```

Add after each type's `t.label` line: `t.icon "pilcrow"` (`rich_text.rb`), `t.icon "image"` (`image.rb`), `t.icon "code_xml"` (`code.rb`), `t.icon "posts"` (`post_list.rb`, the sidebar's Posts icon), `t.icon "columns_2"` (`section.rb`).

- [ ] **Step 4: The drawings**

In `app/views/admin/shared/_icon.html.erb`, change the `:posts` branch's `class="size-5 shrink-0"` to `class="<%= local_assigns.fetch(:size, "size-5") %> shrink-0"`, and before the `<% else` line add:

```erb
<%# The block types' icons (contrast and buttons spec, C2; Lucide, 1.5px):
    a block type names one (`ContentModel::BlockTypeDefinition::ICONS`) and
    `Admin::EditorScreen::BlockIconComponent` draws it at 16, 14 or 12px. %>
<% when :pilcrow %>
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class="<%= local_assigns.fetch(:size, "size-5") %> shrink-0" aria-hidden="true" focusable="false"><path stroke-linecap="round" stroke-linejoin="round" d="M13 4v16M17 4v16M19 4H9.5a4.5 4.5 0 0 0 0 9H13" /></svg>
<% when :image %>
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class="<%= local_assigns.fetch(:size, "size-5") %> shrink-0" aria-hidden="true" focusable="false"><rect x="3" y="3" width="18" height="18" rx="2" /><circle cx="9" cy="9" r="2" /><path stroke-linecap="round" stroke-linejoin="round" d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21" /></svg>
<% when :code_xml %>
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class="<%= local_assigns.fetch(:size, "size-5") %> shrink-0" aria-hidden="true" focusable="false"><path stroke-linecap="round" stroke-linejoin="round" d="m18 16 4-4-4-4M6 8l-4 4 4 4M14.5 4l-5 16" /></svg>
<% when :columns_2 %>
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class="<%= local_assigns.fetch(:size, "size-5") %> shrink-0" aria-hidden="true" focusable="false"><rect x="3" y="3" width="18" height="18" rx="2" /><path stroke-linecap="round" d="M12 3v18" /></svg>
```

Create `app/components/admin/editor_screen/block_icon_component.rb`:

```ruby
module Admin
  module EditorScreen
    # A block type's icon where the editor names the type (contrast and
    # buttons spec, C2): 16px dim before the name in the picker, 14px dim
    # between a card's handle and its name, 12px meta before a tile's
    # summary, where it stands in for the name. Decoration: the name is
    # always beside it, on the tile as `sr-only` text. A type that names no
    # icon draws nothing (Ruling 7).
    class BlockIconComponent < AdminComponent
      PLACES = { picker: %w[size-4 text-dim], card: %w[size-3.5 text-dim], tile: %w[size-3 text-meta] }.freeze

      def initialize(definition:, place:)
        raise ArgumentError, "unknown place #{place.inspect}" unless PLACES.key?(place)

        @definition = definition
        @place = place
      end

      def render? = @definition&.icon.present?

      def call
        size, colour = PLACES.fetch(@place)
        tag.span(helpers.render("admin/shared/icon", name: @definition.icon.to_sym, size: size),
          class: "inline-flex shrink-0 #{colour}", aria: { hidden: true }, data: { block_icon: @definition.icon })
      end
    end
  end
end
```

- [ ] **Step 5: The three places**

`block_picker_component.html.erb` — the lane's menu item becomes:

```erb
          <%= button_to create_path, method: :post, class: "#{menu_item_class} flex items-center gap-2",
                params: { block: { block_type: type.name }, section_id: section.id, column: column } do %><%= render Admin::EditorScreen::BlockIconComponent.new(definition: type, place: :picker) %><%= type.label %><% end %>
```

and the end-of-list button becomes:

```erb
      <%= button_to create_path, method: :post, params: { block: { block_type: type.name } }, class: button_class do %><%= render Admin::EditorScreen::BlockIconComponent.new(definition: type, place: :picker) %><%= type.label %><% end %>
```

(on one line each, so no white space lands in the button's text).

`block_card_component.html.erb` — insert `<%= render Admin::EditorScreen::BlockIconComponent.new(definition: definition, place: :card) unless unavailable? %>` directly after the `<% end %>` that closes the `if list? && editable? && !unavailable?` handle block (so it stands between the handle and the name in the list, group and panel branches).

`block_tile_component.rb` — add:

```ruby
      # The type's icon stands in for its name on the face (contrast and
      # buttons spec, C2), which then keeps the name as `sr-only` text so the
      # face's accessible name still says the type. A type with no icon
      # keeps its visible name (Ruling 7).
      def block_icon = @block_icon ||= Admin::EditorScreen::BlockIconComponent.new(definition: block.definition, place: :tile)

      def icon? = block_icon.render?
```

`block_tile_component.html.erb` — replace

```erb
    <span class="truncate text-sm font-semibold text-ink"><%= label %></span>
    <%= render Admin::EditorScreen::TileSummaryComponent.new(block: block, locale: locale) %>
```

with

```erb
    <% if icon? %>
      <span class="flex min-w-0 items-center gap-1.5"><%= render block_icon %><span class="sr-only"><%= label %></span><%= render Admin::EditorScreen::TileSummaryComponent.new(block: block, locale: locale) %></span>
    <% else %>
      <span class="truncate text-sm font-semibold text-ink"><%= label %></span>
      <%= render Admin::EditorScreen::TileSummaryComponent.new(block: block, locale: locale) %>
    <% end %>
```

- [ ] **Step 6: Run the tests**

Run: `PGGSSENCMODE=disable bin/rails test test/models test/components test/integration/block_samples_test.rb test/values/theme test/lib/dependency_direction_test.rb test/lib/admin_design_rules_test.rb`, then `bin/rails tailwindcss:build && PGGSSENCMODE=disable bin/rails test test/system/admin/blocks_test.rb`, then `… test/system/admin/sections_test.rb`.
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A app test
git commit -m "feat: a block type declares its icon, drawn in the picker, on the card and on the tile

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 6: The page tree's state marks and its selected row

**Files:**
- Create: `app/components/admin/pages_screen/tree_state_mark_component.rb`
- Modify: `app/components/admin/pages_screen/tree_node_component.html.erb`, `tree_node_component.rb`
- Modify: `app/components/admin/ui/unpublished_chip_component.rb`, `.html.erb` (compact mode goes)
- Test: `test/components/admin/pages_screen/tree_component_test.rb`, `test/components/admin/ui/unpublished_chip_component_test.rb`

**Interfaces:**
- Consumes: `Publishable#status` ("draft" | "scheduled" | "live"), `Publishable#unpublished_changes?`, the keys `admin.components.ui.status_chip.labels.*` and `admin.components.ui.unpublished_chip.label`, the format `:"admin.datetime"`.
- Produces: `Admin::PagesScreen::TreeStateMarkComponent.new(page:)` drawing `span.admin-tree-mark[role=img]` with `data-status` (draft, scheduled) and `data-unpublished-changes`; `TreeNodeComponent#row_class`.

- [ ] **Step 1: Write the failing tests**

In `test/components/admin/pages_screen/tree_component_test.rb` add:

```ruby
  # Contrast and buttons spec (C2, Rulings 8 and 9): a mark after the title
  # only when a page is not simply live, named for a screen reader in the
  # status chip's and the unpublished chip's own words.
  test "a draft is a hollow meta ring, a scheduled page a warn dot, a live page with changes a dim dot, and a live page nothing" do
    draft = create_page(title: "Draft one", published: false)
    soon = create_page(title: "Soon")
    soon.update_columns(published_at: 2.days.from_now) # version: none (a test schedules a page) # changes: none (a test schedules a page)
    changed = create_page(title: "Changed")
    assert Pages::Save.call(changed, translations: { "en" => { title: "Changed typed" } }).ok?
    plain = create_page(title: "Plain")

    render_tree

    assert_selector "li[data-page-id='#{draft.id}'] > div .admin-tree-mark[data-status=draft][role=img][aria-label='Draft'][title='Draft'][class~='border-meta'][class~='border-[1.5px]'][class~='size-1.5']"
    assert_selector "li[data-page-id='#{soon.id}'] > div .admin-tree-mark[data-status=scheduled][aria-label='Scheduled'][class~='bg-warn']"
    assert_selector "li[data-page-id='#{soon.id}'] > div .admin-tree-mark[title^='Scheduled · ']"
    assert_selector "li[data-page-id='#{changed.id}'] > div .admin-tree-mark[data-unpublished-changes][aria-label='Unpublished changes'][class~='bg-dim']"
    assert_no_selector "li[data-page-id='#{plain.id}'] > div .admin-tree-mark"
    assert_no_selector ".admin-status-chip"
  end

  # Review focus 4.
  test "a scheduled page with unpublished changes has one mark that names both" do
    soon = create_page(title: "Soon")
    soon.update_columns(published_at: 2.days.from_now, unpublished_changes_at: Time.current) # version: none (a test schedules a page) # changes: none (a test marks a scheduled page)

    render_tree

    assert_selector "li[data-page-id='#{soon.id}'] > div .admin-tree-mark", count: 1
    assert_selector "li[data-page-id='#{soon.id}'] > div .admin-tree-mark[data-status=scheduled][data-unpublished-changes][aria-label='Scheduled · Unpublished changes'][class~='bg-warn']"
  end

  test "the selected row has the sunken ground and a 2px ink bar on its left edge" do
    chosen = create_page(title: "Chosen")
    other = create_page(title: "Other")
    render_inline(Admin::PagesScreen::TreeComponent.new(root: root_page.reload, selected: chosen, locale: "en"))

    assert_selector "li[data-page-id='#{chosen.id}'] > div[class~='bg-sunken'][class~='shadow-[inset_2px_0_0_var(--cs-ink)]']"
    assert_no_selector "li[data-page-id='#{other.id}'] > div[class~='bg-sunken']"
  end
```

The existing "a live page with unpublished changes carries the mark; a draft with a stale mark does not" and "3 marked pages cost the same queries as 30" stay as they are (the new mark keeps `data-unpublished-changes`, `role=img` and the label).

In `test/components/admin/ui/unpublished_chip_component_test.rb`, replace the compact test with:

```ruby
  test "there is no compact mode any more: the tree draws its own mark" do
    assert_raises(ArgumentError) { Admin::Ui::UnpublishedChipComponent.new(compact: true) }
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/components/admin/pages_screen/tree_component_test.rb test/components/admin/ui/unpublished_chip_component_test.rb`
Expected: FAIL — no `.admin-tree-mark`, an `.admin-status-chip` in the tree, no `bg-sunken` on the selected row, `compact: true` accepted.

- [ ] **Step 3: The mark**

Create `app/components/admin/pages_screen/tree_state_mark_component.rb`:

```ruby
module Admin
  module PagesScreen
    # A page's state in the tree (contrast and buttons spec, C2): a small mark
    # after the title, only when the page is not simply live. Draft: a hollow
    # 6px ring of 1.5px in `meta`. Scheduled: a filled `warn` dot. Live with
    # unpublished changes: a `dim` dot. Never colour alone: each is
    # `role="img"` with a name and a tooltip, in the words the status chip
    # and the unpublished chip already use (Ruling 9), so a state reads the
    # same everywhere in CS Studio.
    #
    # ONE MARK A ROW (Ruling 8): a scheduled page with unpublished changes
    # draws the scheduled dot, named "Scheduled · Unpublished changes". No
    # "change scheduled" mark: that state needs the pending copies, which
    # the tree does not read. `status` and `unpublished_changes?` are the
    # row's own columns (`Publishing::State`), so the mark costs no
    # statement (`tree_component_test.rb`: "3 marked pages cost the same
    # queries as 30").
    class TreeStateMarkComponent < AdminComponent
      LOOKS = {
        draft: "size-1.5 rounded-full border-[1.5px] border-meta",
        scheduled: "size-1.5 rounded-full bg-warn",
        changes: "size-1.5 rounded-full bg-dim"
      }.freeze

      def initialize(page:)
        @page = page
      end

      def render? = kind.present?

      def call
        tag.span("", class: "admin-tree-mark shrink-0 #{LOOKS.fetch(kind)}", role: "img", title: title, aria: { label: label },
          data: { status: (status unless status == "live"), unpublished_changes: ("" if changes?) })
      end

      def kind
        return :draft if status == "draft"
        return :scheduled if status == "scheduled"

        :changes if changes?
      end

      def label = words.join(" · ")

      # A scheduled page's tooltip also says when, as the status chip's does.
      def title
        return label unless kind == :scheduled

        [ word(:scheduled), I18n.l(page.published_at, format: :"admin.datetime"), (word(:changes) if changes?) ].compact.join(" · ")
      end

      private

      attr_reader :page

      def status = page.status

      def changes? = page.unpublished_changes?

      def words = [ word(kind), (word(:changes) if kind == :scheduled && changes?) ].compact

      def word(key)
        key == :changes ? t("admin.components.ui.unpublished_chip.label") : t("admin.components.ui.status_chip.labels.#{key}")
      end
    end
  end
end
```

- [ ] **Step 4: The row**

In `tree_node_component.html.erb`, replace the two renders and their comments:

```erb
      <%# The chip carries `data-status` itself and renders nothing for Live. %>
      <%= render Admin::Ui::StatusChipComponent.new(status: status, at: page.published_at, hide_live: true) %>

      <%# The rows moved on from what the site shows (`Publishing::State#changes?`,
          a column already loaded: no statement per row): the warn dot alone, the
          column is narrow. %>
      <%= render Admin::Ui::UnpublishedChipComponent.new(compact: true) if page.unpublished_changes? %>
```

with:

```erb
      <%# Draft, Scheduled or Live with changes, one small named mark (see the component). %>
      <%= render Admin::PagesScreen::TreeStateMarkComponent.new(page: page) %>
```

and change the row's opening tag `<div class="group/node relative flex items-center gap-1.5 rounded-cs px-1.5 py-1 hover:bg-sunken">` to `<div class="group/node relative flex items-center gap-1.5 rounded-cs px-1.5 py-1 hover:bg-sunken <%= row_class %>">`.

In `tree_node_component.rb`, after `def selected? = page == selected` add:

```ruby
      # The selected row (contrast and buttons spec, C1): bold, on the sunken
      # ground, with a 2px ink bar on its left edge (14:1 light, 12:1 dark),
      # as the documentation site's navigation marks where you are. An inset
      # shadow and not a border, so the title does not move by 2px.
      def row_class = selected? ? "bg-sunken shadow-[inset_2px_0_0_var(--cs-ink)]" : nil
```

and in the class comment replace "a status dot" with "a state mark (`TreeStateMarkComponent`)".

In `app/components/admin/ui/unpublished_chip_component.rb`, replace `initialize` and the `private` reader with nothing (the component takes no argument), and the comment's "Full: … Compact (the page tree, whose column is narrow): the dot alone, named for a screen reader and in a tooltip." with "The status chip's shell with a warn dot, in the editor's header and the posts list; the page tree draws its own mark (`Admin::PagesScreen::TreeStateMarkComponent`)." In `unpublished_chip_component.html.erb` keep only the `else` branch's markup (drop the `if compact` branch and the `<% end %>`).

- [ ] **Step 5: Run the tests**

Run: `PGGSSENCMODE=disable bin/rails test test/components test/integration/admin/tree_test.rb test/lib/admin_design_rules_test.rb test/lib/admin_i18n_test.rb`, then `bin/rails tailwindcss:build && PGGSSENCMODE=disable bin/rails test test/system/admin/unpublished_changes_test.rb`, `… test/system/admin/drafts_test.rb`, `… test/system/tree_test.rb`, `… test/system/admin/tree_column_test.rb`.
Expected: PASS. `drafts_test.rb:438` (`assert_selector "[data-unpublished-changes]", text: "Unpublished changes"`) reads the header's full chip, which still has its words.

- [ ] **Step 6: Commit**

```bash
git add -A app test
git commit -m "feat: the page tree marks a draft, a scheduled page and unpublished changes with one small named mark, and shows the selected row

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 7: The Mind graph in dark

**Files:**
- Modify: `app/assets/tailwind/content-spiel.css` (`--cs-graph-page`, `--cs-graph-tree` in both blocks)
- Modify: `app/javascript/mind_graph/theme.js` (`TOKENS`), `marks.js` (`drawPage`, its comment), `renderer.js` (`LINE_STYLES.tree`, its comment)
- Test: `test/lib/admin_contrast_test.rb`, `test/system/admin/mind_graph_modules_test.rb`

**Interfaces:**
- Consumes: `AdminContrastTest#each_scheme`, `#schemes` (Task 1).
- Produces: theme keys `page` (`--cs-graph-page`) and `tree` (`--cs-graph-tree`); `LINE_STYLES.tree.colour == "tree"`.

- [ ] **Step 1: Write the failing tests**

In `test/lib/admin_contrast_test.rb` add:

```ruby
  # Design answer D2: in dark, ink-white page marks glared and the tree's
  # lines vanished.
  test "the Mind graph's page mark and tree line are 3:1 or better on the surface, the dark page mark no glare" do
    each_scheme do |scheme, colour|
      assert_ratio(3.0, colour.("--cs-graph-page"), colour.("--cs-surface"), "a page's mark (#{scheme})")
      assert_ratio(3.0, colour.("--cs-graph-tree", under: "--cs-surface"), colour.("--cs-surface"), "a tree line (#{scheme})")
    end
    assert_equal "#d9d9dc", schemes[:dark]["--cs-graph-page"]
    assert_equal "var(--cs-ink)", schemes[:light]["--cs-graph-page"]
    assert_equal "var(--cs-dim)", schemes[:light]["--cs-graph-tree"]
  end
```

In `test/system/admin/mind_graph_modules_test.rb`:
- `STATED_MARKS`: the `"page"` and `"Home"` entries' `own: "ink"` → `own: "page"`;
- the test "marks: a page is a 14 by 10 card…": `"ink" ]` → `"page" ]` in the `live` and `home` expectations;
- `LINES`: `"tree" => [ "line", 1, [], 1, "butt" ]` → `"tree" => [ "tree", 1, [], 1, "butt" ]`;
- the four fake themes that hold `faint: "faint"` (in `marks_drawn`, `lines_drawn`, the `drawSwatch` and the `drawRowMark` helpers): add `page: "page", tree: "tree",` after `faint: "faint",`;
- the theme-map test: add `"graph-page", "graph-tree"` to its `tokens` array, and `"page" => "the-graph-page", "tree" => "the-graph-tree",` to the expected hash after `"faint" => "the-line",`.

- [ ] **Step 2: Run them to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/lib/admin_contrast_test.rb`, then `bin/rails tailwindcss:build && PGGSSENCMODE=disable bin/rails test test/system/admin/mind_graph_modules_test.rb`
Expected: FAIL — `KeyError: key not found: "--cs-graph-page"`; the marks are drawn in `ink`, the tree line in `line`, and the theme has no `page` or `tree`.

- [ ] **Step 3: The tokens and the canvas**

In `content-spiel.css`, light block, after `--cs-cat-6: …;` add:

```css
  /* The Mind graph's canvas (design answer D2), read by
     `mind_graph/theme.js`: a page's mark, and the tree's lines. */
  --cs-graph-page: var(--cs-ink);
  --cs-graph-tree: var(--cs-dim);
```

and in the dark block, after its `--cs-cat-6: …;`:

```css
  /* Ink-white page marks glared in dark; the tree's lines are dim at 60%
     (that is `--cs-dim`'s value, here as a colour a canvas can take). */
  --cs-graph-page: #d9d9dc;
  --cs-graph-tree: rgba(169,170,175,0.6);
```

In `app/javascript/mind_graph/theme.js`, `TOKENS` gains `page: "--cs-graph-page", tree: "--cs-graph-tree"`, and the comment above it: "`line` is the border of the notes badge and of the "+N more" pill; `tree` the tree's lines; `page` a page's mark (in dark not the ink, which glared)" in place of "…and the tree's lines".

In `marks.js`, `drawPage` becomes `state(context, theme, look, theme.page, { ...boxOf(node), corner: theme.radius ?? 0 }, x, y)`, and the kinds comment's "in neutral ink" becomes "in the page colour (`theme.page`: the ink in light, a softer light grey in dark)".

In `renderer.js`, `tree: { colour: "line", … }` → `tree: { colour: "tree", width: 1, dash: [], alpha: 1, cap: "butt" }`, and the comment's "Tree solid in the strong line colour" → "Tree solid in `tree` (dim; in dark dim at 60%)".

- [ ] **Step 4: Run the tests**

Run: `PGGSSENCMODE=disable bin/rails test test/lib/admin_contrast_test.rb test/lib/mind_graph_guards_test.rb test/lib/admin_design_rules_test.rb`, then `bin/rails tailwindcss:build && PGGSSENCMODE=disable bin/rails test test/system/admin/mind_graph_modules_test.rb`, then `… test/system/admin/mind_graph_test.rb`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A app test
git commit -m "feat: the Mind graph's page marks and tree lines read in dark, and cat-5 leaves cat-1's side

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

(cat-5 moved in Task 1; the subject names it here because this is where it shows.)

---

### Task 8: The site's default theme

**Files:**
- Modify: `app/assets/tailwind/themes/default/tokens.css`, `sections.css`, `code.css`
- Modify: `app/views/layouts/public/_theme_toggle.html.erb`, `app/views/layouts/public/_language_switcher.html.erb`
- Modify: `app/components/blocks/section_component.rb` (`render?`)
- Test: `test/integration/design_tokens_test.rb`, `test/integration/public_blocks_test.rb`, `test/system/code_block_test.rb`

**Interfaces:**
- Consumes: `ContrastMeasure` (Task 1), `theme_tokens`, `band_values` (the test's own).
- Produces: no new token; `Blocks::SectionComponent#render?` asks `render_block`.

- [ ] **Step 1: Write the failing tests**

In `test/integration/design_tokens_test.rb`, replace the test "in a strong band the ink on the accent is the band's colour, readable on the band's accent, and a code block's scheme is the opposite one" with:

```ruby
  # Design answer D2: a strong band is the strongest step of its OWN scheme,
  # the inverted page in light and a raised dark ground in dark, so a code
  # block in it is dark in both.
  test "in a strong band the ink on the accent is the band's colour, readable on the band's accent, and a code block is dark in both schemes" do
    css = Rails.root.join("app/assets/tailwind/themes/default/sections.css").read

    assert_match(/\.content-section--strong\s*\{[^}]*--th-on-accent:\s*var\(--th-band-strong\);/m, css)
    assert_match(/^\.content-section--strong \.content-block--code\s*\{\s*color-scheme:\s*dark;/, css)
    assert_no_match(/\[data-theme="dark"\] \.content-section--strong \.content-block--code/, css)
    theme_tokens.each do |theme, tokens|
      ratio = contrast(resolve_colour(tokens, "--th-band-strong"), resolve_colour(tokens, "--th-on-band-strong-accent"))
      assert_operator ratio, :>=, 4.5, "selected code in a strong band (#{theme}) is #{ratio.round(2)}:1"
      ratio = contrast(resolve_colour(tokens, "--th-accent"), resolve_colour(tokens, "--th-on-accent"))
      assert_operator ratio, :>=, 4.5, "selected code on the page (#{theme}) is #{ratio.round(2)}:1"
    end
  end
```

and add:

```ruby
  # Contrast and buttons spec (C1): what the contract now says of
  # `--th-meta` and `--th-line`, held for the default theme.
  test "faint text is 4.5:1 on the page and on the tinted band, an outline in it is 3:1, and a line stays a hairline, in both themes" do
    theme_tokens.each do |theme, tokens|
      page = resolve_colour(tokens, "--th-paper")
      meta = resolve_colour(tokens, "--th-meta")
      band = resolve_colour(tokens, "--th-band-tinted")
      in_band = resolve_colour(tokens, "--th-meta", inside: band_values("tinted"))
      line = contrast(resolve_colour(tokens, "--th-line", under: page), page)

      assert_operator contrast(meta, page), :>=, 4.5, "faint text on the page (#{theme})"
      assert_operator contrast(in_band, band), :>=, 4.5, "faint text on the tinted band (#{theme})"
      assert_operator contrast(meta, page), :>=, 3.0, "a control's outline (#{theme})"
      assert_operator line, :>=, 1.3, "--th-line (#{theme}) is #{line.round(2)}:1"
      assert_operator line, :<, 3.0, "--th-line (#{theme}) would be an outline"
    end
  end

  test "the bands step from the page: tinted at 1.15:1 or more, the light strong band the inverted page, the dark one a raised ground" do
    theme_tokens.each do |theme, tokens|
      page = resolve_colour(tokens, "--th-paper")
      assert_operator contrast(resolve_colour(tokens, "--th-band-tinted"), page), :>=, 1.15, "the tinted band (#{theme})"
    end
    light, dark = theme_tokens.values_at(:light, :dark)
    assert_equal "var(--th-ink)", light["--th-band-strong"]
    strong = contrast(resolve_colour(dark, "--th-band-strong"), resolve_colour(dark, "--th-paper"))
    assert_operator strong, :>=, 1.4, "the dark strong band is a step up from the page"
    assert_operator strong, :<, 2.0, "the dark strong band does not glare"
  end

  test "the site's controls: the theme button is outlined in the faint text colour and 28px high, a language code has a 24px target and an underline under the pointer, Copy is 12px with a 28px target" do
    toggle = Rails.root.join("app/views/layouts/public/_theme_toggle.html.erb").read
    switcher = Rails.root.join("app/views/layouts/public/_language_switcher.html.erb").read
    code = Rails.root.join("app/assets/tailwind/themes/default/code.css").read.gsub(%r{/\*.*?\*/}m, "")

    %w[border-meta h-7 inline-flex].each { |name| assert_match(/class="[^"]*\b#{Regexp.escape(name)}\b/, toggle, name) }
    assert_no_match(/border-line-strong/, toggle)
    %w[min-h-6 hover:underline].each { |name| assert_includes switcher, name }
    button = code[/\.content-block--code \.code-head button\s*\{([^}]*)\}/m, 1].to_s
    assert_match(/font-size:\s*0\.75rem;/, button)
    assert_match(/padding-block:\s*0\.3125rem;/, button)
    assert_match(/margin-block:\s*-0\.3125rem;/, button)
    assert_match(/text-decoration:\s*underline;/, code[/\.content-block--code \.code-head button:hover\s*\{([^}]*)\}/m, 1].to_s)
  end
```

In `test/integration/public_blocks_test.rb` add:

```ruby
  # Design answer, first reply: Home drew an empty tinted band. A section
  # whose blocks draw nothing is no band (Ruling 19); one that draws
  # anything is.
  test "a section whose blocks draw nothing renders nothing, and one block that draws something brings the band back" do
    section = @root.content_blocks.create!(block_type: :section, position: 5, settings: { "layout" => "two", "background" => "tinted", "width" => "content" })
    @root.content_blocks.create!(block_type: :code, section: section, section_column: 1, position: 0, settings: {})
    get "/"
    assert_select "section.content-section", 0

    @root.content_blocks.create!(block_type: :rich_text, section: section, section_column: 2, position: 0, body: rich_doc("Now there is text"))
    get "/"
    assert_select "section.content-section--tinted", 1
    assert_select "section.content-section--tinted", text: /Now there is text/
  end
```

In `test/system/code_block_test.rb`, in the test that presses Copy (it finds it with `button = find("#{FIGURE} button", text: "Copy")`), add between that line and `button.click`:

```ruby
    assert_operator button.evaluate_script("this.getBoundingClientRect().height"), :>=, 28, "Copy's target"
```

- [ ] **Step 2: Run them to see them fail**

Run: `bin/rails tailwindcss:build && bin/rails theme_css:build && PGGSSENCMODE=disable bin/rails test test/integration/design_tokens_test.rb test/integration/public_blocks_test.rb`, then `PGGSSENCMODE=disable bin/rails test test/system/code_block_test.rb`
Expected: FAIL — the dark override of `color-scheme`, `--th-line` at 1.23:1, the tinted band 1.12:1 in light, the dark strong band 15.7:1, the toggle's `border-line-strong`, no `min-h-6`, Copy's rule without `font-size`, a tinted section drawn around an empty code block, Copy under 28px.

- [ ] **Step 3: The tokens**

In `tokens.css`, light block: `--th-sunken: #ecebe6;` → `--th-sunken: #e6e4dd;`; `--th-line: rgba(20,20,23,0.10);` → `--th-line: rgba(20,20,23,0.14);`. Dark block: `--th-line: rgba(237,237,238,0.09);` → `--th-line: rgba(237,237,238,0.13);`, and replace

```css
  /* The bands again: the dark page inverted is this block's ink as the band
     and its paper as the text. */
  --th-band-tinted: var(--th-sunken);
  --th-band-strong: #ededee;
  --th-on-band-strong: #0f1012;
  --th-on-band-strong-dim: #45464b;
  --th-on-band-strong-accent: oklch(0.45 0.12 250);
```

with

```css
  /* The bands again. A strong band is the strongest step of ITS scheme
     (design answer D2): in dark a raised dark ground, 1.56:1 against the
     page, not the light page inverted, which glared. Its text, dim and
     accent are 10.5:1, 6.8:1 and 7.1:1 on it, and 7.4:1, 4.8:1 and 5.0:1 on
     its sunken ground, where code stands. */
  --th-band-tinted: var(--th-sunken);
  --th-band-strong: #34353a;
  --th-on-band-strong: #ededee;
  --th-on-band-strong-dim: #c0c1c6;
  --th-on-band-strong-accent: oklch(0.82 0.09 250);
```

In the light block's band comment, "`strong` is the page inverted … (16.3:1, 8.1:1 and 6.4:1 in the dark block below)" becomes "`strong` is the page inverted here … (the dark block below says what it is there)"; and the tinted band's line gains "1.16:1 against the page (Ruling 3: 1.2 would put the accent link on it under 4.5:1)".

- [ ] **Step 4: The strong band's code, Copy, the toggle and the switcher**

In `sections.css`, delete the line `[data-theme="dark"] .content-section--strong .content-block--code { color-scheme: light; }`, and in the comment above `.content-section--strong` replace "Strong is the page inverted, with its own three text colours." with "Strong is the strongest step of its scheme -- the page inverted in light, a raised dark ground in dark -- with its own three text colours.", and "And the band is the other scheme: … so the block is told the opposite here (the only `color-scheme` a code block is given)." with "And the band is a dark ground in both schemes: a code block's scrollbar is drawn for the scheme the layout declares on <body>, which on the light page is the wrong one, so the block is told `dark` here (the only `color-scheme` a code block is given)."

In `code.css`, replace the `.content-block--code .code-head button { … }` rule with:

```css
/* Copy (design answer D1): 12px, a 28px target that does not make the
   strip taller (the block padding is taken back by the margin, Ruling 18),
   underlined under the pointer, the theme's focus ring below. */
.content-block--code .code-head button {
  margin-inline-start: auto;
  margin-block: -0.3125rem;
  padding-block: 0.3125rem;
  padding-inline: var(--th-sp-1);
  border: 0;
  background: none;
  font: inherit;
  font-size: 0.75rem;
  color: var(--th-accent);
  cursor: pointer;
}
```

and the `:hover` rule with:

```css
.content-block--code .code-head button:hover {
  color: var(--th-accent-hover);
  text-decoration: underline;
  text-underline-offset: 2px;
}
```

`_theme_toggle.html.erb`: the button's class becomes `"inline-flex h-7 items-center rounded-cs border border-meta px-3 font-cs-mono text-label uppercase tracking-mono text-dim hover:bg-sunken"`, and the comment gains: "Outlined in `--th-meta`, 3:1 or better, as a control on the site is (contrast and buttons spec, C1; the contract's `--th-meta` row)."

`_language_switcher.html.erb`: the link's class becomes `link.current ? "inline-flex min-h-6 items-center rounded-cs bg-ink px-1.5 text-paper" : "inline-flex min-h-6 items-center rounded-cs px-1.5 text-dim hover:text-ink hover:underline"`.

- [ ] **Step 5: An empty band draws nothing**

In `app/components/blocks/section_component.rb`, replace `render?` and its comment with:

```ruby
    # A section draws nothing when none of its blocks draws anything
    # (sections spec §5.5; contrast and buttons spec, Ruling 19): an empty
    # band would be a stripe of background with nothing in it. A section
    # with no block, a block whose type is no longer registered (drawn as
    # nothing by `ThemeHelper#render_block`), and a block that is empty (a
    # Code block with no code) are all no content. The blocks are asked in
    # reading order and the first that draws something ends the question,
    # so a band with content draws its first block twice and an empty one
    # draws nothing. An empty COLUMN keeps its place, so a two-column band
    # with one text stays a half-width text.
    def render?
      columns.any? { |blocks| blocks.any? { |inner| inner.definition && render_block(inner).to_s.strip.present? } }
    end
```

- [ ] **Step 6: Run the tests**

Run: `bin/rails tailwindcss:build && bin/rails theme_css:build && PGGSSENCMODE=disable bin/rails test test/integration/design_tokens_test.rb test/integration/public_blocks_test.rb test/integration/public_canary_test.rb test/integration/theme_pages_test.rb test/integration/block_samples_test.rb test/values/theme test/lib/theming_reference_test.rb test/lib/admin_design_rules_test.rb`, then `PGGSSENCMODE=disable bin/rails test test/system/code_block_test.rb`.
Expected: PASS (the 42 syntax pairs, the band texts and the focus rings run on the new values: the lowest new pair is the comment in a dark strong band, 4.84:1).

- [ ] **Step 7: Commit**

```bash
git add -A app test
git commit -m "feat: the site's lines, tinted band and dark strong band step apart, its controls are outlined at 3:1, and an empty band draws nothing

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 9: The editor's small fixes

**Files:**
- Modify: `app/assets/tailwind/content-spiel.tailwind.css` (`.admin-disclosure`)
- Modify: `app/components/admin/editor_screen/page_settings_form_component.html.erb` (two summaries), `shared_fields_component.html.erb`, `app/views/admin/audit_events/show.html.erb`
- Modify: `app/models/content_model/definition.rb` (`blank:` on `:content_type`), `app/models/block_types/post_list.rb`
- Modify: `app/components/admin/editor_screen/block_card_component.html.erb`, `block_card_component.rb` (`status_line`)
- Test: `test/lib/admin_design_rules_test.rb`, `test/components/admin/editor_screen/page_settings_form_component_test.rb`, `test/models/content_model/code_field_test.rb`, `test/components/admin/editor_screen/block_card_component_test.rb`, `test/system/admin/blocks_test.rb`

**Interfaces:**
- Produces: `.admin-disclosure`; `BlockCardComponent#status_line`; `.admin-block-card__head` on a card's header row; `blank:` accepted for `:content_type` fields.

- [ ] **Step 1: Write the failing tests**

In `test/lib/admin_design_rules_test.rb` add:

```ruby
  # Design answer, first reply: "▾PAGE SETTINGS" had no space. A mono-label
  # summary draws its own triangle, 6px from the words, that a screen reader skips.
  test "a disclosure's triangle is the stylesheet's, apart from its words, turned when open" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    assert_match(/\.admin-disclosure\s*\{[^}]*list-style:\s*none;[^}]*gap:\s*0\.375rem;/m, css)
    assert_match(/\.admin-disclosure::before\s*\{[^}]*content:\s*"▸"\s*\/\s*"";/m, css)
    assert_match(/details\[open\]\s*>\s*\.admin-disclosure::before\s*\{[^}]*rotate\(90deg\)/m, css)
    %w[app/components/admin/editor_screen/page_settings_form_component.html.erb app/components/admin/editor_screen/shared_fields_component.html.erb
       app/views/admin/audit_events/show.html.erb].each do |path|
      Rails.root.join(path).read.scan(/<summary[^>]*>/).each { |summary| assert_includes summary, "admin-disclosure", path }
    end
  end
```

In `test/models/content_model/code_field_test.rb` add:

```ruby
  test "a content type field may name its empty choice too" do
    definition = ContentModel::BlockTypeDefinition.new("x")
    definition.field(:content_type, :content_type, blank: "All types")
    assert_equal "All types", definition.fields.last.options[:blank]
    assert_raises(ArgumentError) { ContentModel::BlockTypeDefinition.new("x").field(:content_type, :content_type, required: true, blank: "All types") }
  end
```

In `test/components/admin/editor_screen/block_card_component_test.rb` add:

```ruby
  test "the Post list's Content type says All types for its empty choice" do
    page = create_page(title: "All types")
    block = page.content_blocks.create!(block_type: "post_list", position: 0, settings: {})
    render_card(block, page: page)
    assert_selector "select[name='block[settings][content_type]'] option[value='']", text: "All types"
  end

  test "the save line stands in the card's header row, before the menu, and not in the body" do
    page = create_page(title: "Status")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)
    render_card(block, page: page)
    status = Admin::EditorScreen::BlockCardComponent.status_id(block)

    assert_selector ".admin-block-card > .admin-block-card__head .admin-block-card__status ##{status}[role=status]"
    assert_no_selector "[data-block-body] ##{status}"
  end
```

In `test/system/admin/blocks_test.rb` add:

```ruby
  # Design answer, first reply: a tall empty gap between a card's header and
  # its first label (the reserved save line, Ruling 20).
  test "a card's first label stands just under its header" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers

    gap = page.evaluate_script(<<~JS)
      (() => {
        const card = document.getElementById(#{ActionView::RecordIdentifier.dom_id(block).to_json})
        const head = card.querySelector(".admin-block-card__head").getBoundingClientRect()
        const label = card.querySelector("[data-field-name='body'] p").getBoundingClientRect()
        return label.top - head.bottom
      })()
    JS
    assert_operator gap, :<=, 16
  end

  # Review focus 2.
  test "a long save message wraps in the header and leaves the menu inside the card" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    card = "##{ActionView::RecordIdentifier.dom_id(block)}"
    status = "##{Admin::EditorScreen::BlockCardComponent.status_id(block)}"

    page.execute_script(<<~JS)
      document.querySelector(#{card.to_json}).style.width = "360px"
      document.querySelector(#{status.to_json}).textContent = "SAVED · ALSO CHANGED ELSEWHERE — RELOAD TO SEE THE LATEST"
    JS
    inside = page.evaluate_script(<<~JS)
      (() => {
        const card = document.querySelector(#{card.to_json}).getBoundingClientRect()
        const menu = document.querySelector(#{card.to_json} + " .admin-block-card__head button[aria-label='Block actions']").getBoundingClientRect()
        return menu.width > 0 && menu.right <= card.right + 0.5
      })()
    JS
    assert inside, "the Block actions button left the card"
  ensure
    page.execute_script("document.querySelector(#{card.to_json})?.style.removeProperty('width')") if card
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `PGGSSENCMODE=disable bin/rails test test/lib/admin_design_rules_test.rb test/models/content_model/code_field_test.rb test/components/admin/editor_screen/block_card_component_test.rb`, then `bin/rails tailwindcss:build && PGGSSENCMODE=disable bin/rails test test/system/admin/blocks_test.rb`
Expected: FAIL — no `.admin-disclosure`; `ArgumentError: `blank:` names the empty choice of a select that isn't required`; the empty option has no text; the status is in the body; the gap is about 44px.

- [ ] **Step 3: The disclosure**

In `content-spiel.tailwind.css`, after the `.cs-select` rules, add:

```css
/* A disclosure whose summary is a mono label ("▸ PAGE SETTINGS", the SEO
   and Shared fields boxes, an audit event's Snapshot). The browser's own
   marker stood against the first letter; this triangle is the
   stylesheet's, 6px from the words, turned when open, and skipped by a
   screen reader (the empty alternative text after the slash), so the words
   are the summary's only content. */
.admin-disclosure { list-style: none; display: flex; align-items: center; gap: 0.375rem; }
.admin-disclosure::-webkit-details-marker { display: none; }
.admin-disclosure::before { content: "▸"; content: "▸" / ""; display: inline-block; transition: transform 150ms var(--cs-ease); }
details[open] > .admin-disclosure::before { transform: rotate(90deg); }
@media (prefers-reduced-motion: reduce) { .admin-disclosure::before { transition: none; } }
```

Add `admin-disclosure` as the first class of each `<summary>` in `page_settings_form_component.html.erb` (both), `shared_fields_component.html.erb` and `app/views/admin/audit_events/show.html.erb`.

- [ ] **Step 4: "All types"**

In `app/models/content_model/definition.rb`, the last refusal becomes:

```ruby
      raise ArgumentError, "`blank:` names the empty choice of a select that isn't required" if options.key?(:blank) && (!%i[select content_type].include?(type) || options[:required])
```

and the comment above `OPTIONS` reads "`blank:` is the label of a select's (or a content type field's) empty choice ("Plain text", "All types")". In `app/models/block_types/post_list.rb`: `t.field :content_type, :content_type` → `t.field :content_type, :content_type, blank: "All types"`. (`Admin::Fields::ContentTypeField` is a `SelectField` and reads `blank_choice` already.)

- [ ] **Step 5: The save line in the card's header**

In `block_card_component.rb`, after `def status_id = self.class.status_id(block)` add:

```ruby
      # The card's save line, in the header row before the "⋯" menu, as the
      # section card's is (contrast and buttons spec, Ruling 20). In the body
      # it reserved a line of its own above the first field, the gap the
      # design answer saw; the header's height is its buttons', so the line
      # costs nothing there and still never moves what is under a press. A
      # long message (stale, saved over) wraps the header instead.
      def status_line
        tag.div(render(Admin::Ui::SaveStatusComponent.new(id: status_id, state: :idle, live: page.published_at.present?)),
          class: "admin-block-card__status min-w-0 shrink text-right")
      end
```

In `block_card_component.html.erb`:
- the header row's opening tag `<div class="flex items-center gap-2 p-3 <%= "border-b border-line hover:bg-sunken" unless unavailable? %>">` becomes `<div class="admin-block-card__head flex items-center gap-2 p-3 <%= "border-b border-line hover:bg-sunken" unless unavailable? %>">`;
- in the panel branch, after `<h3 id="<%= self.class.panel_title_id(block) %>" …</h3>` and its `<span data-editing-mark-slot>…</span>`, add `<%= status_line %>`;
- in the group branch (`elsif !list?`), after `<span class="flex-1"></span>`, add `<%= status_line %>`;
- in the list branch, directly after the `</div>` that closes `<div class="flex min-w-0 flex-1 items-center gap-2">`, add `<%= status_line %>`;
- delete `<%= render Admin::Ui::SaveStatusComponent.new(id: status_id, state: :idle, live: page.published_at.present?) %>` from the body (`[data-block-body]`).

- [ ] **Step 6: Run the tests**

Run: `PGGSSENCMODE=disable bin/rails test test/lib/admin_design_rules_test.rb test/models test/components test/integration/admin/content_blocks_test.rb test/integration/admin/page_editor_test.rb`, then `bin/rails tailwindcss:build`, then one at a time: `PGGSSENCMODE=disable bin/rails test test/system/admin/blocks_test.rb`, `… test/system/admin/autosave_test.rb`, `… test/system/admin/sections_test.rb`, `… test/system/admin/editing_merge_test.rb`, `… test/system/admin/editing_holds_test.rb`, `… test/system/admin/changed_elsewhere_test.rb`.
Expected: PASS (the autosave controller finds the line by its id; the live merge keeps ids).

- [ ] **Step 7: Commit**

```bash
git add -A app test
git commit -m "fix: the page settings triangle has its space, a post list offers All types, a card's save line sits in its header, and the gap under it is gone

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

---

### Task 10: The rules, the references, the roadmap, the full check and the pull request

**Files:**
- Modify: `CLAUDE.md`, `docs/reference/design-system.md`, `docs/reference/theming.md`, `docs/reference/cs-studio-shell-and-dashboard.md`, `docs/reference/content-blocks-and-types.md`, `docs/roadmap.md`, `docs/superpowers/specs/2026-10-15-contrast-and-buttons-design.md` ("As built")

- [ ] **Step 1: The rules in `CLAUDE.md`**

Replace the bullet "CS Studio sources use tokens, not colour literals: …(`test/lib/admin_design_rules_test.rb`)." with:

```markdown
- CS Studio sources use tokens, not colour literals: no hex or `rgb()`/`hsl()` value, no `dark:` variant other than `dark:scheme-dark`, no `danger` in a translation chip or language tab, and no `mx-auto` in the shell except the 403 and 404 messages; a pressable or typed-into element is outlined in `border-field-line` (`--cs-field-line`, 3:1 on paper, surface and sunken), never `border-line-strong`, which only groups (two named exceptions); and no text under 11px: a mono label is `text-label`, 11px at weight 500 (`test/lib/admin_design_rules_test.rb`: "a pressable or typed-into element is outlined in border-field-line, never border-line-strong", "no text under 11px in CS Studio's markup, and a mono label is text-label"). CS Studio's token pairs are measured in both schemes, text at 4.5:1 and every state mark and outline at 3:1 (`test/lib/admin_contrast_test.rb`); a changed token value that breaks a pair fails there. The guard reads a line's classes and does not see a control whose line says no hover, focus or pointer (a segmented group's frame, the drop zone).
```

In the theming rules, after the bullet "A name in `Theme::Contract` …", add:

```markdown
- The default theme's contrast is measured, not its names alone: `--th-meta` is 4.5:1 on the page and on the tinted band and is the site's control outline (3:1); `--th-line` stays a hairline; the tinted band is 1.15:1 or more against the page and the dark strong band a raised ground between 1.4 and 2:1, so a code block in a strong band is `color-scheme: dark` in both schemes (`test/integration/design_tokens_test.rb`). **No guard** measures a theme's own values.
```

- [ ] **Step 2: The references**

- `docs/reference/design-system.md`: in "Describes", add `test/lib/admin_contrast_test.rb`; in "The design pass" paragraph add the three new tokens and the field-line / line-strong rule (as in `CLAUDE.md`); in "Shared components" rewrite the `ButtonComponent` bullet (variants; `not-disabled:hover:`; secondary's ink hover; one disabled look; a busy button keeps its look through `aria-busy`), add a `BadgeComponent` bullet (the badges it draws, sunken and borderless, and that the status, unpublished, no-address and channel chips share the fill), and add to the form-controls bullet: the segmented control's selected pill is inverted with a paper focus ring (`Admin::PostsScreen::ToolbarComponent::SEGMENT_CLASS`, shared by Media and Translations; the Trash's tabs alike), the rich-text toolbar's active state, and `.admin-disclosure`.
- `docs/reference/theming.md`: the token table's `--th-meta` row becomes "labels, dates, captions: 4.5:1 on the page and on the tinted band at 11px; also the outline of a control on the site (3:1)", `--th-line-strong` becomes "a stronger line: a quote's rule"; under "Strong" (the band bullets) state that the dark strong band is a raised dark ground and a code block in it is `color-scheme: dark` in both schemes; update the figures in "Contrast is computed" (the lowest pair is now the comment in a dark strong band, 4.84:1) and name the new tests.
- `docs/reference/cs-studio-shell-and-dashboard.md`: the tree row: the state marks (`TreeStateMarkComponent`, one per row, the words, Ruling 8), the selected row's sunken ground and ink bar, "+ New page" as a small secondary button; the Mind graph: a page's mark is `theme.page` (`--cs-graph-page`), the tree's lines `tree` (`--cs-graph-tree`), the zoom buttons 28px.
- `docs/reference/content-blocks-and-types.md`: add `t.icon` to the declarations (optional, one of `ContentModel::BlockTypeDefinition::ICONS`, read by `Admin::EditorScreen::BlockIconComponent` in the picker, the card's head and the tile; an outside type names one of the list or none) and to "Adding a block type".
- In every reference file, `grep -n "line-strong\|accent-tint\|opacity-50\|compact: true\|StatusChipComponent.*tree\|text-\[10px\]" docs/reference/*.md` and correct each sentence the PR made untrue.

- [ ] **Step 3: The roadmap and the spec**

In `docs/roadmap.md`: add a "Shipped" row "Contrast and buttons (part 1): …" pointing at the spec; under "Next" or the CS Studio backlog add "Contrast and buttons, part 2" with the spec's "What is not in this pull request" list; under "Known gaps" add "cat-5 sits near the accent in dark (contrast and buttons spec, Ruling 5)" and "the native checkbox keeps the browser's outline (Ruling 10)"; in the gap "Three guards read less than they seem to", delete "and does not measure the caption's `--th-meta`" (measured now). At the end of the spec add "## As built" listing where the code departed from it (or "No departures").

- [ ] **Step 4: The full check**

Run, in order, each after the previous has finished:

```bash
bin/rubocop
bin/brakeman
bin/rails tailwindcss:build && bin/rails theme_css:build
PGGSSENCMODE=disable bin/rails test
sysctl -n vm.loadavg
PARALLEL_WORKERS=6 PGGSSENCMODE=disable bin/rails test:system
bin/theme-build-check
git status --short
```

Expected: rubocop and brakeman clean, every test green, the browser suite in about its usual time (a run twice as long is not a result), `bin/theme-build-check` succeeds, and the stylesheet's stamp is back as the default theme's (`git status` shows nothing but the docs of this task).

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md docs
git commit -m "docs: the contrast rules, the button system, block icons and the tree's marks in CLAUDE.md, the references and the roadmap

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT"
```

- [ ] **Step 6: The pull request's text** (the controller opens the PR; nothing is pushed by this plan)

```markdown
## Contrast and buttons (part 1 of 2)

Claude Design's answers C1, C2, D1 and D2 of 2026-10-15, as the owner split them.

- **Contrast (C1).** A boundary that marks a control or a state reaches 3:1; one that only groups stays faint, a little stronger. New `--cs-field-line` outlines every input, select, toggle, button and segmented control; lines, strong lines, sunken, meta, dim and dark mode's four grounds move; every label is 11px at weight 500. The site's lines, tinted band and faint text follow; no theme token is added or renamed.
- **Buttons (D1).** One primary per screen (Discard changes… is a ghost), outlined secondaries with an ink hover, one disabled look (a busy button keeps its own), badges without an outline, inverted filter pills with a paper focus ring, a visible active state in the rich-text toolbar, 28px zoom buttons, and the site's Copy, theme and language controls.
- **Icons and marks (C2).** Each block type declares an icon, drawn in the picker, on the card and on the section tile; the page tree marks Draft, Scheduled and unpublished changes with one small named mark, and shows the selected row.
- **Light and dark (D2).** cat-5 moves to hue 260 in dark; the Mind graph's page marks and tree lines read in dark; a strong band in a dark page is a raised dark ground.
- **Small fixes.** The Page settings triangle has its space; an empty band draws nothing on the site; a post list offers "All types"; a block card's save line sits in its header.

Every promised ratio is a test (`test/lib/admin_contrast_test.rb`, `test/integration/design_tokens_test.rb`). The 21 rulings where the design answer was silent or conflicted with the code are in the spec.

Not in this PR: part 2's list (form widths, Translations words, Media drop zone, Settings, the slug line, two-letter avatars, the Mind graph legend, site captions, Related, tags as links, the dashboard grid, activity, Notes for you) and the Note block.

## Documentation

Editors: `editors/getting-started/signing-in-and-finding-your-way.md`, `editors/pages/the-page-tree.md`, `editors/pages/build-a-page-with-blocks.md`, `editors/pages/arrange-blocks-in-sections.md`, `editors/pages/the-rich-text-editor.md`, `editors/pages/page-settings-and-search-appearance.md`, `editors/posts/work-with-many-posts.md`, `editors/posts/publish-schedule-and-preview.md`, `editors/posts/tags-related-posts-and-the-mind-graph.md`, `editors/translating/keep-translations-up-to-date.md`, `editors/media/the-media-library.md`, `editors/trash/the-trash.md`, `editors/working-together/notes-on-content.md` (screenshots and the words for icons, marks, pills, the save line, Discard changes). Administrators: `administrators/site/languages.md` (DEFAULT). Integrators: `integrators/theming/the-theme-contract.md` (changed default values, the dark strong band, `--th-meta`'s 4.5:1 and outline role, `--th-line-strong`'s narrower role), `integrators/how-it-works/adding-a-block-type.md` and `integrators/how-it-works/block-types-from-outside.md` (`t.icon`).

**Release note for theme authors:** the dark strong band is now a dark ground (`--th-band-strong: #34353a`) and its three text tokens changed with it; a theme that set its own dark `--th-band-strong` should set the three `--th-on-band-strong*` too.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01B1T44ndwnt9ofQCkDEUcKT
```

---

## Self-review

- **Spec coverage.** C1 CS Studio tokens: Task 1 (values), Task 2 (outlines, labels, circle), Task 6 (selected row), table rule by value (spec says all six tables already draw it). C1 site: Task 8. C2: Task 5 (icons), Task 6 (marks). D1: Task 3 (primary/secondary/disabled/badges/View on site/split/New page/New note already small secondary), Task 4 (pills, toolbar, zoom), Task 8 (Copy, theme button, language switcher). D2: Task 1 (grounds, cat-5), Task 7 (graph), Task 8 (strong band). Small fixes: Task 8 (empty band), Task 9 (triangle, All types, the gap). Rulings 1–21 each land in the task named beside it. Not-in-PR items have no task.
- **Placeholders.** None: every code step carries its code; the bulk edits are scripts with their exact lines; Task 10's reference edits name each file and what each says.
- **Names.** `ContrastMeasure#resolve_colour/contrast/mix` (Task 1) are what Tasks 7 and 8 call; `each_scheme`/`schemes`/`assert_ratio` (Task 1) are Task 7's; `border-field-line` (Task 1) is Task 2's; `BadgeComponent` (Task 3); `BlockIconComponent::PLACES`, `ICONS`, `#icon` (Task 5); `TreeStateMarkComponent` (Task 6); theme keys `page`/`tree` (Task 7); `status_line`, `.admin-block-card__head`, `.admin-disclosure` (Task 9).
- **Review Focus.** Each of the five has its test in its task (3, 9, 5, 6, 4).
