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
