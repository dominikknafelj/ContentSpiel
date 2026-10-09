require "test_helper"

# Backend (product UI) and frontend (public theme) CSS are two separate builds
# (spec §9): each carries its own tokens and only the classes its own views use.
class DesignTokensTest < ActionDispatch::IntegrationTest
  test "the product build carries product tokens and no theme tokens" do
    css = stylesheet("tailwind.css")

    assert_includes css, "--cs-paper"
    assert_not_includes css, "--th-"
    assert_not_includes css, "cs-prose"
  end

  # Once deleted by accident in an unrelated commit: SortableJS and the
  # keyboard path both style the dragged row through these classes.
  test "the product build carries the drag pattern classes" do
    css = stylesheet("tailwind.css")

    assert_includes css, ".admin-drag-ghost"
    assert_includes css, ".admin-drag-chosen"
  end

  test "the theme build carries theme tokens and no product tokens or product-only classes" do
    css = stylesheet("theme-default.css")

    assert_includes css, "--th-paper"
    assert_includes css, "cs-prose"
    assert_not_includes css, "--cs-"
    # `md:rounded-l-cs` is only used by the setup wizard's layout.
    assert_not_includes css, "md\\:rounded-l-cs"
    assert_includes stylesheet("tailwind.css"), "md\\:rounded-l-cs"
  end

  # The preview bar looks the same in light and dark: two tokens, declared once
  # in the base block and never in the dark one, readable at 4.5:1 or better.
  test "the preview bar tokens are the same in light and dark and have readable contrast" do
    tokens = Rails.root.join("app/assets/tailwind/themes/default/tokens.css").read
    dark_block = tokens[/\[data-theme="dark"\]\s*\{.*?\}/m]

    assert_not_includes dark_block, "--th-preview"
    background = tokens[/--th-preview-bg:\s*#(\h{6})/, 1] or flunk("--th-preview-bg missing")
    ink = tokens[/--th-preview-ink:\s*#(\h{6})/, 1] or flunk("--th-preview-ink missing")

    luminance = ->(hex) do
      hex.scan(/../).map { |pair| (channel = pair.hex / 255.0) <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055)**2.4 }
        .zip([ 0.2126, 0.7152, 0.0722 ]).sum { |value, weight| value * weight }
    end
    light, dark = [ luminance.(background), luminance.(ink) ].minmax.reverse
    assert_operator (light + 0.05) / (dark + 0.05), :>=, 4.5
    assert_includes stylesheet("theme-default.css"), ".bg-preview-bg"
  end

  # Sections spec §5.3: the two bands and what is written on the strong one,
  # each with its dark value -- a band is drawn in whichever theme the visitor
  # has, unlike the preview bar above.
  BAND_TOKENS = %w[--th-band-tinted --th-band-strong --th-on-band-strong --th-on-band-strong-dim --th-on-band-strong-accent].freeze

  test "the band tokens exist in both themes, map to utilities, and the sections stylesheet holds no colour of its own" do
    light, dark = theme_tokens.values_at(:light, :dark)
    BAND_TOKENS.each do |token|
      assert light.key?(token), "#{token} missing from the light theme"
      assert dark.key?(token), "#{token} missing from the dark theme"
    end
    map = Rails.root.join("app/assets/tailwind/themes/default/theme.css").read
    %w[band-tinted band-strong on-band-strong].each { |name| assert_includes map, "--color-#{name}: var(--th-#{name});" }

    css = Rails.root.join("app/assets/tailwind/themes/default/sections.css").read
    refute_match(/#\h{3,8}\b|\brgba?\(|\bhsla?\(|\boklch\(/, css)
  end

  # WCAG 1.4.3: 4.5:1 for text. On the strong band the three colours a block
  # can write in; on the tinted band the ordinary text tokens, with `meta`
  # read as `sections.css` remaps it there (plain `--th-meta` on the light
  # tinted band is 4.3:1, which is why it is remapped).
  test "text on a band is readable in both themes" do
    theme_tokens.each do |theme, tokens|
      colour = ->(name) { resolve_colour(tokens, name) }
      { "--th-band-strong" => %w[--th-on-band-strong --th-on-band-strong-dim --th-on-band-strong-accent],
        "--th-band-tinted" => %w[--th-ink --th-dim --th-accent --th-accent-hover] }.each do |band, inks|
        inks.each do |ink|
          ratio = contrast(colour.(band), colour.(ink))
          assert_operator ratio, :>=, 4.5, "#{ink} on #{band} (#{theme}) is #{ratio.round(2)}:1"
        end
      end
    end
  end

  test "the theme build carries the section grid, its container queries and the body's clip" do
    css = stylesheet("theme-default.css")

    assert_includes css, ".content-section__grid--one_two"
    assert_includes css, ".content-section--full"
    assert_match(/@container[^{]*30rem/, css)
    assert_match(/@container[^{]*44rem/, css)
    assert_includes css, ".overflow-x-clip"
  end

  test "both builds point at the digested, served font files" do
    font_path = helpers.asset_path("archivo-latin-400-normal.woff2")

    assert_includes stylesheet("tailwind.css"), font_path
    assert_includes stylesheet("theme-default.css"), font_path
    get font_path
    assert_response :success
  end

  test "the public layout links only the theme stylesheet" do
    Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    get "/"

    assert_select "link[rel=stylesheet][href*='theme-default']"
    assert_select "link[rel=stylesheet][href*='/tailwind-']", count: 0
  end

  test "sign-in uses the product layout and stylesheet" do
    get admin_sign_in_path

    assert_select "link[rel=stylesheet][href*='/tailwind-']"
    assert_select "link[rel=stylesheet][href*='theme-default']", count: 0
    assert_includes response.body, 'localStorage.getItem("cs-theme")'
  end

  test "the chrome and content-type tokens exist in both themes and map to utilities" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.css").read
    light, dark = css.split('[data-theme="dark"] {', 2)
    %w[--cs-chrome --cs-cat-1 --cs-cat-2 --cs-cat-3 --cs-cat-4 --cs-cat-5 --cs-cat-6].each do |token|
      assert_includes light, "#{token}:", "#{token} missing from the light theme"
      assert_includes dark, "#{token}:", "#{token} missing from the dark theme"
    end
    map = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read
    assert_includes map, "--color-chrome: var(--cs-chrome);"
    (1..6).each { |n| assert_includes map, "--color-cat-#{n}: var(--cs-cat-#{n});" }
    refute_match(/color-scheme\s*:/, css.gsub(%r{/\*.*?\*/}m, ""), "color-scheme stays per layout, never global")
  end

  private
    def helpers = ActionController::Base.helpers

    # `tokens.css`'s two colour blocks as { "--th-name" => "value" }.
    def theme_tokens
      css = Rails.root.join("app/assets/tailwind/themes/default/tokens.css").read
      { light: css[/:root, \[data-theme="light"\]\s*\{(.*?)\}/m, 1], dark: css[/\[data-theme="dark"\]\s*\{(.*?)\}/m, 1] }
        .transform_values { |block| block.scan(/(--th-[\w-]+):\s*([^;]+);/).to_h }
    end

    # A token's colour as linear-light sRGB, following `var()` to its value.
    # Hex and `oklch()` are the two notations the opaque tokens use.
    def resolve_colour(tokens, name)
      case tokens.fetch(name)
      when /\Avar\((--th-[\w-]+)\)\z/ then resolve_colour(tokens, $1)
      when /\A#(\h{6})\z/
        $1.scan(/../).map { |pair| (channel = pair.hex / 255.0) <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055)**2.4 }
      when /\Aoklch\(([\d.]+) ([\d.]+) ([\d.]+)\)\z/ then oklch_to_linear_srgb($1.to_f, $2.to_f, $3.to_f)
      else flunk("#{name} is neither a hex colour nor oklch(): #{tokens[name]}")
      end
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

    def contrast(one, other)
      light, dark = [ one, other ].map { |rgb| rgb.zip([ 0.2126, 0.7152, 0.0722 ]).sum { |value, weight| value * weight } }.minmax.reverse
      (light + 0.05) / (dark + 0.05)
    end

    def stylesheet(name)
      get helpers.asset_path(name)
      assert_response :success
      response.body
    end
end
