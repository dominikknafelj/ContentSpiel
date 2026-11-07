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
  GROUNDS = %w[--cs-paper --cs-surface --cs-sunken --cs-chrome --cs-rail --cs-popover --cs-field-fill].freeze
  # Where a control stands: the page (paper), a card (surface), a text
  # field's own ground, a rail and a popover. Sunken is not one: it is
  # hover, badges and disabled, no control edge stands on it, and the field
  # line on light sunken measures 2.97:1.
  FIELD_GROUNDS = %w[--cs-paper --cs-surface --cs-field-fill --cs-rail --cs-popover].freeze

  # `content-spiel.css`'s two colour blocks as { "--cs-name" => "value" }.
  def schemes
    css = STYLESHEET.read.gsub(%r{/\*.*?\*/}m, "")
    { light: css[/:root, \[data-theme="light"\]\s*\{(.*?)\}/m, 1], dark: css[/\[data-theme="dark"\]\s*\{(.*?)\}/m, 1] }
      .transform_values { |block| block.scan(/(--cs-[\w-]+):\s*([^;]+);/).to_h.transform_values(&:strip) }
  end

  # The `[data-surface="plain"]` block as { "--cs-name" => "value" }: the
  # accent family re-valued for a visitor's page, merged over each scheme.
  def plain_surface
    css = STYLESHEET.read.gsub(%r{/\*.*?\*/}m, "")
    css[/\[data-surface="plain"\]\s*\{(.*?)\}/m, 1].to_s.scan(/(--cs-[\w-]+):\s*([^;]+);/).to_h.transform_values(&:strip)
  end

  # Each scheme's name and a lambda: a token's colour, a translucent one
  # painted over the token named `under`.
  def each_scheme
    schemes.each do |scheme, tokens|
      yield scheme, ->(name, under: nil) { resolve_colour(tokens, name, under: under && resolve_colour(tokens, under)) }, tokens
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
  test "a state mark is 3:1 or better on the surface, the tree's chrome and the rail" do
    each_scheme do |scheme, colour|
      %w[--cs-surface --cs-chrome --cs-rail].product(%w[--cs-ok --cs-warn --cs-dim --cs-meta]).each do |ground, mark|
        assert_ratio(3.0, colour.(mark), colour.(ground), "#{mark} on #{ground} (#{scheme})")
      end
    end
  end

  test "the selected row's accent bar is 3:1 or better on its sunken ground and on the chrome" do
    each_scheme do |scheme, colour|
      %w[--cs-sunken --cs-chrome].each { |ground| assert_ratio(3.0, colour.("--cs-accent"), colour.(ground), "the selected row's accent bar on #{ground} (#{scheme})") }
    end
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    assert_match(/\.admin-tree-row--selected\s*\{\s*box-shadow:\s*inset 3px 0 0 var\(--cs-accent\);\s*\}/, css)
  end

  test "a selected state is seen: a selected pill's words and its paper focus ring, and the accent ring at rest" do
    each_scheme do |scheme, colour|
      assert_ratio(4.5, colour.("--cs-paper"), colour.("--cs-ink"), "a selected pill's words and ring (#{scheme})")
      assert_ratio(3.0, colour.("--cs-accent"), colour.("--cs-surface"), "the focus ring on a pill at rest (#{scheme})")
    end
    dark = schemes[:dark]
    assert_operator contrast(resolve_colour(dark, "--cs-accent"), resolve_colour(dark, "--cs-ink")), :<, 3.0,
      "the reason for the paper ring: the accent on a dark selected pill is too faint"
  end

  test "a menu's keyboard row and the palette's selected row carry an accent bar, 3:1 on the popover, where their sunken fill is not" do
    each_scheme do |scheme, colour|
      assert_ratio(3.0, colour.("--cs-accent"), colour.("--cs-popover"), "the keyboard row's accent bar on the popover (#{scheme})")
    end
    dark = schemes[:dark]
    assert_operator contrast(resolve_colour(dark, "--cs-sunken"), resolve_colour(dark, "--cs-popover")), :<, 3.0,
      "the reason for the bar: a sunken row on the dark popover is too faint to be the only cue"
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    assert_match(/\.admin-menu-panel :is\(a, button\):focus-visible,\s*\.admin-palette \[role="option"\]\[aria-selected="true"\] > a\s*\{\s*box-shadow:\s*inset 2px 0 0 var\(--cs-accent\);\s*\}/, css)
    assert_includes Rails.root.join("app/components/admin/ui/menu_component.rb").read, '"admin-menu-panel '
  end

  test "a line that only groups stays a hairline: the strong one above the plain one, both under 3:1" do
    each_scheme do |scheme, colour|
      surface = colour.("--cs-surface")
      line = contrast(colour.("--cs-line", under: "--cs-surface"), surface)
      strong = contrast(colour.("--cs-line-strong", under: "--cs-surface"), surface)
      assert_operator line, :>=, 1.2, "--cs-line (#{scheme}) is #{line.round(2)}:1"
      assert_operator strong, :>=, 1.55, "--cs-line-strong (#{scheme}) is #{strong.round(2)}:1"
      assert_operator strong, :>, line, "the strong line is above the plain one (#{scheme})"
      assert_operator strong, :<, 3.0, "a strong line at 3:1 would be an outline: that is --cs-field-line (#{scheme})"
    end
  end

  test "the grounds step apart: sunken from surface, and in dark each elevation over the one below" do
    each_scheme { |scheme, colour| assert_ratio(1.10, colour.("--cs-sunken"), colour.("--cs-surface"), "sunken against surface (#{scheme})") }
    dark = schemes[:dark]
    [ %w[--cs-surface --cs-paper], %w[--cs-rail --cs-surface], %w[--cs-popover --cs-rail] ].each do |upper, lower|
      assert_ratio(1.10, resolve_colour(dark, upper), resolve_colour(dark, lower), "#{upper} over #{lower} (dark)")
    end
  end

  # A block card's state edges (`content-spiel.tailwind.css`): held, its
  # type gone, its thread open. The edge is the card's only outline, so it is
  # held to a state's 3:1 on the card it is drawn inside and on the canvas
  # around the card.
  test "a card's state edge is 3:1 or better against the card and the canvas, in both schemes" do
    each_scheme do |scheme, colour|
      %w[--cs-field-line --cs-danger --cs-accent].product(%w[--cs-surface --cs-paper]).each do |edge, ground|
        assert_ratio(3.0, colour.(edge), colour.(ground), "the #{edge} edge on #{ground} (#{scheme})")
      end
    end
  end

  # The rail's tabs (`.admin-rail__tab`, `Admin::Ui::RailTabsComponent`) stand
  # on the rail's ground, the grid's `::before`. A tab's words and the selected
  # tab's are text; the selected tab's underline is a state's mark. Each colour
  # is read from the rule that draws it, so a changed rule is measured too.
  test "the rail's tabs: a tab's words and the selected tab's are 4.5:1 on the rail, its underline 3:1" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    ground = css[/\.admin-rail-grid:not\(\.admin-rail-grid--folded\)::before\s*\{[^}]*background:\s*var\((--cs-[\w-]+)\)/, 1]
    words = css[/\.admin-rail__tab\s*\{[^}]*(?<![\w-])color:\s*var\((--cs-[\w-]+)\)/, 1]
    selected = css[/\.admin-rail__tab\[aria-selected="true"\]\s*\{([^}]*)\}/, 1]
    assert ground && words && selected, "the rail's ground, a tab's words and the selected tab are drawn by the stylesheet"
    assert_equal "--cs-rail", ground
    selected_words = selected[/(?<![\w-])color:\s*var\((--cs-[\w-]+)\)/, 1]
    underline = selected[/box-shadow:\s*inset 0 -2px 0 var\((--cs-[\w-]+)\)/, 1]
    assert selected_words && underline, "the selected tab names its words and a 2px underline"
    assert_equal "--cs-accent", underline
    each_scheme do |scheme, colour|
      assert_ratio(4.5, colour.(words), colour.(ground), "a tab's #{words} words on #{ground} (#{scheme})")
      assert_ratio(4.5, colour.(selected_words), colour.(ground), "the selected tab's #{selected_words} words on #{ground} (#{scheme})")
      assert_ratio(3.0, colour.(underline), colour.(ground), "the selected tab's #{underline} underline on #{ground} (#{scheme})")
    end
  end

  # The section chosen in the page editor's rail (`.admin-section-card[data-chosen]`):
  # an outline 2px outside the frame, so it stands on the canvas. Its colour is
  # read from the rule that draws it.
  test "the chosen section's outline is 3:1 or better on the canvas, in both schemes" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    rule = css[/\.admin-section-card\[data-chosen\]\s*\{([^}]*)\}/, 1]
    assert rule, "the chosen section is drawn by the stylesheet"
    outline = rule[/outline:\s*2px solid var\((--cs-[\w-]+)\)/, 1]
    assert_equal "--cs-accent", outline, "a selection is the accent"
    assert_match(/outline-offset:\s*2px/, rule, "the outline stands outside the frame, on the canvas")
    each_scheme do |scheme, colour|
      assert_ratio(3.0, colour.(outline), colour.("--cs-paper"), "the chosen section's #{outline} outline on the canvas (#{scheme})")
    end
  end

  # A section's head (`.admin-section-card__head`): its words in the
  # structure ink on the structure tint, and a word under the pointer or
  # focused on the ink thinned to 12% over that tint (`.admin-section-word`).
  # The name, the handle and the count stand on the same tint.
  test "a section head's words and its hovered word are 4.5:1 or better on the structure tint" do
    each_scheme do |scheme, colour|
      tint = colour.("--cs-structure-tint")
      hovered = mix(colour.("--cs-structure-ink"), tint, 0.12)
      assert_ratio(4.5, colour.("--cs-structure-ink"), tint, "a word on the head (#{scheme})")
      assert_ratio(4.5, colour.("--cs-structure-ink"), hovered, "a hovered word (#{scheme})")
      %w[--cs-ink --cs-meta].each { |ink| assert_ratio(4.5, colour.(ink), tint, "#{ink} on the head (#{scheme})") }
      assert_ratio(3.0, colour.("--cs-accent"), hovered, "a focused word's ring (#{scheme})")
    end
  end

  # A section's frame only groups (2.6:1 on the canvas, held above that
  # floor); its state edges, held and unavailable, are a state's 3:1 on the
  # canvas outside it and on the head's tint and the settings' rail inside.
  test "a section's frame groups, and its held and unavailable edges are 3:1 or better on the canvas, the head and the settings" do
    each_scheme do |scheme, colour|
      assert_operator contrast(colour.("--cs-structure"), colour.("--cs-paper")), :>=, 2.6, "the frame on the canvas (#{scheme})"
      %w[--cs-field-line --cs-danger].product(%w[--cs-paper --cs-structure-tint --cs-rail]).each do |edge, ground|
        assert_ratio(3.0, colour.(edge), colour.(ground), "the section's #{edge} edge on #{ground} (#{scheme})")
      end
    end
  end

  # An open or focused tile (`content-spiel.tailwind.css`, `.admin-block-tile`)
  # is ringed in the accent outside its edge, where it stands on the section
  # frame's tint or, in a lane at the page's own width, on the canvas.
  test "the open tile's accent ring is 3:1 or better against the frame's ground and the canvas" do
    each_scheme do |scheme, colour|
      %w[--cs-paper --cs-structure-tint].each { |ground| assert_ratio(3.0, colour.("--cs-accent"), colour.(ground), "the tile's ring on #{ground} (#{scheme})") }
    end
  end

  # The drop place (`.admin-drag-ghost`, a tile's, a block card's and a tree
  # row's) is a dashed edge with nothing inside it: the edge alone says where
  # the drag lands, so it is a state's 3:1 on the grounds it stands on.
  test "the drop place's dashed edge is 3:1 or better on the surface and the canvas" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read
    edge = css[/\.admin-drag-ghost \{[^}]*border: 1\.5px dashed var\((--cs-[\w-]+)\)/, 1]
    assert edge, "the ghost's edge is a token"
    each_scheme do |scheme, colour|
      %w[--cs-surface --cs-paper].each { |ground| assert_ratio(3.0, colour.(edge), colour.(ground), "the drop place's #{edge} on #{ground} (#{scheme})") }
    end
  end

  # The preview's words (`TileSummaryComponent`): the heading in ink and the
  # text in dim, on the tile at rest and raised.
  test "a tile's preview is readable on the tile at rest and raised" do
    each_scheme do |scheme, colour|
      %w[--cs-ink --cs-dim --cs-meta].product(%w[--cs-surface --cs-tile-raised]).each do |ink, ground|
        assert_ratio(4.5, colour.(ink), colour.(ground), "#{ink} on #{ground} (#{scheme})")
      end
    end
  end

  test "words on a raised tile are readable: ink, dim and meta 4.5:1 on --cs-tile-raised" do
    each_scheme do |scheme, colour|
      %w[--cs-ink --cs-dim --cs-meta].each { |ink| assert_ratio(4.5, colour.(ink), colour.("--cs-tile-raised"), "#{ink} on --cs-tile-raised (#{scheme})") }
    end
  end

  test "the primary's, the secondary's and the danger confirm's words are 4.5:1 or better on their fills, at rest and hovered" do
    each_scheme do |scheme, colour|
      assert_ratio(4.5, colour.("--cs-on-accent"), colour.("--cs-accent"), "the primary at rest (#{scheme})")
      assert_ratio(4.5, colour.("--cs-on-accent"), colour.("--cs-accent-hover"), "the primary hovered (#{scheme})")
      assert_ratio(4.5, colour.("--cs-accent"), colour.("--cs-accent-tint"), "the secondary (#{scheme})")
      assert_ratio(4.5, colour.("--cs-on-danger"), colour.("--cs-danger"), "the danger confirm (#{scheme})")
    end
  end

  test "the accent focus ring is 3:1 or better on every ground, the rail and the popover included" do
    each_scheme do |scheme, colour|
      GROUNDS.each { |ground| assert_ratio(3.0, colour.("--cs-accent"), colour.(ground), "the focus ring on #{ground} (#{scheme})") }
    end
  end

  test "Live, a scheduled date, a panel head's words, a section head's words and the type chip's words are 4.5:1 or better" do
    each_scheme do |scheme, colour|
      { "--cs-on-live" => "--cs-live", "--cs-on-scheduled" => "--cs-scheduled",
        "--cs-head-action-ink" => "--cs-head-action", "--cs-head-cool-ink" => "--cs-head-cool", "--cs-head-warm-ink" => "--cs-head-warm",
        "--cs-structure-ink" => "--cs-structure-tint", "--cs-type-chip-ink" => "--cs-type-chip" }.each do |ink, fill|
        assert_ratio(4.5, colour.(ink), colour.(fill), "#{ink} on #{fill} (#{scheme})")
      end
      assert_ratio(3.0, colour.("--cs-live"), colour.("--cs-surface"), "the Live chip's shape on the surface (#{scheme})")
    end
  end

  # Docked in the dashboard's rail an information panel has no band: its
  # heading and line stand on the rail itself, in the warm head's ink; the
  # action ink is measured there too, for a panel of that kind beside it.
  test "an information panel's heading and line read on the rail's ground" do
    each_scheme do |scheme, colour|
      %w[--cs-head-warm-ink --cs-head-action-ink].each do |ink|
        assert_ratio(4.5, colour.(ink), colour.("--cs-rail"), "#{ink} on --cs-rail (#{scheme})")
      end
    end
  end

  # `Admin::Ui::ScheduledDateComponent`: its month and day in the block's ink.
  test "the scheduled date's words read on its block" do
    each_scheme do |scheme, colour|
      assert_ratio(4.5, colour.("--cs-on-scheduled"), colour.("--cs-scheduled"), "--cs-on-scheduled on --cs-scheduled (#{scheme})")
    end
  end

  # The canvas's figures (spec, stage 5a), each a floor to its rounding: a
  # figure of 6.9 is met by 6.85. A post's hues mean post types, so each slot
  # keeps its own hue angle; only its lightness is tuned into the band.
  CANVAS = "--cs-surface"
  def floor(figure) = figure - 0.05
  CAT_HUES = { light: [ 200, 300, 120, 0, 230, 95 ], dark: [ 200, 300, 120, 0, 260, 95 ] }.freeze

  test "a post's six hues are 5.9 to 7.1:1 on the canvas in light and 8.1 to 9.1:1 in dark, each on its own hue" do
    bands = { light: 5.9..7.1, dark: 8.1..9.1 }
    each_scheme do |scheme, colour, tokens|
      (1..6).each do |slot|
        ratio = contrast(colour.("--cs-cat-#{slot}"), colour.(CANVAS))
        band = bands.fetch(scheme)
        assert_operator ratio, :>=, floor(band.begin), "--cs-cat-#{slot} (#{scheme}) is #{ratio.round(2)}:1"
        assert_operator ratio, :<, band.end + 0.05, "--cs-cat-#{slot} (#{scheme}) is #{ratio.round(2)}:1"
        hue = tokens.fetch("--cs-cat-#{slot}")[/\Aoklch\([\d.]+ [\d.]+ ([\d.]+)\)\z/, 1]
        assert_equal CAT_HUES.fetch(scheme)[slot - 1], hue&.to_f, "--cs-cat-#{slot} (#{scheme}) left its hue: #{tokens["--cs-cat-#{slot}"]}"
      end
    end
  end

  # The upper bound keeps a line from reading as text.
  test "the graph's related line is 3.9 / 4.3:1 and its tree line 3.8 / 4.5:1 on the canvas, each under its figure plus 0.4, and the shared-tag and lists lines 3:1 or better" do
    figures = { "--cs-graph-line-related" => { light: 3.9, dark: 4.3 }, "--cs-graph-line-tree" => { light: 3.8, dark: 4.5 } }
    each_scheme do |scheme, colour|
      ground = colour.(CANVAS)
      figures.each do |token, figure|
        ratio = contrast(colour.(token, under: CANVAS), ground)
        assert_operator ratio, :>=, floor(figure.fetch(scheme)), "#{token} (#{scheme}) is #{ratio.round(2)}:1"
        assert_operator ratio, :<, figure.fetch(scheme) + 0.4, "#{token} (#{scheme}) is #{ratio.round(2)}:1, near a text's figure"
      end
      %w[--cs-graph-line-tag --cs-graph-line-lists].each { |token| assert_ratio(3.0, colour.(token, under: CANVAS), ground, "#{token} (#{scheme})") }
    end
  end

  test "a tag is 6.2 / 8.9:1 or better, a page's mark 3:1 or better and in dark below the ink, and the selection ring 6.9 / 7.1:1" do
    each_scheme do |scheme, colour|
      ground = colour.(CANVAS)
      assert_ratio(floor({ light: 6.2, dark: 8.9 }.fetch(scheme)), colour.("--cs-graph-tag"), ground, "a tag (#{scheme})")
      assert_ratio(3.0, colour.("--cs-graph-page"), ground, "a page's mark (#{scheme})")
      assert_ratio(floor({ light: 6.9, dark: 7.1 }.fetch(scheme)), colour.("--cs-accent"), ground, "the selection ring (#{scheme})")
    end
    dark = schemes[:dark]
    measure = ->(name) { contrast(resolve_colour(dark, name), resolve_colour(dark, CANVAS)) }
    assert_operator measure.("--cs-graph-page"), :<, measure.("--cs-ink"), "a page's mark glares in dark: it is no softer than the ink"
  end

  # What a selection leaves out is drawn at `--cs-graph-faded`: the
  # strongest mark at it, ink, stays under a control's 3:1, and the faintest
  # post hue at it is still seen.
  test "what a selection leaves out stays seen and never reads as a control" do
    each_scheme do |scheme, colour, tokens|
      faded = Float(tokens.fetch("--cs-graph-faded"))
      ground = colour.(CANVAS)
      at_faded = ->(name) { contrast(mix(colour.(name), ground, faded), ground) }
      assert_operator at_faded.("--cs-ink"), :<, 3.0, "faded ink reads as a control (#{scheme})"
      faintest = (1..6).map { |slot| at_faded.("--cs-cat-#{slot}") }.min
      assert_operator faintest, :>=, 1.5, "a faded post is lost (#{scheme}): #{faintest.round(2)}:1"
    end
  end

  # A canvas takes `rgba()` and not `color-mix()`, so a translucent line is
  # its base token's colour written as `rgba()`, with the base named in the
  # comment beside it. This holds the two together.
  test "a graph line's translucent colour is its base token's colour" do
    css = STYLESHEET.read
    blocks = { light: css[/:root, \[data-theme="light"\]\s*\{(.*?)\n\}/m, 1], dark: css[/\[data-theme="dark"\]\s*\{(.*?)\n\}/m, 1] }
    blocks.each do |scheme, block|
      lines = block.lines.grep(/--cs-graph-line-[\w-]+:\s*rgba\(/)
      assert_operator lines.size, :>=, 3, "the translucent lines of #{scheme}"
      lines.each do |line|
        token, red, green, blue, base = line.match(%r{(--cs-graph-line-[\w-]+):\s*rgba\((\d+),\s*(\d+),\s*(\d+),\s*[\d.]+\);\s*/\*\s*(ink|dim|meta)\b}).to_a.drop(1)
        assert token, "a translucent graph line names its base token in the comment beside it: #{line.strip}"
        hex = schemes[scheme].fetch("--cs-#{base}")
        assert_equal hex.delete("#").scan(/../).map(&:hex), [ red, green, blue ].map(&:to_i), "#{token} (#{scheme}) is not --cs-#{base}'s colour"
      end
    end
  end

  # The MCP channel chip (`text-accent` on `bg-accent-tint`) and the NO ALT
  # badge (`text-warn-ink` on `bg-warn-tint`) are words on a tint.
  test "the MCP chip's and the NO ALT badge's words are 4.5:1 or better on their tints, in both schemes" do
    each_scheme do |scheme, colour|
      assert_ratio(4.5, colour.("--cs-accent"), colour.("--cs-accent-tint"), "the MCP chip (#{scheme})")
      assert_ratio(4.5, colour.("--cs-warn-ink"), colour.("--cs-warn-tint"), "the NO ALT badge (#{scheme})")
    end
  end

  # The plain pages a form's send answers without JavaScript: drawn by the
  # CMS in CS Studio's tokens, never a theme's, so they are measured here. The
  # words on the page (`bg-paper`): the label and the answers' text
  # (`--cs-ink`), the required word and the help line (`--cs-meta`), the
  # error under a control (`--cs-danger-ink`) and the back link
  # (`--cs-accent`); a control's text on its fill (`--cs-surface`); the
  # summary's words on its tint and the thank-you's on its own. A control's
  # outline and the invalid control's edge (`--cs-danger`) at 3:1 against
  # the page and the fill. The stylesheet's block is `.form-send-page`.
  test "a form's plain pages are readable in both schemes: their words, a control's text and outline, the invalid edge, the summary and the thank-you" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read
    { "label" => "--cs-ink", "required" => "--cs-meta", "help" => "--cs-meta", "error" => "--cs-danger-ink" }.each do |part, token|
      assert_match(/\.form-send-page \.form-field__#{part} \{[^}]*color: var\(#{token}\)/, css, "the #{part} is drawn in #{token}")
    end
    assert_match(/\[aria-invalid="true"\] \{ border-color: var\(--cs-danger\); \}/, css)
    assert_match(/border: 1px solid var\(--cs-field-line\)[^}]*background: var\(--cs-surface\)/m, css)

    plain = plain_surface
    each_scheme do |scheme, colour, tokens|
      tokens = tokens.merge(plain)
      colour = ->(name, under: nil) { resolve_colour(tokens, name, under: under && resolve_colour(tokens, under)) }
      assert_equal resolve_colour(tokens, "--cs-ink"), colour.("--cs-accent"), "the plain accent is the scheme's ink (#{scheme})"
      assert_equal resolve_colour(tokens, "--cs-sunken"), colour.("--cs-accent-tint"), "the plain accent tint is the scheme's sunken (#{scheme})"
      %w[--cs-paper --cs-surface].each { |ground| assert_ratio(4.5, colour.("--cs-accent"), colour.(ground), "the plain accent on #{ground} (#{scheme})") }
      assert_ratio(4.5, colour.("--cs-on-accent"), colour.("--cs-accent"), "the plain primary's words on its fill (#{scheme})")
      %w[--cs-ink --cs-meta --cs-danger-ink --cs-accent].each { |ink| assert_ratio(4.5, colour.(ink), colour.("--cs-paper"), "#{ink} on the plain page (#{scheme})") }
      assert_ratio(4.5, colour.("--cs-ink"), colour.("--cs-surface"), "an answer on its control's fill (#{scheme})")
      %w[--cs-paper --cs-surface].each do |ground|
        assert_ratio(3.0, colour.("--cs-field-line"), colour.(ground), "a control's outline on #{ground} (#{scheme})")
        assert_ratio(3.0, colour.("--cs-danger"), colour.(ground), "the invalid control's edge on #{ground} (#{scheme})")
      end
      assert_ratio(4.5, colour.("--cs-danger-ink"), colour.("--cs-danger-tint"), "the error summary's words on its tint (#{scheme})")
      assert_ratio(4.5, colour.("--cs-ok-ink"), colour.("--cs-ok-tint"), "the thank-you's words on its tint (#{scheme})")
    end
  end

  test "the plain surface re-values every accent token and nothing else" do
    assert_equal %w[--cs-accent --cs-accent-hover --cs-accent-tint --cs-on-accent], plain_surface.keys.sort
  end

  # `[data-surface="plain"]` and `[data-theme="dark"]` are both (0,1,0) on the
  # same <html>, so the plain block wins in dark only by standing after the
  # dark block; a selector that outweighs both would win wherever it stands.
  test "the plain block wins over both theme blocks: after them, or by a heavier selector" do
    css = STYLESHEET.read.gsub(%r{/\*.*?\*/}m, "")
    at = ->(selector) { css.index(/^#{Regexp.escape(selector)}\s*\{/) }
    plain = css[/^([^{}\n]*data-surface="plain"[^{}\n]*)\{/, 1].to_s.strip
    assert_not_empty plain, "the plain block is there"
    next if plain.start_with?("html[") || plain.start_with?(":root[")

    [ ':root, [data-theme="light"]', '[data-theme="dark"]' ].each do |theme|
      assert at.(theme), "#{theme} is there"
      assert_operator at.(plain), :>, at.(theme), "#{plain} stands after #{theme}: equal specificity, so the later one wins"
    end
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

  # Icon chips: the icon is a graphic, 3:1 (1.4.11) on its chip
  # and on every ground a chip stands on. People is a hue too, with no block.
  test "each family's icon is 3:1 or better on its chip and on surface, rail, chrome and popover, in both schemes" do
    families = %w[text media code form lists structure people]
    each_scheme do |scheme, colour|
      families.each do |family|
        icon = colour.("--cs-ic-#{family}")
        assert_ratio(3.0, icon, colour.("--cs-ic-#{family}-bg"), "#{family} icon on its chip (#{scheme})")
        %w[--cs-surface --cs-rail --cs-chrome --cs-popover].each { |ground| assert_ratio(3.0, icon, colour.(ground), "#{family} icon on #{ground} (#{scheme})") }
      end
    end
  end

  # Every sidebar module's chip, in its family's hue, on the sidebar's
  # ground (`--cs-chrome`) and on the current module's row, which keeps the
  # chip's family on the accent tint. The icon is the chip's meaningful mark
  # (1.4.11), so it is the icon that is measured at 3:1: on its chip, and on
  # both grounds the chip stands on. The chip's fill is decoration and is not
  # measured: on the chrome it is 1.14 (media) to 1.23:1 (structure) light
  # and 1.20 (people) to 1.37:1 (structure) dark, and on the accent tint
  # 1.01 to 1.13:1.
  def sidebar_families
    families = StudioModules.entries.map(&:family).uniq
    assert_not_includes families, :neutral, "a sidebar module's chip is never neutral"
    families
  end

  test "every sidebar module's icon is 3:1 on the sidebar's ground and on the current row" do
    families = sidebar_families
    each_scheme do |scheme, colour|
      families.each do |family|
        %w[--cs-chrome --cs-accent-tint].each do |ground|
          assert_ratio(3.0, colour.("--cs-ic-#{family}"), colour.(ground), "the #{family} module's icon on #{ground} (#{scheme})")
        end
      end
    end
  end

  test "every sidebar module's icon is 3:1 on its chip" do
    families = sidebar_families
    each_scheme do |scheme, colour|
      families.each do |family|
        assert_ratio(3.0, colour.("--cs-ic-#{family}"), colour.("--cs-ic-#{family}-bg"), "the #{family} module's icon on its chip (#{scheme})")
      end
    end
  end

  # The people hue is a circle or a bubble with initials in it: those are
  # words, so the pair is 4.5:1 and not the icon's 3:1.
  test "the people hue's initials are 4.5:1 or better on their circle, in both schemes" do
    each_scheme do |scheme, colour|
      assert_ratio(4.5, colour.("--cs-ic-people"), colour.("--cs-ic-people-bg"), "the people hue on its circle (#{scheme})")
    end
  end

  test "a Draft chip's words and outline hold on the grounds a chip stands on, in both schemes" do
    each_scheme do |scheme, colour|
      %w[--cs-paper --cs-surface --cs-rail].each do |ground|
        assert_ratio(4.5, colour.("--cs-dim"), colour.(ground), "Draft's words on #{ground} (#{scheme})")
        assert_ratio(3.0, colour.("--cs-field-line"), colour.(ground), "Draft's outline on #{ground} (#{scheme})")
      end
    end
  end

  # The Notes tab stands on the rail's ground docked and on the popover's in
  # the slide-over; the thread's reply dock paints the ground the drawer
  # names (`--cs-notes-ground`), so a message, a time, a mention, Reply and
  # the composer's edge are measured on both. Each colour is read from the
  # class that draws it.
  NOTES_GROUNDS = %w[--cs-rail --cs-popover].freeze

  def notes_template(name) = Rails.root.join("app/components/admin/notes_screen/#{name}").read

  def utility_token(classes, property)
    classes[/(?<![\w:-])#{property}-([\w-]+)/, 1].then { |name| "--cs-#{name}" }
  end

  test "the Notes tab's ground is the rail docked and the popover in the slide-over, and the reply dock paints it" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    assert_equal "--cs-popover", css[/^\.admin-notes-drawer\s*\{[^}]*--cs-notes-ground:\s*var\((--cs-[\w-]+)\)/, 1]
    assert_equal "--cs-rail", css[/\.admin-rail-grid:not\(\.admin-rail-grid--folded\) \.admin-notes-drawer\s*\{[^}]*--cs-notes-ground:\s*var\((--cs-[\w-]+)\)/, 1]
    dock = notes_template("thread_component.html.erb")[/data-note-part="reply"[^\n]* class="([^"]*)">/, 1]
    assert_includes dock.to_s.split, "bg-(--cs-notes-ground)", "the reply dock stands on the notes' ground, not on the surface"
    refute_includes dock.to_s.split, "bg-surface"
  end

  test "a note's message, its time and the viewer's own mention hold 4.5:1 on the Notes tab's grounds, in both schemes" do
    message = notes_template("message_component.html.erb")
    assert_includes message, "text-[13px] font-semibold text-ink"
    assert_match(/text-label text-meta/, message)
    viewer = Admin::NotesScreen::BodyComponent::MENTION_VIEWER_CLASS
    each_scheme do |scheme, colour|
      NOTES_GROUNDS.each do |ground|
        assert_ratio(4.5, colour.("--cs-ink"), colour.(ground), "a message's words on #{ground} (#{scheme})")
        assert_ratio(4.5, colour.("--cs-meta"), colour.(ground), "a time on #{ground} (#{scheme})")
      end
      tint = utility_token(viewer, "bg")
      assert_equal "--cs-accent-tint", tint
      assert_ratio(4.5, colour.(utility_token(viewer, "text")), colour.(tint), "the viewer's own mention on its tint (#{scheme})")
    end
  end

  test "Reply is the secondary button, 4.5:1 on the grounds a thread stands on, and the composer's edge is 3:1 there" do
    thread = notes_template("thread_component.html.erb")
    assert_match(/submit: t\("\.send_reply"\)[^%]*variant: :secondary/m, thread, "Reply is drawn as the secondary variant")
    secondary = Admin::Ui::ButtonComponent::VARIANT_CLASSES.fetch(:secondary)
    each_scheme do |scheme, colour|
      assert_ratio(4.5, colour.(utility_token(secondary, "text")), colour.(utility_token(secondary, "bg")), "Reply's words on its tint (#{scheme})")
      NOTES_GROUNDS.each do |ground|
        assert_ratio(4.5, colour.(utility_token(secondary, "text")), colour.(ground), "Reply's words on #{ground} (#{scheme})")
        assert_ratio(3.0, colour.("--cs-field-line"), colour.(ground), "the composer's edge on #{ground} (#{scheme})")
      end
    end
  end
end
