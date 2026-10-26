require "test_helper"

# Design pass spec §3: tokens only, red only for destruction and failure,
# and none of the components the shared parts replaced. These rules are easy to
# break one innocent edit at a time, so they are pinned here.
class AdminDesignRulesTest < ActiveSupport::TestCase
  # Everything that draws CS Studio, or is drawn inside it: its views and
  # components, the media components it shares with the public site
  # (`components/media`: the picker and the picture tag), the public site's own
  # components (`components/public`: the preview bar, whose two colours are
  # theme tokens too), and every script -- the Stimulus controllers and the
  # modules beside them (`media/`, `saving/`, `search/`, `rich_text/`,
  # `mind_graph/`), which build markup and set classes as well. The mind
  # graph's draw onto a canvas, where a colour is a string handed to the
  # context: its modules read every one from the tokens (`mind_graph/theme.js`).
  SOURCE_DIRECTORIES = %w[
    views/admin views/layouts views/setup components/admin components/media components/public
    javascript/controllers javascript/media javascript/saving javascript/search javascript/rich_text javascript/mind_graph javascript/notes
  ].freeze
  ADMIN_SOURCES = Dir[Rails.root.join("app/{#{SOURCE_DIRECTORIES.join(",")}}/**/*.{erb,rb,js}")]

  # A raw colour literal, in any of the spellings CSS has for one:
  # - hex with 3, 4, 6 or 8 digits. The lookbehind is what keeps the things
  #   that merely look like one out: a Stimulus action (`admin--ui--menu#add`), a
  #   Ruby interpolation (`"##{id}"`), an HTML character reference (`&#8203;`)
  #   and a URL fragment (`/path#fade`) all have a word character, `#`, `&` or
  #   `/` in front of the `#`. An id selector that happens to spell hex
  #   digits (`"#feed"`) would still be flagged -- rename the id.
  # - `rgb(` / `rgba(` / `hsl(` / `hsla(`.
  RAW_COLOUR = /(?<![\w#&\/-])#(?:\h{8}|\h{6}|\h{3,4})(?![\w-])|\b(?:rgb|hsl)a?\(/

  # Any `dark:` variant -- `dark:bg-…`, an arbitrary `dark:[…]`, a stacked
  # `dark:hover:bg-…` or `hover:dark:bg-…` -- except `dark:scheme-dark`, the
  # one place the theme is handed to the browser's own controls. Tokens
  # already switch with the theme, so a `dark:` class is always a second,
  # diverging source of colour. A variant is followed by a utility; prose
  # about the rule ("no `dark:` variants") is not.
  DARK_VARIANT = /(?<![\w-])dark:(?!scheme-dark(?![\w-]))[a-z\[!-]/

  # The one file allowed a `dark:` variant: the public site's footer toggle
  # swaps its two labels with `dark:hidden` / `dark:inline`. That is which
  # *text* shows, not a colour, and it belongs to the public theme (it only
  # sits under `views/layouts`), so there is no token to replace it with.
  DARK_VARIANT_EXEMPT = %w[app/views/layouts/public/_theme_toggle.html.erb].freeze

  def design_offences(pattern, except: [])
    (ADMIN_SOURCES - except.map { |path| Rails.root.join(path).to_s }).flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, index|
        "#{Pathname(path).relative_path_from(Rails.root)}:#{index + 1}: #{line[pattern]}" if line.match?(pattern)
      end
    end
  end

  # A directory that is renamed or emptied would otherwise drop out of every
  # rule below without a word.
  test "every directory the rules cover is there and has sources" do
    SOURCE_DIRECTORIES.each do |directory|
      root = Rails.root.join("app", directory).to_s
      assert ADMIN_SOURCES.any? { |path| path.start_with?("#{root}/") }, "app/#{directory} has no .erb, .rb or .js file: the design rules no longer look at it"
    end
  end

  test "no raw colour literals in CS Studio" do
    assert_empty design_offences(RAW_COLOUR)
  end

  test "no dark: variants in CS Studio except dark:scheme-dark" do
    assert_empty design_offences(DARK_VARIANT, except: DARK_VARIANT_EXEMPT)
    DARK_VARIANT_EXEMPT.each do |path|
      assert_equal %w[dark:hidden dark:inline], Rails.root.join(path).read.scan(/dark:[\w-]+/), "#{path} is exempt for its label swap only"
    end
  end

  # The guard is only worth having if its patterns catch what they claim to
  # and nothing else, so both are pinned against examples.
  test "the guard patterns match colours and dark: variants, and nothing that only looks like one" do
    [ "color: #fff", "fill='#1a2b3c'", "stroke: #1a2b3c80;", "bg-[#abcd]", "background: rgb(0 0 0 / 50%)", "rgba(0,0,0,.5)",
      "hsl(210 50% 40%)", "hsla(210, 50%, 40%, .5)" ].each do |sample|
      assert_match RAW_COLOUR, sample
    end
    [ 'find("#toasts")', "#content", 'action: "admin--ui--menu#add"', "admin--pages--tree#face", '"##{dom_id}"', "&#8203;", "&#x200b;",
      "/cs-studio/pages#add", "#fade-in", "issue #12345", "#abcde" ].each do |sample|
      assert_no_match RAW_COLOUR, sample
    end

    [ "dark:bg-ink", "dark:text-paper", "dark:hover:bg-sunken", "hover:dark:bg-sunken", "dark:[color:red]", "dark:shadow-menu",
      "dark:!bg-ink", "dark:-mt-1", "scheme-light dark:scheme-dark dark:border-line" ].each do |sample|
      assert_match DARK_VARIANT, sample
    end
    [ "scheme-light dark:scheme-dark", "no `dark:` colour variant", '{ dark: "x" }', "data-dark:bg" ].each do |sample|
      assert_no_match DARK_VARIANT, sample
    end
  end

  # Every place a translation STATE is drawn: red is for destruction and
  # failure, never for "missing" or "outdated" (final review C, M13).
  test "translation chips, language tabs, tree markers, the matrix and the summary and dashboard cards never use the danger colour" do
    %w[
      app/components/admin/ui/translation_chip_component.rb app/components/admin/ui/language_tabs_component.html.erb
      app/components/admin/pages_screen/tree_node_component.html.erb app/components/admin/pages_screen/tree_node_component.rb
      app/components/admin/translation_screen/matrix_component.html.erb app/components/admin/translation_screen/matrix_component.rb
      app/components/admin/translation_screen/summary_card_component.html.erb app/components/admin/translation_screen/summary_card_component.rb
      app/components/admin/dashboard_screen/translation_card_component.html.erb app/components/admin/dashboard_screen/translation_card_component.rb
    ].each do |path|
      assert_no_match(/danger/, Rails.root.join(path).read, path)
    end
  end

  # One placeholder for a record with no title, everywhere: "(untitled)".
  test "a blank title reads (untitled), never Untitled" do
    offenders = Dir[Rails.root.join("app/**/*.{rb,erb,js}")].select { |f| File.read(f).match?(/["']Untitled["']/) }
    assert_empty offenders.map { |f| Pathname(f).relative_path_from(Rails.root).to_s }
  end

  test "the replaced components are gone" do
    %w[
      status_badge_component.rb language_switcher_component.rb flash_component.rb translation_screen/state_badge_component.rb
      record_header_component.rb tag_input_component.rb translation_screen/list_component.rb
      translation_screen/outdated_note_component.rb dashboard_screen/column_component.rb audit_changes_component.rb
      audit_changes_component.html.erb settings_form_component.rb settings_form_component.html.erb
      media_library/detail_component.rb media_library/detail_component.html.erb
      columns/image_column_component.rb columns/image_column_component.html.erb
    ].each do |file|
      assert_not Rails.root.join("app/components/admin", file).exist?, file
    end
    assert_not Rails.root.join("app/views/shared/_theme_toggle.html.erb").exist?
    # Round 3: Languages is a card of the Settings screen, an image's detail a
    # panel beside the Media grid, and the audit log words its rows through
    # `Audit::Sentence` -- the screens and helper they replaced stay deleted.
    %w[
      app/views/admin/languages/index.html.erb app/views/admin/media/show.html.erb
      app/views/admin/shared/_image_upload_field.html.erb app/views/admin/api_tokens/_connection.html.erb
      app/views/admin/users/_access_fields.html.erb app/helpers/admin/audit_events_helper.rb
    ].each do |file|
      assert_not Rails.root.join(file).exist?, file
    end
    # The translation states live in `translation_states` (`Translations::StateIndex`) now.
    assert_not Rails.root.join("app/models/translations/cached_status.rb").exist?
  end

  test "the outlined danger button variant is gone" do
    offenders = Dir[Rails.root.join("app/**/*")].select { |f| File.file?(f) && File.read(f).include?("danger_outline") }
    assert_empty offenders.map { |f| Pathname(f).relative_path_from(Rails.root).to_s }
  end

  # Inside the shell a form starts at the left edge of the content area, next
  # to the sidebar and under the page heading; only a screen that IS the form
  # (sign-in, setup, a dialog) is centred. The 403 and 404 messages are the
  # two centred things inside the shell, and they are messages, not forms.
  test "nothing inside CS Studio is centred except the 403 and 404 messages" do
    centred = Dir[Rails.root.join("app/views/admin/**/*.erb"), Rails.root.join("app/components/{admin,media}/**/*.{erb,rb}")]
      .select { |f| File.read(f).match?(/\bmx-auto\b/) }
      .map { |f| Pathname(f).relative_path_from(Rails.root).to_s }
    assert_equal %w[app/views/admin/errors/forbidden.html.erb app/views/admin/errors/not_found.html.erb], centred.sort
  end

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

  # Design answer, first reply: "▾PAGE SETTINGS" had no space. A mono-label
  # summary draws its own triangle, 6px from the words, that a screen reader skips.
  test "a disclosure's triangle is the stylesheet's, apart from its words, turned when open" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    assert_match(/\.admin-disclosure\s*\{[^}]*list-style:\s*none;[^}]*gap:\s*0\.375rem;/m, css)
    assert_match(/\.admin-disclosure::before\s*\{[^}]*content:\s*"▸"\s*\/\s*"";/m, css)
    assert_match(/details\[open\]\s*>\s*\.admin-disclosure::before\s*\{[^}]*rotate\(90deg\)/m, css)
    # The reference card folds only when stacked; side by side its summary is inert, and shows no triangle.
    assert_match(/\.admin-translation-pair > \.admin-reference-card > details > summary::before\s*\{\s*display:\s*none;/, css)
    %w[app/components/admin/editor_screen/page_settings_form_component.html.erb app/components/admin/editor_screen/shared_fields_component.html.erb
       app/components/admin/editor_screen/reference_card_component.html.erb app/views/admin/audit_events/show.html.erb].each do |path|
      Rails.root.join(path).read.scan(/<summary[^>]*>/).each { |summary| assert_includes summary, "admin-disclosure", path }
    end
  end

  # Layout points spec, decision 1: one cap, one place.
  test "the form column's width is a token: 760px and 1144px are written once, in content-spiel.css" do
    tokens = Rails.root.join("app/assets/tailwind/content-spiel.css").read
    assert_equal 1, tokens.scan("--cs-form-max: 760px;").size
    assert_equal 1, tokens.scan("--cs-form-max-pair: 1144px;").size

    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    assert_match(/\.admin-form-column\s*\{\s*max-width:\s*var\(--cs-form-max\);\s*\}/, css)
    assert_match(/\.admin-form-column--pair\s*\{\s*max-width:\s*var\(--cs-form-max-pair\);\s*\}/, css)
    assert_match(/@container \(min-width: 824px\)\s*\{\s*\.admin-translation-pair\s*\{\s*grid-template-columns:\s*repeat\(2, minmax\(0, 560px\)\);/m, css)
    assert_no_match(/\b(?:760|1144)px/, css)
    assert_empty design_offences(/\[(?:760|1144)px\]|max-width:\s*(?:760|1144)px/)
  end

  # Layout points spec, decision 13: at most three cards in a row, by the
  # dashboard's own width, never `auto-fit`.
  test "the dashboard's grid is one, two or three columns by its container, and never auto-fit" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    assert_match(/\.admin-dashboard\s*\{\s*container:\s*admin-dashboard\s*\/\s*inline-size;\s*\}/, css)
    assert_match(/@container admin-dashboard \(min-width: 40rem\)\s*\{\s*\.admin-dashboard-cards\s*\{\s*grid-template-columns:\s*repeat\(2, minmax\(0, 1fr\)\);/m, css)
    assert_match(/@container admin-dashboard \(min-width: 60rem\)\s*\{\s*\.admin-dashboard-cards\s*\{\s*grid-template-columns:\s*repeat\(3, minmax\(0, 1fr\)\);/m, css)
    assert_no_match(/auto-fit/, Rails.root.join("app/views/admin/dashboard/show.html.erb").read)
  end
end
