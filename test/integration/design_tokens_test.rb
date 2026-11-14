require "test_helper"

# Backend (product UI) and frontend (public theme) CSS are two separate
# builds: each carries its own tokens and only the classes its own views use.
class DesignTokensTest < ActionDispatch::IntegrationTest
  include ContrastMeasure

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
    # `md:p-11` is only used by the setup wizard's layout.
    assert_not_includes css, "md\\:p-11"
    assert_includes stylesheet("tailwind.css"), "md\\:p-11"
  end

  # A caption is text, not a label: the sans at the small size in the faint
  # colour, sentence case as typed. Mono stays for labels (dates, the code
  # block's language), so only the figcaption rules change; the Image block's
  # caption takes the same look through utilities, hence `text-small`.
  test "a caption is text: the Code block's and a rich text's are the sans at the small size in the faint colour, as typed" do
    {
      "code.css" => /\.content-block--code figcaption\s*\{([^}]*)\}/,
      "prose.css" => /\.cs-prose figcaption\s*\{([^}]*)\}/
    }.each do |file, rule|
      css = Rails.root.join("app/assets/tailwind/themes/default", file).read
      body = css[rule, 1]
      assert body, "#{file} has the figcaption rule"
      assert_match(/font-family:\s*var\(--th-font\)/, body, file)
      assert_match(/font-size:\s*var\(--th-t-small\)/, body, file)
      assert_match(/color:\s*var\(--th-meta\)/, body, file)
      %w[text-transform letter-spacing --th-mono --th-t-label].each do |gone|
        assert_not_includes body, gone, "#{file}: a caption has no #{gone}"
      end
    end
    assert_match(/\.text-small\s*\{[^}]*var\(--th-t-small\)/m, stylesheet("theme.css"), "the theme build carries the text-small utility")
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

  # The two bands and what is written on the strong one,
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
  # tinted band is 4.71:1; the band reads it as dim, the stronger).
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
    Page.create!(title: "Home", slug: "", published_at: Time.current)
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
    colours = %w[field-fill rail popover structure structure-tint structure-ink live on-live scheduled on-scheduled
                 head-action head-action-ink head-cool head-cool-ink head-warm head-warm-ink type-chip type-chip-ink on-danger
                 tile-raised]
    (colours.map { |name| "--cs-#{name}" } + (1..4).map { |n| "--cs-shadow-#{n}" }).each do |token|
      assert_includes light, "#{token}:", "#{token} missing from the light theme"
      assert_includes dark, "#{token}:", "#{token} missing from the dark theme"
    end
    colours.each { |name| assert_includes map, "--color-#{name}: var(--cs-#{name});" }
    (1..4).each { |n| assert_includes map, "--shadow-#{n}: var(--cs-shadow-#{n});" }
    assert_not_includes map, "--shadow-menu", "the menus say shadow-3"
    %w[field button button-sm chip tile card frame rail].each do |name|
      assert_match(/--cs-radius-#{name}: \d+px;/, css, "--cs-radius-#{name} missing from the scheme-independent block")
      assert_includes map, "--radius-#{name}: var(--cs-radius-#{name});"
    end
    refute_match(/color-scheme\s*:/, css.gsub(%r{/\*.*?\*/}m, ""), "color-scheme stays per layout, never global")
  end

  # A type's stylesheet holds plain rules on tokens (the Code block's span
  # classes are built from role names, and no utility scan would find them).
  # The list is derived from the registry, so a type's stylesheet is in the
  # build because it declared it, and in it once.
  test "the public stylesheet's entry imports every registered type's stylesheet once, and the default theme's file imports none that a type declares" do
    blocks = BlockTypes.theme_css_blocks
    entry = ThemeCss.entry(ThemeFolder.new(nil), root: Rails.root, blocks: blocks)
    theme_css = Rails.root.join(ThemeCss::DEFAULT).read

    assert_equal BlockTypes.all.size, blocks.size, "one entry for each registered type, whether or not it declares a stylesheet"
    assert_not_empty blocks.filter_map(&:stylesheet), "no type declares a stylesheet: the loop below would check nothing"
    blocks.filter_map(&:stylesheet).each do |path|
      relative = path.relative_path_from(Rails.root.join(ThemeCss::ENTRY).dirname).to_s
      assert_equal 1, entry.scan(%(@import "#{relative}";)).size, "#{path.basename} is imported once by the entry"
      assert_not_includes theme_css, %(@import "./#{path.basename}";), "#{path.basename} is a type's: the entry imports it, not theme.css"
    end
  end

  test "the code block's stylesheet is declared by the type and imported by the entry, holds no colour of its own, colours each role by its token and keeps a long line inside" do
    css = Rails.root.join("app/assets/tailwind/themes/default/code.css").read

    assert_not_includes Rails.root.join(ThemeCss::DEFAULT).read, "code.css", "the Code type's stylesheet is imported by the entry, as the type declares it"
    assert_equal Rails.root.join("app/assets/tailwind/themes/default/code.css"), BlockTypes.fetch(:code).stylesheet_path
    refute_match(/#\h{3,8}\b|\brgba?\(|\bhsla?\(|\boklch\(/, css)
    CodeHighlight::ROLES.each { |role| assert_match(/\.syn-#{role}\s*\{\s*color:\s*var\(--th-syn-#{role}\);/, css) }
    assert_no_match(/\.content-block--code\s*\{[^}]*min-width/, css, "the figure is a block wherever it is drawn and needs no min-width of its own; in a column the tracks' minmax(0, …) keep the line in")
    assert_match(/\.content-block--code pre\s*\{[^}]*overflow-x:\s*auto;[^}]*white-space:\s*pre;/m, css)
    assert_match(/\.content-block--code \.code-status\s*\{[^}]*position:\s*absolute;[^}]*width:\s*1px;[^}]*height:\s*1px;[^}]*overflow:\s*hidden;[^}]*clip:\s*rect\(0 0 0 0\);[^}]*clip-path:\s*inset\(50%\);/m, css,
      "the status line is hidden from sight by the block's own rule, so a theme's template needs no scanned utility")
    assert_match(/\.content-block--code \.code-head\s*\{[^}]*color:\s*var\(--th-dim\);/m, css, "meta on the sunken ground is 4.71:1 in the light theme; the head reads as dim, the stronger")
  end

  # The code block's head and its code are each a rule on tokens.
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

    assert_no_match(/color-scheme/, css, "the page's scheme is the layout's (`scheme-light dark:scheme-dark` on <body>) and is inherited; only a strong band says another, in sections.css")

    ring = rule.(".content-block--code .code-head button:focus-visible,\n.content-block--code pre:focus-visible")
    assert_match(/outline:\s*2px solid var\(--th-accent\);/, ring)
    assert_no_match(/danger|warn/, css, "no answer of the button has a colour of its own: Not copied is as neutral as Copied")
  end

  # What is written on a strong band's accent is the band's own colour.
  # A strong band is the strongest step of its OWN scheme,
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

  # What the theme contract says of `--th-meta` (text) and `--th-line` (a
  # hairline), held for the default theme.
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

  # Where the default theme draws `--th-meta` words on `--th-sunken`: a form
  # whose block is unavailable draws its fields and its submit disabled, in
  # `--th-meta` on `--th-sunken` (`form.css`). The page's `--th-meta` on the
  # page's sunken ground was 4.06:1 in the light theme.
  test "faint text is 4.5:1 on the sunken ground, where a disabled form draws it, in both themes" do
    form = Rails.root.join("app/assets/tailwind/themes/default/form.css").read.gsub(%r{/\*.*?\*/}m, "")
    assert_match(/\.form-body:disabled[^{]*\{[^}]*color:\s*var\(--th-meta\);\s*background:\s*var\(--th-sunken\);/m, form)
    assert_match(/\.form-body:disabled \.form-submit\s*\{[^}]*color:\s*var\(--th-meta\);\s*background:\s*var\(--th-sunken\);/m, form)

    theme_tokens.each do |theme, tokens|
      ratio = contrast(resolve_colour(tokens, "--th-sunken"), resolve_colour(tokens, "--th-meta"))
      assert_operator ratio, :>=, 4.5, "faint text on the sunken ground (#{theme}) is #{ratio.round(2)}:1"
    end
  end

  # The image mark of an image with neither a width nor a preview
  # (`images.css`): a data-URI SVG cannot read a token, so each scheme has a
  # value of its own, and this holds each to `--th-meta` as `tokens.css`
  # defines it for that scheme. A theme that overrides `--th-meta` is not
  # followed (media.md says so).
  test "the empty image's mark is 28px, centred, not repeated, one <img>'s background, and drawn in --th-meta in both schemes" do
    css = Rails.root.join("app/assets/tailwind/themes/default/images.css").read.gsub(%r{/\*.*?\*/}m, "")
    base = css[/^img\[data-image-empty\]\s*\{(.*?)\}/m, 1] or flunk("images.css has no base rule for img[data-image-empty]")
    assert_match(/background-repeat:\s*no-repeat/, base)
    assert_match(/background-position:\s*center/, base)
    assert_match(/background-size:\s*28px/, base)

    theme_tokens.each do |theme, tokens|
      rule = (theme == :dark ? css[/\[data-theme="dark"\]\s+img\[data-image-empty\]\s*\{(.*?)\}/m, 1] : base) or flunk("no mark rule for #{theme}")
      uri = rule[/background-image:\s*url\("data:image\/svg\+xml,([^"]+)"\)/, 1] or flunk("no data-URI mark for #{theme}")
      svg = CGI.unescape(uri)
      colour = svg[/stroke='(#\h{6})'/, 1] or flunk("the mark has no stroke colour for #{theme}: #{svg}")
      assert_equal tokens.fetch("--th-meta").downcase, colour.downcase, "the mark is --th-meta (#{theme})"
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

  NOTE_KINDS = BlockTypes::Note::KINDS.keys.freeze

  # The Note block's public side: plain rules on tokens; each kind's
  # four tokens drawn in one place; the text, links and inline code the
  # theme's own.
  test "the note's stylesheet is declared by the type, holds no colour of its own, and draws each kind by its four tokens" do
    css = Rails.root.join("app/assets/tailwind/themes/default/note.css").read
    bare = css.gsub(%r{/\*.*?\*/}m, "")
    rule = ->(selector) { bare[/(?:^|\})\s*#{Regexp.escape(selector)}\s*\{([^}]*)\}/m, 1].to_s }

    assert_equal Rails.root.join("app/assets/tailwind/themes/default/note.css"), BlockTypes.fetch(:note).stylesheet_path
    refute_match(/#\h{3,8}\b|\brgba?\(|\bhsla?\(|\boklch\(/, bare)
    NOTE_KINDS.each do |kind|
      %w[ground line ink border].each do |part|
        assert_match(/--note-#{part}:\s*var\(--th-note-#{kind}-#{part}\);/, rule.(".content-block--note-#{kind}"), "#{kind}'s #{part}")
      end
    end
    box = rule.(".content-block--note")
    assert_match(/background:\s*var\(--note-ground\);/, box)
    assert_match(/border:\s*1px solid var\(--note-border\);/, box)
    assert_match(/border-left:\s*3px solid var\(--note-line\);/, box)
    head = rule.(".content-block--note .note-head")
    assert_match(/color:\s*var\(--note-ink\);/, head)
    assert_match(/font-size:\s*inherit;/, head, "the h3 is the body's size, whatever the theme's h3 is")
    assert_match(/clip-path:\s*inset\(50%\);/, rule.(".content-block--note .note-kind"), "the kind's word before a title is heard, not seen")
    assert_no_match(/color:/, rule.(".content-block--note .note-body"), "the text is the theme's ink, from .cs-prose")
    code = rule.(".content-block--note .note-body :not(pre) > code")
    assert_match(/background:\s*var\(--th-surface\);/, code)
    assert_match(/border:\s*1px solid var\(--th-line\);/, code)
  end

  # Each kind in its hue: Note neutral, Tip the ok green, Important the
  # accent blue, Warning the warn amber. Red is kept for errors.
  NOTE_HUES = { "note" => "--th-line-strong", "tip" => "--th-ok", "important" => "--th-accent", "warning" => "--th-warn" }.freeze

  test "the sixteen note tokens are defined from the theme's base tokens in both schemes, never a literal, each kind in its hue and none in red" do
    theme_tokens.each do |theme, tokens|
      NOTE_KINDS.each do |kind|
        %w[ground line ink border].each do |part|
          value = tokens.fetch("--th-note-#{kind}-#{part}") { flunk("--th-note-#{kind}-#{part} is not defined for #{theme}") }
          assert_match(/\A(?:var\(--th-[\w-]+\)|color-mix\(in srgb, var\(--th-[\w-]+\) \d+%, var\(--th-[\w-]+\)\))\z/, value, "#{theme} --th-note-#{kind}-#{part} is #{value}")
          assert_no_match(/danger/, value, "#{theme} --th-note-#{kind}-#{part}: red is kept for errors and destructive actions")
        end
        assert_equal "var(#{NOTE_HUES.fetch(kind)})", tokens.fetch("--th-note-#{kind}-line"), "#{theme}: the #{kind}'s rule is its hue"
      end
      assert_equal "color-mix(in srgb, var(--th-ink) 4%, var(--th-paper))", tokens.fetch("--th-note-note-ground"), "#{theme}: a Note is a 4% tint of the text colour"
    end
  end

  # The text, the link colour and the kind's
  # ink, each at 4.5:1 on the kind's ground, on the page, in a tinted band
  # and in a strong band, in both schemes. 4 kinds x 3 x 3 grounds x 2 = 72.
  # A note's ground is computed where it is declared: on the page and in a
  # tinted band it is the page's tint; a strong band re-values it to the
  # band's own ground.
  test "every note's text, link and word are readable on its ground, on the page, in a tinted band and in a strong band, in both themes" do
    pairs = 0
    theme_tokens.each do |theme, tokens|
      { "the page" => [ {}, "--th-paper" ], "a tinted band" => [ band_values("tinted"), "--th-band-tinted" ],
        "a strong band" => [ band_values("strong"), "--th-band-strong" ] }.each do |place, (inside, around)|
        outside = resolve_colour(tokens, around, inside: inside)
        NOTE_KINDS.each do |kind|
          ground = resolve_colour(tokens, "--th-note-#{kind}-ground", inside: inside, under: outside)
          [ "--th-ink", "--th-accent", "--th-note-#{kind}-ink" ].each do |token|
            ratio = contrast(ground, resolve_colour(tokens, token, inside: inside))
            assert_operator ratio, :>=, 4.5, "#{token} on the #{kind} ground in #{place} (#{theme}) is #{ratio.round(2)}:1"
            pairs += 1
          end
        end
      end
    end
    assert_equal 72, pairs
  end

  # On a strong band a note shares the band's ground and its text is the
  # band's, but each kind keeps its colour on its rule and its icon (the ink,
  # which colours the word too): Note the band's dim and text, Important the
  # band's accent, Tip and Warning their hue mixed with the band's text. The
  # band is a dark ground in both schemes, so these are light inks in both,
  # each at 3:1 or better against the band (the ink is held at 4.5:1 above, as
  # text).
  test "on a strong band a note shares the band's ground and each kind keeps its colour: its rule and its icon at 3:1 against the band in both themes; a tinted band leaves the notes alone" do
    strong = band_values("strong")
    expected = {
      "note" => %w[var(--th-on-band-strong-dim) var(--th-on-band-strong)],
      "tip" => [ "color-mix(in srgb, var(--th-ok) 60%, var(--th-on-band-strong))" ] * 2,
      "important" => %w[var(--th-on-band-strong-accent)] * 2,
      "warning" => [ "color-mix(in srgb, var(--th-warn) 60%, var(--th-on-band-strong))" ] * 2
    }
    expected.each do |kind, (line, ink)|
      assert_equal "var(--th-band-strong)", strong["--th-note-#{kind}-ground"], "#{kind}: the band's ground"
      assert_equal line, strong["--th-note-#{kind}-line"], "#{kind}'s rule"
      assert_equal ink, strong["--th-note-#{kind}-ink"], "#{kind}'s word and icon"
      assert_equal "var(--th-line)", strong["--th-note-#{kind}-border"], "#{kind}: the band's line"
    end
    assert_no_match(/danger/, strong.select { |name, _| name.start_with?("--th-note-") }.values.join(" "), "no kind is red on the band either")
    assert_empty band_values("tinted").keys.grep(/--th-note-/)

    pairs = 0
    theme_tokens.each do |theme, tokens|
      band = resolve_colour(tokens, "--th-band-strong")
      inks = NOTE_KINDS.map { |kind| resolve_colour(tokens, "--th-note-#{kind}-ink", inside: strong) }
      assert_equal 4, inks.uniq.size, "#{theme}: four kinds, four colours on the band"
      NOTE_KINDS.each do |kind|
        %w[line ink].each do |part|
          ratio = contrast(band, resolve_colour(tokens, "--th-note-#{kind}-#{part}", inside: strong))
          assert_operator ratio, :>=, 3.0, "the #{kind}'s #{part} against a strong band (#{theme}) is #{ratio.round(2)}:1"
          pairs += 1
        end
      end
    end
    assert_equal 16, pairs
  end

  CARD_TOKENS = %w[--th-card-ground --th-card-line --th-card-icon].freeze

  # The Card's ground, frame and icon are three tokens of its own; the title
  # stays --th-ink and the text --th-dim.
  test "the card's tokens are defined from the theme's base tokens in both schemes, never a literal" do
    theme_tokens.each do |theme, tokens|
      CARD_TOKENS.each do |name|
        value = tokens.fetch(name) { flunk("#{name} is not defined for #{theme}") }
        assert_match(/\A(?:var\(--th-[\w-]+\)|color-mix\(in srgb, var\(--th-[\w-]+\) \d+%, var\(--th-[\w-]+\)\))\z/, value, "#{theme} #{name} is #{value}")
      end
    end
    theme_tokens.each do |theme, tokens|
      assert_equal "var(--th-meta)", tokens.fetch("--th-card-line"), "#{theme}: the frame is the one base token that holds 3:1 (--th-line-strong is a hairline)"
    end
    assert_equal CARD_TOKENS.map { |name| name.delete_prefix("--th-") }, BlockTypes.fetch(:card).themed_tokens
    css = Rails.root.join("app/assets/tailwind/themes/default/card.css").read.gsub(%r{/\*.*?\*/}m, "")
    CARD_TOKENS.each { |name| assert_includes css, "var(#{name})", "card.css draws with #{name}" }
  end

  # The title (--th-ink) and the text (--th-dim) at 4.5:1 on the card's
  # ground, the icon at 3:1 on it and the frame at 3:1 against what the card
  # stands on, on the page, in a tinted band and in a strong band, in both
  # schemes. (2 + 1) x 3 places x 2 schemes = 18, plus 6 frames.
  test "a card's title, text, icon and frame are readable on the page, in a tinted band and in a strong band, in both themes" do
    pairs = 0
    theme_tokens.each do |theme, tokens|
      { "the page" => [ {}, "--th-paper" ], "a tinted band" => [ band_values("tinted"), "--th-band-tinted" ],
        "a strong band" => [ band_values("strong"), "--th-band-strong" ] }.each do |place, (inside, around)|
        outside = resolve_colour(tokens, around, inside: inside)
        ground = resolve_colour(tokens, "--th-card-ground", inside: inside, under: outside)
        { "--th-ink" => 4.5, "--th-dim" => 4.5, "--th-card-icon" => 3.0 }.each do |token, least|
          ratio = contrast(ground, resolve_colour(tokens, token, inside: inside, under: ground))
          puts "card #{theme} #{place} #{token}: #{ratio.round(2)}" if ENV["SHOW_RATIOS"]
          assert_operator ratio, :>=, least, "#{token} on the card ground in #{place} (#{theme}) is #{ratio.round(2)}:1"
          pairs += 1
        end
        frame = contrast(outside, resolve_colour(tokens, "--th-card-line", inside: inside, under: outside))
        puts "card #{theme} #{place} frame: #{frame.round(2)}" if ENV["SHOW_RATIOS"]
        assert_operator frame, :>=, 3.0, "the card's frame against #{place} (#{theme}) is #{frame.round(2)}:1"
        pairs += 1
      end
    end
    assert_equal 24, pairs
  end

  test "the measuring reads a colour mixed of two tokens as the two mixed" do
    tokens = { "--th-paper" => "#ffffff", "--th-ink" => "#000000",
               "--th-quarter" => "color-mix(in srgb, var(--th-ink) 25%, var(--th-paper))",
               "--th-three-quarters" => "color-mix(in srgb, var(--th-ink) 75%, var(--th-paper))" }

    # Worked by hand, not by `mix`: black at 25% over white is 0.75 in the encoded
    # values, and ((0.75 + 0.055) / 1.055)^2.4 = 0.5225 in linear light (75% is 0.25
    # encoded, 0.0508 linear). Swapped operands or an inverted share give the other.
    quarter = resolve_colour(tokens, "--th-quarter")
    three_quarters = resolve_colour(tokens, "--th-three-quarters")
    quarter.each { |channel| assert_in_delta 0.5225, channel, 0.001, "25% black over white" }
    three_quarters.each { |channel| assert_in_delta 0.0508, channel, 0.001, "75% black over white" }
    assert_operator contrast(quarter, resolve_colour(tokens, "--th-paper")), :<, contrast(three_quarters, resolve_colour(tokens, "--th-paper"))
  end

  # One token per role the highlighter names, each with
  # its dark value.
  SYNTAX_TOKENS = %w[comment keyword string constant tag attribute embed].map { |role| "--th-syn-#{role}" }.freeze

  test "the seven syntax tokens are the highlighter's seven roles, and each has a light and a dark value" do
    assert_equal CodeHighlight::ROLES.map { |role| "--th-syn-#{role}" }, SYNTAX_TOKENS
    theme_tokens.each do |theme, tokens|
      SYNTAX_TOKENS.each { |token| assert tokens.key?(token), "#{token} missing from the #{theme} theme" }
    end
  end

  # WHERE A CODE BLOCK CAN STAND, and what is then behind its text
  # (`code.css`: the `pre` and the head strip are both `--th-sunken`):
  #   - on the page: the sunken ground;
  #   - in a tinted band, which is itself the sunken ground and so puts the
  #     surface behind code (`--th-sunken: var(--th-surface)`);
  #   - in a strong band: the band's text colour at 12% over the band.
  # Each answers `inside`, what the band declares for everything in it (read
  # from `sections.css`, so a re-valued token is measured as re-valued), the
  # colour behind the code, and the colour around the block, which is what
  # the code's own focus ring is drawn on. `colour` is a token as it is THERE.
  def code_grounds(tokens)
    { "the page" => [ {}, "--th-paper" ], "a tinted band" => [ band_values("tinted"), "--th-band-tinted" ],
      "a strong band" => [ band_values("strong"), "--th-band-strong" ] }.transform_values do |inside, around|
      outside = resolve_colour(tokens, around, inside: inside)
      { inside: inside, outside: outside, ground: resolve_colour(tokens, "--th-sunken", inside: inside, under: outside),
        colour: ->(name) { resolve_colour(tokens, name, inside: inside) } }
    end
  end

  # WCAG 1.4.3 for code, all seven roles (the comment is the one that usually
  # fails): every role on every ground a code block has, in both themes. 42
  # pairs; the lowest is the comment in a dark strong band, 4.84:1.
  test "every syntax colour is readable on every ground a code block has: the page, a tinted band and a strong band, in both themes" do
    pairs = 0
    theme_tokens.each do |theme, tokens|
      code_grounds(tokens).each do |place, here|
        SYNTAX_TOKENS.each do |token|
          ratio = contrast(here[:ground], here[:colour].(token))
          assert_operator ratio, :>=, 4.5, "#{token} on #{place} (#{theme}) is #{ratio.round(2)}:1"
          pairs += 1
        end
      end
    end
    assert_equal 42, pairs
  end

  # The rest of what is written on that ground: plain code (`--th-ink`), the
  # head strip's language (`--th-dim`) and Copy's word, at rest and under the
  # pointer (the accent and its hover), each text at 4.5:1. And the two focus
  # rings, which are not text and need 3:1 (WCAG 1.4.11): Copy's is drawn
  # inside the strip, on the code's ground, and the code's own is drawn
  # outside the block, on what is around it.
  test "plain code, the head strip and Copy are readable on every ground a code block has, and both focus rings stand out, in both themes" do
    theme_tokens.each do |theme, tokens|
      code_grounds(tokens).each do |place, here|
        %w[--th-ink --th-dim --th-accent --th-accent-hover].each do |token|
          ratio = contrast(here[:ground], here[:colour].(token))
          assert_operator ratio, :>=, 4.5, "#{token} on #{place} (#{theme}) is #{ratio.round(2)}:1"
        end
        ring = here[:colour].("--th-accent")
        assert_operator contrast(here[:ground], ring), :>=, 3.0, "Copy's focus ring on #{place} (#{theme}) is #{contrast(here[:ground], ring).round(2)}:1"
        assert_operator contrast(here[:outside], ring), :>=, 3.0, "the code's focus ring on #{place} (#{theme}) is #{contrast(here[:outside], ring).round(2)}:1"
      end
    end
  end

  # On a strong band the code is one colour. The band re-values the seven to
  # its own text colour, the comment to its dim; the test above measures both
  # on the band's sunken ground. A tinted band re-values none of them.
  test "on a strong band the code is one colour: the seven are the band's text colour, the comment its dim; a tinted band leaves them alone" do
    strong = band_values("strong")
    (SYNTAX_TOKENS - %w[--th-syn-comment]).each { |token| assert_equal "var(--th-on-band-strong)", strong[token], token }
    assert_equal "var(--th-on-band-strong-dim)", strong["--th-syn-comment"]
    assert_equal "color-mix(in srgb, var(--th-on-band-strong) 12%, transparent)", strong["--th-sunken"], "the ground the two colours are measured on"
    assert_empty band_values("tinted").keys & SYNTAX_TOKENS
  end

  # The measuring itself, on values of its own: a pair that is too close
  # is seen as too close, a thinned colour is painted over what is under
  # it, and a token is measured as it is valued where the code stands. A
  # band's declaration names the band's own value of a token it declares
  # and the page's value of every other; and a token the PAGE made from
  # another (`--th-band-strong: var(--th-ink)`) was computed on the page, so
  # the band's new ink does not reach back into it.
  test "the measuring can fail: a colour too close to its ground is under 4.5, and a token is measured as the band values it" do
    tokens = { "--th-paper" => "#ffffff", "--th-sunken" => "#ecebe6", "--th-surface" => "#ffffff", "--th-ink" => "#141417", "--th-band-tinted" => "var(--th-sunken)",
               "--th-band-strong" => "var(--th-ink)", "--th-on-band-strong" => "#f5f4f0", "--th-on-band-strong-dim" => "#c9c8c2", "--th-syn-comment" => "#8a8a8a" }
    grounds = code_grounds(tokens)
    colour = ->(name) { resolve_colour(tokens, name) }

    assert_operator contrast(grounds["the page"][:ground], grounds["the page"][:colour].("--th-syn-comment")), :<, 4.5
    assert_in_delta 21.0, contrast(colour.("--th-paper"), [ 0.0, 0.0, 0.0 ]), 0.01
    assert_equal colour.("--th-surface"), grounds["a tinted band"][:ground]
    assert_equal colour.("--th-sunken"), grounds["a tinted band"][:outside], "the tinted band is the page's sunken ground, not the band's own"

    strong = grounds["a strong band"]
    assert_equal colour.("--th-ink"), strong[:outside], "the strong band is the PAGE's ink"
    assert_equal colour.("--th-on-band-strong"), strong[:colour].("--th-ink"), "and ink inside it is the band's"
    assert_equal colour.("--th-on-band-strong-dim"), strong[:colour].("--th-syn-comment"), "a comment in the band is the band's dim, not the page's comment"
    assert_equal mix(colour.("--th-on-band-strong"), colour.("--th-ink"), 0.12), strong[:ground]
    assert_operator contrast(strong[:ground], strong[:outside]), :<, 1.6, "the band's sunken ground is the band, a little lighter"
    assert_operator contrast(strong[:ground], strong[:colour].("--th-ink")), :>, 10
    assert_raises(Minitest::Assertion) { resolve_colour(tokens, "--th-sunken", inside: strong[:inside]) }
  end

  # The Tailwind 4 features the button system rests on are in the build.
  test "the product build carries the not-disabled hovers, the busy exception, the ink tint and the labels' weight" do
    css = stylesheet("tailwind.css")

    assert_match(/:not\(:disabled\)/, css)
    assert_match(/:not\(\[aria-busy=["']?true["']?\]\)/, css)
    assert_match(/\.text-label\s*\{[^}]*500/, css)
    assert_includes css, "bg-ink\\/6"
  end

  TABLE_TOKENS = %w[table-rule table-line table-head table-caption table-ground].freeze

  # The Table block's public side: five tokens from the base, in both
  # schemes, never a literal.
  test "the five table tokens are defined from the theme's base tokens in both schemes, never a literal" do
    theme_tokens.each do |theme, tokens|
      TABLE_TOKENS.each do |name|
        value = tokens.fetch("--th-#{name}") { flunk("--th-#{name} is not defined for #{theme}") }
        assert_match(/\Avar\(--th-[\w-]+\)\z/, value, "#{theme} --th-#{name} is #{value}")
      end
      assert_equal "var(--th-line-strong)", tokens.fetch("--th-table-rule")
      assert_equal "var(--th-line)", tokens.fetch("--th-table-line")
      assert_equal "var(--th-ink)", tokens.fetch("--th-table-head")
      assert_equal "var(--th-meta)", tokens.fetch("--th-table-caption")
      assert_equal "var(--th-paper)", tokens.fetch("--th-table-ground")
    end
  end

  test "the table's stylesheet is declared by the type and holds no colour of its own" do
    path = Rails.root.join("app/assets/tailwind/themes/default/table.css")
    bare = path.read.gsub(%r{/\*.*?\*/}m, "")

    assert_equal path, BlockTypes.fetch(:table).stylesheet_path
    refute_match(/#\h{3,8}\b|\brgba?\(|\bhsla?\(|\boklch\(|\bcolor-mix\(/, bare, "every colour is a token")
    assert_no_match(/Written by bin\/rails generate block_type/, path.read, "the stylesheet is the type's own now: the generator's destroy must not remove it")
    TABLE_TOKENS.each { |name| assert_includes bare, "var(--th-#{name})", "the stylesheet draws with --th-#{name}" }
  end

  # Header text, cell text and caption at 4.5:1 against the table's ground, on
  # the page, in a tinted band and in a strong band, in both schemes: 3 x 3 x 2.
  # The cell text is --th-ink, which a strong band re-values to its text.
  test "a table's header text, cell text and caption are readable on its ground, on the page, in a tinted band and in a strong band, in both themes" do
    pairs = 0
    theme_tokens.each do |theme, tokens|
      { "the page" => [ {}, "--th-paper" ], "a tinted band" => [ band_values("tinted"), "--th-band-tinted" ],
        "a strong band" => [ band_values("strong"), "--th-band-strong" ] }.each do |place, (inside, around)|
        outside = resolve_colour(tokens, around, inside: inside)
        ground = resolve_colour(tokens, "--th-table-ground", inside: inside, under: outside)
        %w[--th-table-head --th-ink --th-table-caption].each do |token|
          ratio = contrast(ground, resolve_colour(tokens, token, inside: inside))
          assert_operator ratio, :>=, 4.5, "#{token} on the table's ground in #{place} (#{theme}) is #{ratio.round(2)}:1"
          pairs += 1
        end
      end
    end
    assert_equal 18, pairs
  end

  test "a tinted band changes only the table's ground and caption; a strong band re-values all five" do
    assert_equal %w[--th-table-caption --th-table-ground], band_values("tinted").keys.grep(/--th-table-/).sort
    assert_equal "var(--th-band-tinted)", band_values("tinted")["--th-table-ground"]
    strong = band_values("strong")
    assert_equal TABLE_TOKENS.map { |name| "--th-#{name}" }.sort, strong.keys.grep(/--th-table-/).sort
    assert_equal "color-mix(in srgb, var(--th-on-band-strong) 40%, transparent)", strong["--th-table-rule"]
    assert_equal "color-mix(in srgb, var(--th-on-band-strong) 16%, transparent)", strong["--th-table-line"]
    assert_equal "var(--th-on-band-strong)", strong["--th-table-head"]
    assert_equal "var(--th-on-band-strong-dim)", strong["--th-table-caption"]
    assert_equal "var(--th-band-strong)", strong["--th-table-ground"]
  end

  FORM_TOKENS = %w[--th-form-field-ground --th-form-field-line --th-form-field-focus --th-form-error --th-form-done-ground --th-form-done-line].freeze

  # The six from the base, in both schemes; the field's outline is
  # --th-meta (3:1, the site's control outline),
  # never a hairline; the done ground is the ok hue, never the grey band.
  test "the six form tokens are defined from the theme's base tokens in both schemes, never a literal, the outline the faint text colour" do
    theme_tokens.each do |theme, tokens|
      FORM_TOKENS.each do |name|
        value = tokens.fetch(name) { flunk("#{name} is not defined for #{theme}") }
        assert_match(/\A(?:var\(--th-[\w-]+\)|color-mix\(in srgb, var\(--th-[\w-]+\) \d+%, var\(--th-[\w-]+\)\))\z/, value, "#{theme} #{name} is #{value}")
      end
      assert_equal "var(--th-meta)", tokens.fetch("--th-form-field-line"), "#{theme}: the outline is 3:1, not --th-line-strong"
      assert_equal "var(--th-surface)", tokens.fetch("--th-form-field-ground")
      assert_equal "var(--th-accent)", tokens.fetch("--th-form-field-focus")
      assert_equal "var(--th-danger-ink)", tokens.fetch("--th-form-error")
      assert_equal "var(--th-ok)", tokens.fetch("--th-form-done-line")
      assert_match(/\Acolor-mix\(in srgb, var\(--th-ok\) \d+%, var\(--th-paper\)\)\z/, tokens.fetch("--th-form-done-ground"))
    end
    assert_equal FORM_TOKENS.map { |name| name.delete_prefix("--th-") }, BlockTypes.fetch(:form).themed_tokens
  end

  test "the form's stylesheet is declared by the type, holds no colour of its own and draws with its six tokens" do
    css = Rails.root.join("app/assets/tailwind/themes/default/form.css").read
    bare = css.gsub(%r{/\*.*?\*/}m, "")

    assert_equal Rails.root.join("app/assets/tailwind/themes/default/form.css"), BlockTypes.fetch(:form).stylesheet_path
    refute_match(/#\h{3,8}\b|\brgba?\(|\bhsla?\(|\boklch\(/, bare)
    FORM_TOKENS.each { |name| assert_includes bare, "var(#{name})", "form.css draws with #{name}" }
    assert_match(/font-size:\s*1rem/, bare, "a control's text is 16px: below it a phone zooms the page on focus")
    assert_match(/\[aria-invalid="true"\]/, bare, "an invalid control is marked by the attribute the script and the server set")
    assert_no_match(/data-theme/, bare, "nothing in form.css names a scheme: the tokens follow it")
  end

  # The form's pairs: the field's text on its ground, the error, the
  # help (--th-dim), the required word (--th-meta) and the summary's links
  # (--th-accent) on what the form stands on, and the thank-you's text on
  # its ground, at 4.5:1; the outline, the focus ring and the error's edge
  # against what the form stands on, and the thank-you's rule against its
  # ground, at 3:1. On the page, a tinted band and a strong band, in both
  # schemes: (6 + 4) x 3 x 2 = 60.
  test "a form's field text, line, focus ring, error and thank-you are readable on the page, a tinted band and a strong band, in both themes" do
    pairs = 0
    theme_tokens.each do |theme, tokens|
      { "the page" => [ {}, "--th-paper" ], "a tinted band" => [ band_values("tinted"), "--th-band-tinted" ],
        "a strong band" => [ band_values("strong"), "--th-band-strong" ] }.each do |place, (inside, around)|
        outside = resolve_colour(tokens, around, inside: inside)
        field = resolve_colour(tokens, "--th-form-field-ground", inside: inside, under: outside)
        done = resolve_colour(tokens, "--th-form-done-ground", inside: inside, under: outside)
        texts = { "--th-ink on the field" => [ "--th-ink", field ], "--th-form-error" => [ "--th-form-error", outside ],
                  "--th-dim (help)" => [ "--th-dim", outside ], "--th-meta (required)" => [ "--th-meta", outside ],
                  "--th-accent (a summary's link)" => [ "--th-accent", outside ], "--th-ink on the thank-you" => [ "--th-ink", done ] }
        lines = { "--th-form-field-line" => [ "--th-form-field-line", outside ], "--th-form-field-focus" => [ "--th-form-field-focus", outside ],
                  "--th-form-error (the edge)" => [ "--th-form-error", outside ], "--th-form-done-line" => [ "--th-form-done-line", done ] }
        [ [ texts, 4.5 ], [ lines, 3.0 ] ].each do |set, least|
          set.each do |what, (token, ground)|
            ratio = contrast(ground, resolve_colour(tokens, token, inside: inside, under: ground))
            puts "form #{theme} #{place} #{what}: #{ratio.round(2)}" if ENV["SHOW_RATIOS"]
            assert_operator ratio, :>=, least, "#{what} in #{place} (#{theme}) is #{ratio.round(2)}:1"
            pairs += 1
          end
        end
      end
    end
    assert_equal 60, pairs
  end

  # A strong band re-values all six, as the Note's and the
  # Card's (a token is computed where it is declared, so the page's light
  # field ground would stay under the band's light text), and the block is
  # drawn for a dark ground in both schemes; a tinted band leaves them alone.
  test "a strong band re-values the six form tokens and draws the form's controls for a dark ground; a tinted band leaves them alone" do
    strong = band_values("strong")

    assert_equal FORM_TOKENS.sort, strong.keys.grep(/--th-form-/).sort
    assert_equal "color-mix(in srgb, var(--th-on-band-strong) 6%, var(--th-band-strong))", strong["--th-form-field-ground"]
    assert_equal "var(--th-on-band-strong-dim)", strong["--th-form-field-line"]
    assert_equal "var(--th-on-band-strong-accent)", strong["--th-form-field-focus"]
    assert_match(/\Acolor-mix\(in srgb, var\(--th-danger\) \d+%, var\(--th-on-band-strong\)\)\z/, strong["--th-form-error"])
    assert_equal "var(--th-band-strong)", strong["--th-form-done-ground"]
    assert_match(/\Acolor-mix\(in srgb, var\(--th-ok\) \d+%, var\(--th-on-band-strong\)\)\z/, strong["--th-form-done-line"])
    assert_empty band_values("tinted").keys.grep(/--th-form-/)
    sections = Rails.root.join("app/assets/tailwind/themes/default/sections.css").read
    assert_match(/\.content-section--strong \.content-block--form \{ color-scheme: dark; \}/, sections)
  end

  DIAGRAM_TOKENS = %w[ink fill line edge group note accent series-1 series-2 series-3 series-4 series-5 series-6].map { |name| "--th-diagram-#{name}" }.freeze
  DIAGRAM_SERIES = DIAGRAM_TOKENS.grep(/series/).freeze
  DIAGRAM_CSS = Rails.root.join("app/assets/tailwind/themes/default/diagram.css")

  # The Diagram block's tokens (Diagram block spec §4): every one from the
  # base but the six series colours, which are literals as the syntax colours
  # are; the font fixed. A strong band re-values all thirteen, as it does the
  # Code block's; a tinted band only the group's ground, which would be the
  # band itself.
  test "every diagram token is defined in both schemes and re-valued on the strong band" do
    assert_equal DIAGRAM_TOKENS.map { |name| name.delete_prefix("--th-") }, BlockTypes.fetch(:diagram).themed_tokens
    assert_equal %w[diagram-font], BlockTypes.fetch(:diagram).fixed_tokens
    theme_tokens.each do |theme, tokens|
      DIAGRAM_TOKENS.each do |name|
        value = tokens.fetch(name) { flunk("#{name} is not defined for #{theme}") }
        shape = DIAGRAM_SERIES.include?(name) ? /\A#\h{6}\z/ : /\A(?:var\(--th-[\w-]+\)|color-mix\(in srgb, var\(--th-[\w-]+\) \d+%, var\(--th-[\w-]+\)\))\z/
        assert_match shape, value, "#{theme} #{name} is #{value}"
      end
      { "--th-diagram-ink" => "var(--th-ink)", "--th-diagram-fill" => "var(--th-surface)", "--th-diagram-line" => "var(--th-dim)",
        "--th-diagram-edge" => "var(--th-dim)", "--th-diagram-group" => "var(--th-sunken)", "--th-diagram-accent" => "var(--th-accent)" }.each do |name, value|
        assert_equal value, tokens.fetch(name), "#{theme} #{name}"
      end
      assert_match(/\Acolor-mix\(in srgb, var\(--th-accent-tint\) \d+%, var\(--th-surface\)\)\z/, tokens.fetch("--th-diagram-note"))
    end
    fixed = Rails.root.join("app/assets/tailwind/themes/default/tokens.css").read[/^:root \{(.*?)\}/m, 1]
    assert_match(/--th-diagram-font:\s*"Archivo"/, fixed, "the face the boxes were measured in")
    assert_equal DIAGRAM_TOKENS.sort, band_values("strong").keys.grep(/--th-diagram-/).sort
    assert_equal %w[--th-diagram-group], band_values("tinted").keys.grep(/--th-diagram-/)
  end

  # WCAG 1.4.3 and 1.4.11 for what a diagram draws: its labels (ink) on
  # every shape they stand on, the node's fill, a group's ground, a note and
  # each series colour, at 4.5:1; its lines (a node's outline, an edge, the
  # accent's activation, critical task and today line) at 3:1 on the ground
  # the drawing stands on and on a group's. On the page, a tinted band and a
  # strong band, in both schemes: (9 + 6) x 3 x 2 = 90.
  test "ink on fill, group and note is 4.5:1; edge and line on every ground are 3:1; ink on each series colour is 4.5:1, in both schemes, on the page, a tinted and a strong band" do
    pairs = 0
    theme_tokens.each do |theme, tokens|
      { "the page" => [ {}, "--th-paper" ], "a tinted band" => [ band_values("tinted"), "--th-band-tinted" ],
        "a strong band" => [ band_values("strong"), "--th-band-strong" ] }.each do |place, (inside, around)|
        outside = resolve_colour(tokens, around, inside: inside)
        ground = ->(name) { resolve_colour(tokens, name, inside: inside, under: outside) }
        ink = resolve_colour(tokens, "--th-diagram-ink", inside: inside)
        (%w[--th-diagram-fill --th-diagram-group --th-diagram-note] + DIAGRAM_SERIES).each do |shape|
          ratio = contrast(ground.(shape), ink)
          puts "diagram #{theme} #{place} ink on #{shape}: #{ratio.round(2)}" if ENV["SHOW_RATIOS"]
          assert_operator ratio, :>=, 4.5, "--th-diagram-ink on #{shape} in #{place} (#{theme}) is #{ratio.round(2)}:1"
          pairs += 1
        end
        { "the ground" => outside, "a group" => ground.("--th-diagram-group") }.each do |under, colour|
          %w[--th-diagram-line --th-diagram-edge --th-diagram-accent].each do |stroke|
            ratio = contrast(colour, resolve_colour(tokens, stroke, inside: inside, under: colour))
            puts "diagram #{theme} #{place} #{stroke} on #{under}: #{ratio.round(2)}" if ENV["SHOW_RATIOS"]
            assert_operator ratio, :>=, 3.0, "#{stroke} on #{under} in #{place} (#{theme}) is #{ratio.round(2)}:1"
            pairs += 1
          end
        end
      end
    end
    assert_equal 90, pairs
  end

  # The stylesheet paints what Mermaid's dropped <style> painted, by the
  # class names Mermaid writes, and carries the layout that <style> held
  # (Diagram block spec §4): it is plain CSS, since the renderer frame
  # inlines the same file.
  test "diagram.css paints by class, holds no colour literal and scopes text-anchor middle to svg.flowchart" do
    assert_equal DIAGRAM_CSS, BlockTypes.fetch(:diagram).stylesheet_path
    text = DIAGRAM_CSS.read
    css = text.gsub(%r{/\*.*?\*/}m, "")
    assert_no_match(/Written by bin\/rails generate block_type/, text, "the stylesheet is the type's own")
    refute_match(/#\h{3,8}\b|\brgba?\(|\bhsla?\(|\boklch\(|\bcolor-mix\(/, css, "every colour is a token")
    assert_no_match(/@apply|@theme|@utility|@import|theme\(|--color-/, css, "plain CSS: no Tailwind, so the frame can inline it")
    assert_no_match(/data-theme/, css, "nothing names a scheme: the tokens follow it")
    (DIAGRAM_TOKENS + %w[--th-diagram-font]).each { |name| assert_includes css, "var(#{name})", "diagram.css paints with #{name}" }

    rules = css.scan(/([^{}]+)\{([^{}]*)\}/).map { |selectors, body| [ selectors.split(",").map(&:strip), body ] }
    middle = rules.select { |_, body| body.match?(/text-anchor:\s*middle/) }
    assert middle.flat_map(&:first).any? { |selector| selector.match?(/svg\.flowchart .*\.node .*\.label .*text/) }, "a flowchart's node labels are centred"
    middle.flat_map(&:first).each do |selector|
      assert_match(/svg\.flowchart |TitleText|\.titleText|\.slice|\.taskText\b|\.vertText|text\.actor|aria-roledescription/, selector, "#{selector}: text-anchor middle on a type's own class only (class, state and ER labels start where they are written)")
    end

    %w[edge-pattern-dashed edge-pattern-dotted edge-thickness-thick messageLine1 loopLine note-edge actor-line activation0 relationshipLine
       row-rect-odd row-rect-even edgeTerminals statediagram-cluster statediagram-note state-start relation transition cluster pieOuterCircle
       today grid].each do |name|
      assert_match(/\.#{Regexp.escape(name)}\b/, css, "diagram.css paints .#{name}")
    end
    (1..6).each do |k|
      assert_match(/\.pieCircle:nth-of-type\(6n\+#{k}\)\s*\{\s*fill:\s*var\(--th-diagram-series-#{k}\)/, css, "slice #{k}")
      assert_match(/\.legend:nth-of-type\(6n\+#{(k % 6) + 1}\) rect\s*\{\s*fill:\s*var\(--th-diagram-series-#{k}\)/, css, "legend #{k}")
    end
    %w[done active crit].product((0..3).to_a).each { |state, section| assert_includes css, ".#{state}#{section}", "the gantt's #{state} task in section #{section}" }
    { "16px" => "the root", "18px" => "titles", "17px" => "pie labels and legend", "25px" => "the pie's title", "14px" => "ER edge labels", "11px" => "class terminals and gantt task text" }.each do |size, what|
      assert_match(/font-size:\s*#{size}/, css, "#{what} at #{size}")
    end
    assert_match(/stroke-dasharray/, css, "the dash patterns")
    assert_match(/max-width:\s*100%/, css)
    assert_match(/height:\s*auto/, css)
    assert_match(/min-width:\s*var\(--diagram-min-width/, css, "the smallest width the component writes")
    assert_match(/overflow-x:\s*auto/, css)
    assert_match(/overscroll-behavior-x:\s*contain/, css)
  end

  private
    def helpers = ActionController::Base.helpers

    # `tokens.css`'s two colour blocks as { "--th-name" => "value" }.
    def theme_tokens
      css = Rails.root.join("app/assets/tailwind/themes/default/tokens.css").read
      { light: css[/:root, \[data-theme="light"\]\s*\{(.*?)\}/m, 1], dark: css[/\[data-theme="dark"\]\s*\{(.*?)\}/m, 1] }
        .transform_values { |block| block.scan(/(--th-[\w-]+):\s*([^;]+);/).to_h }
    end

    # The custom properties a band gives what is inside it
    # (`sections.css`, `.content-section--<name> { … }`), as written.
    def band_values(name)
      css = Rails.root.join("app/assets/tailwind/themes/default/sections.css").read.gsub(%r{/\*.*?\*/}m, "")
      rule = css[/^\.content-section--#{name}\s*\{(.*?)\}/m, 1] or flunk("sections.css has no rule for the #{name} band")
      rule.scan(/(--th-[\w-]+):\s*([^;]+);/).to_h
    end

    def stylesheet(name)
      get helpers.asset_path(name)
      assert_response :success
      response.body
    end
end
