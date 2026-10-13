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
    css = stylesheet("theme.css")

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
    assert_includes stylesheet("theme.css"), ".bg-preview-bg"
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
    css = stylesheet("theme.css")

    assert_includes css, ".content-section__grid--one_two"
    assert_includes css, ".content-section--full"
    assert_match(/@container[^{]*30rem/, css)
    assert_match(/@container[^{]*44rem/, css)
    assert_includes css, ".overflow-x-clip"
  end

  test "both builds point at the digested, served font files" do
    font_path = helpers.asset_path("archivo-latin-400-normal.woff2")

    assert_includes stylesheet("tailwind.css"), font_path
    assert_includes stylesheet("theme.css"), font_path
    get font_path
    assert_response :success
  end

  test "the public layout links only the theme stylesheet" do
    Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    get "/"

    assert_select "link[rel=stylesheet][href*='/theme-']"
    assert_select "link[rel=stylesheet][href*='/tailwind-']", count: 0
  end

  test "sign-in uses the product layout and stylesheet" do
    get admin_sign_in_path

    assert_select "link[rel=stylesheet][href*='/tailwind-']"
    assert_select "link[rel=stylesheet][href*='/theme-']", count: 0
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

  # Code block spec §4: plain rules on tokens, because the span classes are
  # built from role names and no utility scan would find them.
  test "the code block's stylesheet is imported by the theme, holds no colour of its own, colours each role by its token and keeps a long line inside" do
    css = Rails.root.join("app/assets/tailwind/themes/default/code.css").read

    assert_includes Rails.root.join("app/assets/tailwind/themes/default/theme.css").read, %(@import "./code.css";)
    refute_match(/#\h{3,8}\b|\brgba?\(|\bhsla?\(|\boklch\(/, css)
    CodeHighlight::ROLES.each { |role| assert_match(/\.syn-#{role}\s*\{\s*color:\s*var\(--th-syn-#{role}\);/, css) }
    assert_no_match(/\.content-block--code\s*\{[^}]*min-width/, css, "the figure is a block wherever it is drawn; the scrolling pre is what keeps the line in")
    assert_match(/\.content-block--code pre\s*\{[^}]*overflow-x:\s*auto;[^}]*white-space:\s*pre;/m, css)
    assert_match(/\.content-block--code \.code-status\s*\{[^}]*position:\s*absolute;[^}]*width:\s*1px;[^}]*height:\s*1px;[^}]*overflow:\s*hidden;[^}]*clip-path:\s*inset\(50%\);/m, css,
      "the status line is hidden from sight by the block's own rule, so a theme's template needs no scanned utility")
    assert_match(/\.content-block--code \.code-head\s*\{[^}]*color:\s*var\(--th-dim\);/m, css, "meta on the sunken ground is 4.3:1 in the light theme; the head reads as dim")
  end

  # Design answers C1 and C8, each a rule on tokens.
  test "the code block's head is hidden where it is bare and ruled off from the code, selected code is the accent pair, the scrollbar follows the theme and the focus ring is the accent" do
    css = Rails.root.join("app/assets/tailwind/themes/default/code.css").read.gsub(%r{/\*.*?\*/}m, "")
    rule = ->(selector) { css[/(?:^|\})\s*#{Regexp.escape(selector)}\s*\{([^}]*)\}/m, 1].to_s }

    assert_match(/display:\s*none;/, rule.(".content-block--code .code-head[hidden]"), "a hidden head stays hidden although the head is a flex row")
    head = rule.(".content-block--code .code-head")
    assert_match(/border:\s*1px solid var\(--th-line\);/, head)
    assert_no_match(/border-bottom/, head, "the 1px line under the strip is the head's own border")
    assert_match(/border-top:\s*0;/, rule.(".content-block--code .code-head:not([hidden]) + pre"), "one line between the strip and the code, not two")
    assert_match(/border:\s*1px solid var\(--th-line\);[^}]*border-radius:\s*var\(--th-radius\);/m, rule.(".content-block--code pre"), "without a strip the code is a whole box")

    selection = rule.(".content-block--code pre::selection,\n.content-block--code pre ::selection")
    assert_match(/background:\s*var\(--th-accent\);\s*color:\s*var\(--th-on-accent\);/m, selection)

    assert_match(/color-scheme:\s*light;/, rule.(".content-block--code"))
    assert_match(/color-scheme:\s*dark;/, rule.(%([data-theme="dark"] .content-block--code)))

    ring = rule.(".content-block--code .code-head button:focus-visible,\n.content-block--code pre:focus-visible")
    assert_match(/outline:\s*2px solid var\(--th-accent\);/, ring)
    assert_no_match(/danger|warn/, css, "no answer of the button has a colour of its own: Not copied is as neutral as Copied")
  end

  # The strong band is the page inverted: what is written on its accent is
  # the band's own colour, and a code block in it is the other scheme.
  test "in a strong band the ink on the accent is the band's colour, readable on the band's accent, and a code block's scheme is the opposite one" do
    css = Rails.root.join("app/assets/tailwind/themes/default/sections.css").read

    assert_match(/\.content-section--strong\s*\{[^}]*--th-on-accent:\s*var\(--th-band-strong\);/m, css)
    assert_match(/^\.content-section--strong \.content-block--code\s*\{\s*color-scheme:\s*dark;/, css)
    assert_match(/^\[data-theme="dark"\] \.content-section--strong \.content-block--code\s*\{\s*color-scheme:\s*light;/, css)
    theme_tokens.each do |theme, tokens|
      ratio = contrast(resolve_colour(tokens, "--th-band-strong"), resolve_colour(tokens, "--th-on-band-strong-accent"))
      assert_operator ratio, :>=, 4.5, "selected code in a strong band (#{theme}) is #{ratio.round(2)}:1"
      ratio = contrast(resolve_colour(tokens, "--th-accent"), resolve_colour(tokens, "--th-on-accent"))
      assert_operator ratio, :>=, 4.5, "selected code on the page (#{theme}) is #{ratio.round(2)}:1"
    end
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
