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
    javascript/controllers javascript/media javascript/saving javascript/search javascript/rich_text javascript/mind_graph javascript/notes javascript/live javascript/editing
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

  test "a control is identified by a field-line edge or a fill of its own, never border-line-strong" do
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

  test "a text field is a well: the field fill and a field-line bottom edge, the accent outline on focus; a checkbox and a toggle keep a full outline" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    rule = ->(selector) { css[/(?:^|\})\s*#{Regexp.escape(selector)}\s*\{([^}]*)\}/m, 1].to_s }
    shared = css[/\n(:is\(\.admin-column, \.admin-field[^{]*\{[^}]*\})/m, 1].to_s

    # `background-color`, not the shorthand: the shorthand would wipe a select's chevron.
    assert_match(/background-color:\s*var\(--cs-field-fill\);/, shared)
    assert_match(/border-width:\s*0 0 1px;/, shared)
    assert_includes shared, "var(--cs-field-invalid-border, var(--cs-field-line))"
    assert_match(/border-radius:\s*var\(--cs-radius-field\) var\(--cs-radius-field\) 0 0;/, shared)
    assert_match(/outline:\s*2px solid var\(--cs-accent\);/, css[/:is\(\.admin-column[^{]*:focus[^{]*\{[^}]*\}/m].to_s)
    assert_match(/border-width:\s*0 0 1px;/, rule.(".cs-select"))
    assert_match(/border-bottom-color:\s*var\(--cs-field-line\);/, rule.(".cs-select"))
    assert_match(/background-color:\s*var\(--cs-field-fill\);/, rule.(".cs-select"))
    assert_match(/border:\s*1px solid var\(--cs-field-line\);/, rule.(".cs-toggle"))
    assert_match(/\.admin-prefix-input:not\(:focus-within\)\s*\{\s*border-color:\s*var\(--cs-field-line\);/, css)
    assert_no_match(/font-size:\s*10px/, css)
  end

  test "setup_input_class draws the well: the field fill and a bottom edge" do
    classes = Object.new.extend(SetupHelper).setup_input_class.split
    assert_includes classes, "bg-field-fill"
    assert_includes classes, "border-b"
    assert_includes classes, "border-0"
    assert_includes classes, "rounded-t-field"
  end

  # One type voice: a label is the sans at `text-label` (12px, weight 500), in
  # sentence case. Capitals with letterspacing is the mono-label voice that
  # this replaces. A language code (`uppercase` alone) is its own spelling and
  # is not tracked.
  UPPER_TRACKED = /(?<![\w-])uppercase(?![\w-])[^"'`]*(?<![\w-])tracking-[\w\[\].-]+|(?<![\w-])tracking-[\w\[\].-]+[^"'`]*(?<![\w-])uppercase(?![\w-])/
  UPPER_TRACKED_ALLOWED = {
    "admin-wordmark" => "the brand's wordmark, drawn as the Brand page draws it",
    "CONTENT·SPIEL" => "the product layout's wordmark",
    "Content·Spiel</span>" => "the setup layout's wordmark"
  }.freeze
  # CS Studio's sources, the setup pages and the three layouts around them.
  # The public site is the theme's and out of scope: its pages keep their look.
  TYPE_VOICE_SOURCES = (ADMIN_SOURCES - Dir[Rails.root.join("app/{views/layouts/public,components/public}/**/*")]).concat(
    Dir[Rails.root.join("app/helpers/setup_helper.rb")],
    Dir[Rails.root.join("app/views/setup/**/*.erb")],
    Dir[Rails.root.join("app/views/layouts/{product,setup,admin}.html.erb")]
  ).uniq

  test "one type voice: no capitals with tracking in the sources but the wordmark" do
    offences = TYPE_VOICE_SOURCES.flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, index|
        next if UPPER_TRACKED_ALLOWED.keys.any? { |marker| line.include?(marker) }
        "#{Pathname(path).relative_path_from(Rails.root)}:#{index + 1}" if line.match?(UPPER_TRACKED)
      end
    end
    assert_empty offences
  end

  test "the type-voice pattern matches tracked capitals in either order, and nothing else" do
    [ "uppercase tracking-mono", "tracking-wide font-bold uppercase", "font-cs-mono text-label uppercase tracking-mono",
      "uppercase tracking-[0.1em] text-meta" ].each { |sample| assert_match UPPER_TRACKED, sample }
    [ "uppercase", "tracking-tight", "text-transform: uppercase; /* note */", "uppercase\" class=\"tracking-mono",
      "font-cs-mono text-label tracking-mono" ].each { |sample| assert_no_match UPPER_TRACKED, sample }
  end

  test "every allowed tracked-capitals marker is still there" do
    UPPER_TRACKED_ALLOWED.each_key { |marker| assert TYPE_VOICE_SOURCES.any? { |path| File.read(path).include?(marker) }, marker }
  end

  test "the label is 11px for a visitor and 12px under CS Studio's surface" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.css").read.gsub(%r{/\*.*?\*/}m, "")
    assert_equal [ "11px" ], css.scan(/--cs-t-label:\s*([^;]+);/).flatten.reject { |v| v == "12px" }
    studio = css.index(/^html\[data-surface="studio"\]\s*\{[^}]*--cs-t-label:\s*12px;/m)
    assert studio, "the studio rule is `html[data-surface=\"studio\"]`: (0,1,1) beats `:root` (0,1,0)"
    roots = css.enum_for(:scan, /^:root[^{]*\{[^}]*--cs-t-label/m).map { Regexp.last_match.begin(0) }
    assert_not_empty roots
    assert roots.all? { |at| at < studio }, "the studio rule comes after every :root block that sets --cs-t-label"
    %w[admin product setup].each { |name| assert_includes Rails.root.join("app/views/layouts/#{name}.html.erb").read, '<html data-surface="studio"', name }
    %w[form_send application].each { |name| assert_not_includes Rails.root.join("app/views/layouts/#{name}.html.erb").read, 'data-surface="studio"', name }
  end

  test "the stylesheets set no label in capitals" do
    %w[content-spiel.tailwind.css admin-rich-text.css].each do |name|
      # The form-send pages are the public site's: their rules keep their look.
      css = Rails.root.join("app/assets/tailwind", name).read.gsub(%r{/\*.*?\*/}m, "").lines.grep_v(/\A\.form-send-page/).join
      assert_no_match(/text-transform:\s*uppercase/, css, name)
    end
  end

  # Mono is for code and for a value a person copies or compares exactly. Everything else (counts, times,
  # addresses, ⌘K, a field error's "!", language codes, initials, badges, the sidebar's numbers) is the sans.
  MONO_CODE = /<code|<pre|tag\.code|tag\.pre/
  MONO_ALLOWED = {
    "app/components/admin/ui/save_status_component.rb" => "the save status line stays mono capitals",
    "app/components/admin/settings_screen/ai_test_result_component.rb" => "the AI 'CONNECTED · n MS' result stays mono capitals",
    "app/components/admin/editor_screen/tile_summary_component.rb" => "the Code block's tile shows its source as the mono look",
    "app/components/admin/fields/code_field.rb" => "the Code block's source field is code",
    "app/views/setup/token.html.erb" => "the setup token's input holds a key value",
    "app/components/admin/tokens_screen/create_step_component.html.erb" => "a token's value, shown once",
    "app/components/admin/audit_screen/row_component.html.erb" => "the event's action key (`event.action`)",
    "app/components/admin/audit_screen/changes_component.html.erb" => "a changed field's key",
    "app/components/admin/audit_screen/event_header_component.html.erb" => "the event header's values (action, subject key)",
    "app/components/admin/groups_screen/permission_row_component.html.erb" => "`permission.key`",
    "app/components/admin/groups_screen/toggle_list_component.html.erb" => "`permission.key`"
  }.freeze
  MONO_SOURCES = TYPE_VOICE_SOURCES.reject { |path| path.start_with?(Rails.root.join("app/views/layouts/public").to_s) }

  test "mono is for code, a token's or key's value and the save status line only" do
    offences = MONO_SOURCES.flat_map do |path|
      relative = Pathname(path).relative_path_from(Rails.root).to_s
      next [] if MONO_ALLOWED.key?(relative)

      File.readlines(path).each_with_index.filter_map do |line, index|
        "#{relative}:#{index + 1}" if line.include?("font-cs-mono") && !line.match?(MONO_CODE)
      end
    end
    assert_empty offences
  end

  test "every mono allowance names a file that still writes mono" do
    MONO_ALLOWED.each_key do |relative|
      assert MONO_SOURCES.include?(Rails.root.join(relative).to_s), "#{relative} is not a studio source"
      assert_includes Rails.root.join(relative).read, "font-cs-mono", relative
    end
  end

  test "the stylesheets draw mono only for code, an embed and the form-send pages" do
    %w[content-spiel.tailwind.css admin-rich-text.css].each do |name|
      css = Rails.root.join("app/assets/tailwind", name).read.gsub(%r{/\*.*?\*/}m, "")
      css.to_enum(:scan, /font-family:\s*var\(--cs-mono\)/).map { Regexp.last_match.begin(0) }.each do |at|
        selector = css[0...at][/([^{}]*)\{[^{}]*\z/m, 1].to_s.strip
        ok = selector.split(",").all? { |part| part.strip.match?(/\A(?:\.admin-rich-text-content (?:pre|code)|\.admin-rich-text-embed|\.form-send-page\b.*)\z/) }
        assert ok, "#{name}: #{selector} draws mono"
      end
    end
  end

  test "the token --text-small is mapped to 13px, and --text-count is 11px for studio and visitor alike" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read
    assert_includes css, "--text-small: var(--cs-t-small);"
    assert_includes Rails.root.join("app/assets/tailwind/content-spiel.css").read, "--cs-t-small: 13px"
    assert_includes css, "--text-count: var(--cs-t-count);"
    tokens = Rails.root.join("app/assets/tailwind/content-spiel.css").read.gsub(%r{/\*.*?\*/}m, "")
    assert_equal [ "11px" ], tokens.scan(/--cs-t-count:\s*([^;]+);/).flatten
  end

  test "a count is text-count, not the 12px label" do
    %w[ui/tab_links_component.html.erb presence_screen/row_marker_component.html.erb posts_screen/toolbar_component.html.erb media_library/toolbar_component.html.erb].each do |name|
      source = Rails.root.join("app/components/admin", name).read
      assert_includes source, "text-count", name
      assert_not_includes source, "text-label", name
    end
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

  # Design System: a filter bar is 38px, set by the bar, never by a control.
  test "the filter bar's height is a token written once, and the bar sets it as a minimum, never a group height" do
    tokens = Rails.root.join("app/assets/tailwind/content-spiel.css").read
    assert_equal 1, tokens.scan("--cs-control-compact: 2.375rem;").size

    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    assert_match(/\.admin-filter-bar input:not\(\.sr-only\),.*?min-height:\s*var\(--cs-control-compact\);\s*padding-block:\s*0;/m, css)
    assert_match(/\.admin-filter-bar fieldset label\s*\{\s*min-height:\s*calc\(var\(--cs-control-compact\) - 2px\);/m, css)
    assert_no_match(/\b38px|2\.375rem/, css)

    assert_includes File.read(Rails.root.join("app/helpers/admin/filter_helper.rb")), "admin-filter-bar mb-4 flex flex-wrap items-start gap-3"
    public_css = Dir[Rails.root.join("app/assets/tailwind/themes/**/*.css")].sum("") { |f| File.read(f) }
    assert_no_match(/cs-control-compact|admin-filter-bar/, public_css, "nothing of CS Studio's reaches the public stylesheet")
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

  # E4 (Stage 1, Task 5): the buttons are tokens only. A Tailwind palette
  # step (`bg-violet-600`, `text-gray-500`), or white and black as a utility,
  # is a second source of colour that does not switch with the theme.
  PALETTE = /(?<![\w-])(?:bg|text|border|ring|outline|fill|stroke|from|via|to|divide|decoration|accent|caret|shadow|placeholder)-(?:slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose)-(?:50|[1-9]00|950)(?![\w-])|(?<![\w-])(?:bg|text|border|ring|outline|fill|stroke)-(?:white|black)(?![\w-])/

  def class_offences(pattern, allowed: {})
    TYPE_VOICE_SOURCES.flat_map do |path|
      relative = Pathname(path).relative_path_from(Rails.root).to_s
      next [] if allowed.key?(relative)

      File.readlines(path).each_with_index.filter_map do |line, index|
        "#{relative}:#{index + 1}: #{line[pattern]}" if line.match?(pattern)
      end
    end
  end

  test "no Tailwind palette colour or white/black utility in CS Studio" do
    assert_empty class_offences(PALETTE)
  end

  test "the palette pattern matches a palette step and white, and no token" do
    [ "bg-violet-600", "text-gray-500", "border-rose-950", "text-white", "hover:bg-black" ].each { |sample| assert_match PALETTE, sample }
    [ "bg-accent", "text-ink", "bg-white-ish", "text-on-accent", "bg-cat-1" ].each { |sample| assert_no_match PALETTE, sample }
  end

  ACCENT_FILL = /(?<![\w-])bg-accent(?![\w-])/
  ACCENT_FILL_ALLOWED = {
    "app/components/admin/ui/button_component.rb" => "the buttons",
    "app/components/admin/shell/sidebar_component.rb" => "the Dashboard's count pill",
    "app/components/admin/notes_screen/header_button_component.html.erb" => "the unread count pill",
    "app/components/admin/notes_screen/thread_row_component.html.erb" => "the unread bubble",
    "app/components/admin/notes_screen/inbox_row_component.html.erb" => "the unread bubble",
    "app/javascript/controllers/admin/notes/inbox_controller.js" => "the unread bubble",
    "app/javascript/mind_graph/card_notes.js" => "the unread bubble",
    "app/javascript/notes/merge.js" => "the NEW divider",
    "app/components/admin/translation_screen/translate_all_component.html.erb" => "a progress bar",
    "app/javascript/media/upload_tiles.js" => "a progress bar",
    "app/javascript/rich_text/popover.js" => "a script-built button that cannot render the component",
    "app/views/admin/posts/index.html.erb" => "the primary's own split half, New post's type chooser"
  }.freeze

  test "only a button, the checkbox, a count pill, the unread bubble and a progress bar carry the accent fill" do
    assert_empty class_offences(ACCENT_FILL, allowed: ACCENT_FILL_ALLOWED)
  end

  test "every accent-fill allowance is still used" do
    ACCENT_FILL_ALLOWED.each_key do |relative|
      assert File.read(Rails.root.join(relative)).match?(ACCENT_FILL), "#{relative} no longer carries bg-accent: drop it from ACCENT_FILL_ALLOWED"
    end
  end

  # The tinted fill with accent words is the secondary button's look; a thing
  # that is not pressable and wears it reads as a button.
  TINT_PAIR = /(?=.*(?<![\w-])bg-accent-tint(?![\w-]))(?=.*(?<![\w-])text-accent(?![\w-]))/
  TINT_PAIR_ALLOWED = {
    "app/components/admin/ui/button_component.rb" => "the secondary button",
    "app/javascript/rich_text/popover.js" => "the popover's secondary, a script-built button",
    "app/components/admin/ui/channel_chip_component.rb" => "the MCP chip, not pressable",
    "app/components/admin/notes_screen/body_component.rb" => "your own mention"
  }.freeze

  test "the tint with accent words is a secondary button's, a chip's or your own mention, and nothing else" do
    assert_empty class_offences(TINT_PAIR, allowed: TINT_PAIR_ALLOWED)
  end

  test "every tint-pair allowance is still used" do
    TINT_PAIR_ALLOWED.each_key do |relative|
      assert File.read(Rails.root.join(relative)).each_line.any? { |line| line.match?(TINT_PAIR) }, "#{relative} no longer wears the pair: drop it from TINT_PAIR_ALLOWED"
    end
  end
end
