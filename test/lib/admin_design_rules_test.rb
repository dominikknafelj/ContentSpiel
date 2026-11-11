require "test_helper"

# CS Studio's design rules: tokens only, red only for destruction and failure,
# and none of the components the shared parts replaced. These rules are easy to
# break one innocent edit at a time, so they are pinned here.
class AdminDesignRulesTest < ActiveSupport::TestCase
  # Everything that draws CS Studio, or is drawn inside it: its views (the
  # invitation page `views/invitations`, a product-layout page, among them) and
  # components, the media components it shares with the public site
  # (`components/media`: the picture tag), the public site's own
  # components (`components/public`: the preview bar, whose two colours are
  # theme tokens too), and every script -- the Stimulus controllers and the
  # modules beside them (`media/`, `saving/`, `search/`, `rich_text/`,
  # `mind_graph/`), which build markup and set classes as well. The mind
  # graph's draw onto a canvas, where a colour is a string handed to the
  # context: its modules read every one from the tokens (`mind_graph/theme.js`).
  SOURCE_DIRECTORIES = %w[
    views/admin views/layouts views/setup views/invitations components/admin components/media components/public
    javascript/controllers javascript/media javascript/saving javascript/search javascript/rich_text javascript/mind_graph javascript/notes javascript/live javascript/editing javascript/ui
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

  # The mails: the mailer layout, the button and every mailer's views
  # (`app/views/*_mailer`, so a new mailer's are read too). A mail has no
  # tokens and a client reads no stylesheet, so its colours are named CSS
  # colours written inline, with one exception: the button's violet,
  # `MAIL_ACCENT`, which is `--cs-accent`'s light value (a mail has no dark
  # scheme). The exception admits that spelling and no other, in a mail
  # source alone.
  MAIL_SOURCES = (Dir[Rails.root.join("app/views/layouts/mailer.*")] + Dir[Rails.root.join("app/views/{mails,*_mailer}")].select { |path| File.directory?(path) })
    .map { |path| Pathname(path).relative_path_from(Rails.root).to_s }.sort.freeze
  MAIL_ACCENT = "#6236d9".freeze
  # The violet as a whole literal: `#6236d9ff` is another colour, and stays caught.
  MAIL_ACCENT_LITERAL = /#{MAIL_ACCENT}(?!\h)/
  MAIL_FILES = MAIL_SOURCES.flat_map do |source|
    path = Rails.root.join(source)
    path.file? ? [ path.to_s ] : Dir[path.join("**/*.erb")]
  end.freeze

  # A line's raw colour literals, after a mail source's one admitted value
  # is taken out of it.
  def raw_colours(line, mail:)
    line = line.gsub(MAIL_ACCENT_LITERAL, "") if mail
    line.scan(RAW_COLOUR)
  end

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
  test "the visitor's two layouts are there, and out of the type-voice and elevation scans" do
    VISITOR_LAYOUTS.each do |path|
      assert File.exist?(path), path
      assert_not_includes TYPE_VOICE_SOURCES, path
      assert_not_includes ELEVATION_SOURCES, path
    end
  end

  test "every directory the rules cover is there and has sources" do
    SOURCE_DIRECTORIES.each do |directory|
      root = Rails.root.join("app", directory).to_s
      assert ADMIN_SOURCES.any? { |path| path.start_with?("#{root}/") }, "app/#{directory} has no .erb, .rb or .js file: the design rules look at nothing there"
    end
    mailers = Dir[Rails.root.join("app/mailers/*_mailer.rb")].map { |path| File.basename(path, ".rb") } - %w[application_mailer]
    mailers.each { |mailer| assert_includes MAIL_SOURCES, "app/views/#{mailer}", "#{mailer}'s views are read by the colour rule" }
    assert_includes MAIL_SOURCES, "app/views/mails"
    assert_includes MAIL_SOURCES, "app/views/layouts/mailer.html.erb"
    MAIL_SOURCES.each do |source|
      root = Rails.root.join(source).to_s
      assert MAIL_FILES.any? { |path| path == root || path.start_with?("#{root}/") }, "#{source} has no .erb file: the colour rule looks at nothing there"
    end
  end

  test "no colour literal in CS Studio's sources or a mail's, but the mail's violet" do
    offences = (ADMIN_SOURCES | MAIL_FILES).flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, index|
        found = raw_colours(line, mail: MAIL_FILES.include?(path))
        "#{Pathname(path).relative_path_from(Rails.root)}:#{index + 1}: #{found.join(" ")}" if found.any?
      end
    end
    assert_empty offences

    assert_empty raw_colours("background:#{MAIL_ACCENT};", mail: true), "the violet is admitted in a mail source"
    assert_equal [ MAIL_ACCENT ], raw_colours("background:#{MAIL_ACCENT};", mail: false), "and refused in CS Studio's"
    [ "background:#6236DA;", "color:#000;", "background:#6236d9ff;" ].each do |sample|
      assert_not_empty raw_colours(sample, mail: true), "#{sample} is refused in a mail source"
    end
  end

  test "a mail's one colour literal is the accent's violet, on the button alone" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.css").read.gsub(%r{/\*.*?\*/}m, "")
    light = css[/:root, \[data-theme="light"\]\s*\{(.*?)\}/m, 1]
    assert_equal MAIL_ACCENT, light[/--cs-accent:\s*([^;]+);/, 1].strip, "the mail's violet is --cs-accent's light value"

    holders = (ADMIN_SOURCES | MAIL_FILES).select { |path| File.read(path).include?(MAIL_ACCENT) }
    assert_equal [ "app/views/mails/_button.html.erb" ], holders.map { |path| Pathname(path).relative_path_from(Rails.root).to_s }
    assert_equal 1, Rails.root.join("app/views/mails/_button.html.erb").read.scan(MAIL_ACCENT).size, "once, on the button's link"
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
  # failure, never for "missing" or "outdated".
  test "translation chips, language tabs, tree markers, the matrix and the summary and dashboard cards never use the danger colour" do
    %w[
      app/components/admin/ui/translation_chip_component.rb app/components/admin/ui/language_tabs_component.html.erb
      app/components/admin/pages_screen/tree_row_component.html.erb app/components/admin/pages_screen/tree_row_component.rb
      app/components/admin/translation_screen/matrix_component.html.erb app/components/admin/translation_screen/matrix_component.rb
      app/components/admin/translation_screen/summary_card_component.html.erb app/components/admin/translation_screen/summary_card_component.rb
      app/components/admin/dashboard_screen/translation_panel_component.html.erb app/components/admin/dashboard_screen/translation_panel_component.rb
      app/components/admin/ui/language_progress_component.html.erb app/components/admin/ui/language_progress_component.rb
    ].each do |path|
      assert_no_match(/danger/, Rails.root.join(path).read, path)
    end
  end

  # SortableJS is `preload: false` and every user of it imports it inside the
  # function that makes its Sortables, so a screen with nothing to drag never
  # fetches it. A static import is fetched at the controller's registration.
  STATIC_SORTABLE_IMPORT = /^\s*import\b[^;]*?\bfrom\s*["']sortablejs["']|^\s*import\s+["']sortablejs["']/

  test "no script imports SortableJS statically: it is loaded on demand" do
    offenders = Dir[Rails.root.join("app/javascript/**/*.js")].select { |path| File.read(path).match?(STATIC_SORTABLE_IMPORT) }

    assert_empty offenders.map { |path| Pathname(path).relative_path_from(Rails.root).to_s }
  end

  test "the static SortableJS import pattern matches the static form and not import()" do
    assert_match STATIC_SORTABLE_IMPORT, %(import Sortable from "sortablejs")
    assert_match STATIC_SORTABLE_IMPORT, %(  import Sortable from 'sortablejs')
    assert_match STATIC_SORTABLE_IMPORT, %(import { Sortable } from "sortablejs")
    assert_match STATIC_SORTABLE_IMPORT, %(import Sortable, { Swap } from "sortablejs")
    assert_match STATIC_SORTABLE_IMPORT, %(import * as Sortable from "sortablejs")
    assert_match STATIC_SORTABLE_IMPORT, %(import "sortablejs")
    assert_no_match STATIC_SORTABLE_IMPORT, %(const { default: Sortable } = await import("sortablejs"))
    assert_no_match STATIC_SORTABLE_IMPORT, %(import("sortablejs").then((m) => m.default))
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
      dashboard_screen/card_component.rb dashboard_screen/card_component.html.erb
      dashboard_screen/translation_card_component.rb dashboard_screen/translation_card_component.html.erb
      dashboard_screen/quick_create_component.rb dashboard_screen/quick_create_component.html.erb
    ].each do |file|
      assert_not Rails.root.join("app/components/admin", file).exist?, file
    end
    # The dashboard's buttons open the layout's New post and New page
    # dialogs, with no script of the dashboard's.
    %w[quick_create_controller.js start_draft_controller.js].each do |file|
      assert_not Rails.root.join("app/javascript/controllers/admin/dashboard", file).exist?, file
    end
    assert_not Rails.root.join("app/views/shared/_theme_toggle.html.erb").exist?
    # Languages is a card of the Settings screen, an image's detail a panel
    # beside the Media grid, and the audit log words its rows through
    # `Audit::Sentence`: no screen or helper draws them a second way.
    %w[
      app/views/admin/languages/index.html.erb app/views/admin/media/show.html.erb
      app/views/admin/shared/_image_upload_field.html.erb app/views/admin/api_tokens/_connection.html.erb
      app/views/admin/users/_access_fields.html.erb app/helpers/admin/audit_events_helper.rb
    ].each do |file|
      assert_not Rails.root.join(file).exist?, file
    end
    # The translation states live in `translation_states` (`Translations::StateIndex`).
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

  # A boundary that identifies a control is
  # `--cs-field-line`, 3:1 on every ground; `--cs-line-strong` only groups.
  # Read line by line: a line whose classes make it pressable or typed into
  # (a hover, a focus, a checked state, a placeholder, a pointer cursor)
  # draws no strong line. A control whose line says none of those (a
  # segmented group's frame, the drop zone) is not seen here: review holds
  # them. The public layouts are the theme's, whose
  # outline token is `--th-meta` (`design_tokens_test.rb`).
  CONTROL_SOURCES = (ADMIN_SOURCES + [ Rails.root.join("app/helpers/setup_helper.rb").to_s ])
    .reject { |path| path.start_with?(Rails.root.join("app/views/layouts/public").to_s) }
  CONTROL_STATE = /(?<![\w-])(?:hover|focus|focus-within|focus-visible|has-checked|has-\[:checked\]|placeholder):|\bcursor-pointer\b/
  STRONG_LINE_ALLOWED = {
    "data-mind-graph-card" => "the graph's card is a panel that takes the focus; its outline is the focus ring"
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

  # A block card's and a tile's state (held, its type gone, its thread open)
  # is an outline inside its edge, drawn by the stylesheet from an attribute,
  # so nothing changes size and no shadow is overwritten; a border utility on
  # the wrapper or the head would be a second edge beside it.
  EDITOR_CARDS = %w[block_card_component.html.erb block_tile_component.html.erb section_card_component.html.erb].map { |f| "app/components/admin/editor_screen/#{f}" }.freeze
  EDITOR_CARD_WRAPPER = /class[=:].*(?<![\w-])admin-block-(?:card|tile)(?:__head)?(?![\w-])/
  BORDER_EDGE = /(?<![\w-])border(?:-(?:line|line-strong|danger|accent|field-line))?(?=[\s"'])/
  # Held by someone else and discussed in the notes are one frame: the marks
  # that already exist, in one rule, the people's.
  PEOPLE_FRAME = [ '.admin-block-card:where(:not(.admin-section-card))[data-card-edge="held"]',
                   ".admin-block-card:where(:not(.admin-section-card))[data-notes-active]",
                   ".admin-block-tile[data-notes-active]" ].freeze
  UNAVAILABLE_EDGE = '.admin-block-card[data-card-edge="unavailable"]'
  SECTION_FRAME = [ '.admin-section-card[data-card-edge="held"]',
                    '.admin-section-card:where(:has(> .admin-section-card__settings form[data-editing-frozen="true"]))' ].freeze
  CHOSEN_SECTION = ":is(.admin-section-card, .admin-section-group)[data-chosen]"

  test "the editor's cards and tiles draw no border utility: their edges are the stylesheet's state outlines" do
    wrappers = EDITOR_CARDS.flat_map { |path| Rails.root.join(path).readlines.each_with_index.select { |line, _| line.match?(EDITOR_CARD_WRAPPER) }.map { |line, index| [ path, index, line ] } }
    assert_operator wrappers.size, :>=, 3, "the wrapper lines are found: the card's, its head's and the tile's"
    offences = wrappers.select { |_, _, line| line.match?(BORDER_EDGE) }.map { |path, index, _| "#{path}:#{index + 1}" }
    assert_empty offences, "a border utility on a card or tile wrapper"
  end

  test "held and discussed blocks share one people outline, under the unavailable edge and the chosen section" do
    rules = self.class.css_rules("content-spiel.tailwind.css")
    frame = rule_for(PEOPLE_FRAME)
    assert_match(/outline:\s*2px solid var\(--cs-people\)/, frame)
    assert_match(/outline-offset:\s*-2px/, frame)
    assert_no_match(/--cs-accent|--cs-field-line/, frame)
    notes = rules.select { |selectors, _| selectors.any? { |selector| selector.include?("[data-notes-active]") && !selector.include?(":not([data-notes-active])") } }
    assert_equal [ PEOPLE_FRAME ], notes.map(&:first), "a thread open in the notes is drawn by the people frame and by no rule beside it"
    assert_no_match(/admin-people-frame/, ADMIN_SOURCES.map { |path| File.read(path) }.join, "no element carries a class for the frame: the marks are the selectors")

    unavailable = single_rule(UNAVAILABLE_EDGE)
    assert_match(/outline:\s*2px solid var\(--cs-danger\)/, unavailable)
    assert_match(/outline-offset:\s*-2px/, unavailable)
    order = [ PEOPLE_FRAME, [ UNAVAILABLE_EDGE ], [ CHOSEN_SECTION ] ].map { |selectors| rules.index { |found, _| found == selectors } }
    assert_equal order.sort, order, "the people frame, then the unavailable edge, then the chosen section: the later wins at one weight"
  end

  # A live merge synchronises a section's frame, which is not a kept unit, so
  # it may drop a `data-card-edge` the server drew: the stylesheet draws the
  # outline from the mark and from the frozen settings form alike, and in both
  # cases outside the frame.
  test "a held section draws the people outline outside its frame, from the server's mark or its frozen form, under the unavailable edge" do
    rules = self.class.css_rules("content-spiel.tailwind.css")
    body = rule_for(SECTION_FRAME)
    assert_match(/outline:\s*2px solid var\(--cs-people\)/, body)
    assert_match(/outline-offset:\s*2px/, body)
    assert(PEOPLE_FRAME.grep(/card-edge/).all? { |selector| selector.include?(":where(:not(.admin-section-card))") }, "the block frame leaves a section out")
    frame = rules.index { |found, _| found == PEOPLE_FRAME }
    section = rules.index { |found, _| found == SECTION_FRAME }
    unavailable = rules.index { |found, _| found == [ UNAVAILABLE_EDGE ] }
    chosen = rules.index { |found, _| found == [ CHOSEN_SECTION ] }
    assert_equal [ frame, section, unavailable, chosen ].sort, [ frame, section, unavailable, chosen ], "the unavailable edge and the chosen section come later and win"
  end

  DRAGLESS = ".admin-block-card:where(:not(.admin-drag-chosen, .admin-drag-ghost, .admin-drag-fallback))".freeze
  GLOW = ".admin-block-card:has(> .admin-block-card__head [data-editing-mark]:not(.admin-editing-mark--leaving)):not([data-card-edge=\"held\"]):not([data-notes-active])".freeze

  test "a card glows in the people hue while its mark stands, never on a held card, and not under reduced motion" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    glow = self.class.css_rules("content-spiel.tailwind.css").find { |selectors, body| selectors == [ GLOW ] && body.include?("color-mix") }&.last
    assert glow, "the glow is drawn by the stylesheet"
    assert_match(/box-shadow:\s*var\(--cs-shadow-1\), 0 0 0 4px color-mix\(in oklab, var\(--cs-people\) 20%, transparent\)/, glow)
    assert_match(/transition-duration:\s*200ms/, glow)
    assert_includes css.gsub(/\s+/, " "), "#{DRAGLESS} { transition: box-shadow 600ms var(--cs-ease); }", "600ms out, and not on a card being dragged"
    assert_match(/@media \(prefers-reduced-motion: no-preference\)\s*\{\s*#{Regexp.escape(GLOW)}\s*\{[^}]*color-mix/, css, "the glow is drawn only where motion is welcome")
    assert_match(/@media \(prefers-reduced-motion: reduce\)\s*\{\s*#{Regexp.escape(DRAGLESS)}\s*\{\s*transition:\s*none;\s*\}\s*\}/, css, "under reduced motion the card has no transition")
  end

  # A section is a frame of the structure colour around its lanes, not a
  # card: no ground of its own, the frame's radius, a 1.5px edge, danger
  # when its type is gone. Its head is tinted and its words are the head's
  # ink, thinned behind them under the pointer or the focus.
  test "a section is a structure frame with a tinted head, and its words are the head's ink" do
    frame = single_rule(".admin-section-card")
    assert_match(/border:\s*1\.5px solid var\(--cs-structure\)/, frame)
    assert_match(/border-radius:\s*var\(--cs-radius-frame\)/, frame)
    assert_match(/background:\s*transparent/, frame)
    assert_match(/border-color:\s*var\(--cs-danger\)/, single_rule('.admin-section-card[data-card-edge="unavailable"]'))
    head = single_rule(".admin-section-card__head")
    assert_match(/background:\s*var\(--cs-structure-tint\)/, head)
    assert_match(/color:\s*var\(--cs-structure-ink\)/, head)
    assert_match(/border-radius:\s*calc\(var\(--cs-radius-frame\) - 1\.5px\) calc\(var\(--cs-radius-frame\) - 1\.5px\) 0 0/, head)
    assert_match(/padding:\s*10px 12px/, head)
    word = single_rule(".admin-section-word")
    assert_match(/color:\s*var\(--cs-structure-ink\)/, word)
    assert_match(/font-size:\s*13px/, word)
    assert_match(/border-radius:\s*var\(--cs-radius\)/, word)
    assert_match(/background:\s*color-mix\(in srgb, var\(--cs-structure-ink\) 12%, transparent\)/, single_rule(".admin-section-word:is(:hover, :focus-visible)"))
    assert_match(/outline:\s*2px solid var\(--cs-accent\)/, single_rule(".admin-section-word:focus-visible"))
  end

  # A tile's states are drawn by elevation (`.admin-block-tile`): at rest
  # the first, under the pointer the second, open or focused the third with
  # the accent ring outside its edge. Its thread open is the people
  # frame, an outline inside its edge. No border: the drop place's dashes are the only edge a tile
  # shows, and only while it is the place a drag would land.
  TILE_STATES = {
    [ ".admin-block-tile" ] => [ "var(--cs-radius-tile)", "background: var(--cs-surface)", "box-shadow: var(--cs-shadow-1)" ],
    [ ".admin-block-tile:where(:hover)" ] => [ "box-shadow: var(--cs-shadow-2)", "background: var(--cs-tile-raised)" ],
    [ '.admin-block-tile:where(:has(> .admin-block-tile__face[aria-expanded="true"]))', ".admin-block-tile:where(:has(> .admin-block-tile__face:focus-visible))" ] =>
      [ "box-shadow: var(--cs-shadow-3), 0 0 0 2px var(--cs-accent)", "background: var(--cs-tile-raised)" ],
    [ ".admin-drag-ghost" ] => [ "border: 1.5px dashed var(--cs-field-line)", "border-radius: var(--cs-radius-tile)", "box-shadow: none" ],
    [ ".admin-drag-chosen" ] => [ "background: var(--cs-popover)", "box-shadow: var(--cs-shadow-4)" ],
    [ ".admin-drag-fallback" ] => [ "background: var(--cs-popover)", "box-shadow: var(--cs-shadow-4)" ]
  }.freeze

  test "a tile's states are elevations and the accent, and none of them is a border" do
    TILE_STATES.each do |selectors, declarations|
      body = rule_for(selectors)
      declarations.each { |declaration| assert_includes body, declaration, selectors.join(", ") }
      assert_no_match(/(?<![\w-])border(?:-color)?:/, body, selectors.join(", ")) unless selectors == [ ".admin-drag-ghost" ]
    end
    order = TILE_STATES.keys.map { |selectors| self.class.css_rules("content-spiel.tailwind.css").index { |found, _| found == selectors } }
    assert_equal order.sort, order, "rest, the pointer, open or focused, the thread, then the drop place and the lifted tile: the later state wins at one weight"
  end

  # A tile in a grid (`.admin-tile`: the media tiles, the upload tiles,
  # Translations' language tiles, the Dashboard's draft tiles, the user
  # editor's group tiles) is drawn by one rule set, its states elevations
  # and the selection's accent outline, which a ticked label tile takes too.
  # A locked tile is sunken with no shadow, after the selection so a ticked
  # locked one keeps the outline and not the shadow. A transform would move
  # it under the pointer, and a border is an edge drawn for depth.
  TILE = '.admin-tile:is([aria-current="true"], [aria-pressed="true"])'.freeze
  TICKED_TILE = ".admin-tile:has(> input:checked)".freeze
  LOCKED_TILES = [ ".admin-tile[data-locked]", ".admin-tile[data-locked]:has(> input:checked)" ].freeze

  test "a tile is .admin-tile: elevation 1 at rest, 2 under a pointer, the accent outline when selected, pressed or ticked, sunken when locked; never a transform" do
    rest = single_rule(".admin-tile")
    [ "border-radius: var(--cs-radius-tile)", "background: var(--cs-surface)", "box-shadow: var(--cs-shadow-1)" ].each { |declaration| assert_includes rest, declaration }

    hovers = self.class.css_blocks("content-spiel.tailwind.css", /@media \(hover: hover\)\s*\{/).select { |body| body.include?(".admin-tile:hover") }
    assert_equal 1, hovers.size, "the pointer's elevation is drawn only where a pointer can hover"
    assert_match(/\.admin-tile:hover\s*\{\s*box-shadow:\s*var\(--cs-shadow-2\);\s*\}/, hovers.first)
    assert_includes single_rule(".admin-tile:hover"), "box-shadow: var(--cs-shadow-2)"

    selected = rule_for([ TILE, TICKED_TILE ])
    [ "outline: 2px solid var(--cs-accent)", "outline-offset: 2px", "box-shadow: var(--cs-shadow-1)" ].each { |declaration| assert_includes selected, declaration }
    locked = rule_for(LOCKED_TILES)
    [ "background: var(--cs-sunken)", "box-shadow: none", "color: var(--cs-meta)" ].each { |declaration| assert_includes locked, declaration }
    assert_no_match(/outline/, locked, "a ticked locked tile keeps the selection's outline")

    rules = self.class.css_rules("content-spiel.tailwind.css")
    order = [ [ ".admin-tile" ], [ ".admin-tile:hover" ], [ TILE, TICKED_TILE ], LOCKED_TILES ].map { |selectors| rules.index { |found, _| found == selectors } }
    assert_equal order.sort, order, "rest, the pointer, the selection, then the lock: the selection wins under the pointer, and the lock over both"
    tile_rules = rules.select { |selectors, _| selectors.any? { |selector| selector.match?(/\.admin-tile(?![\w-])/) } }
    tile_rules.each do |selectors, body|
      assert_no_match(/(?<![\w-])(?:transform|translate|scale|rotate):/, body, "#{selectors.join(", ")} moves the tile")
      assert_no_match(/(?<![\w-])border(?!-radius)[\w-]*:/, body, "#{selectors.join(", ")} draws a border")
    end
  end

  # A tile's look written as utilities (the tile radius with an elevation of
  # its own) is a second tile beside `.admin-tile`, which a restyle of the
  # tile would miss. Read a line at a time.
  HAND_TILE = /(?=.*(?<![\w-])rounded-tile(?![\w-]))(?=.*(?<![\w-])(?:[\w-]+:)*shadow-[1-4](?![\w-])).*/

  test "no hand-drawn tile: the tile radius never stands with an elevation utility on one line" do
    assert_empty design_offences(HAND_TILE), "a tile is .admin-tile, never rounded-tile with a shadow utility"
  end

  test "the hand-drawn tile pattern matches the tile radius with an elevation, and not either alone" do
    [ 'class="rounded-tile bg-surface shadow-1 p-4"', '"shadow-1 rounded-tile"', "rounded-tile hover:shadow-2" ].each { |sample| assert_match HAND_TILE, sample }
    [ 'class="rounded-tile bg-paper"', 'class="rounded-card shadow-1"', "admin-tile p-4", "rounded-tile shadow-menu", "rounded-tile-x shadow-1" ].each { |sample| assert_no_match HAND_TILE, sample }
  end

  test "the border pattern matches a border utility of the card's colours, and not a radius, an outline or a hover" do
    [ 'class="border ', "border-line ", "border-line-strong\"", "border-danger'", "border-accent ", "border-field-line\"", "data-[notes-active]:border-accent " ].each { |sample| assert_match BORDER_EDGE, sample }
    [ "rounded-card ", "outline-accent ", "border-b ", "borderless ", "admin-border-x " ].each { |sample| assert_no_match BORDER_EDGE, sample }
  end

  # A button is `Admin::Ui::ButtonComponent`'s (or its `.classes`, which a
  # link, a label and a script take): an outlined box with a field-line edge on
  # a button, a menu's trigger or anything a pointer presses is a button drawn
  # by hand, outside the component. A script takes the strings from the view (a `data-` value),
  # or, where it cannot, is held to them string for string (the popover, below).
  # What may keep a field-line edge and still be pressed is a control that is
  # not a button, each named with its reason.
  PRESSABLE = /<button|tag\.button|button_class:|(?<![\w-])cursor-pointer(?![\w-])|element\("button"|createElement\("button"\)/
  FIELD_LINE_EDGE = /(?<![\w-])(?:[\w-]+:)*border-field-line(?![\w-])/
  HAND_BUTTON_ALLOWED = {
    "admin-rich-text-button" => "the rich-text toolbar's toggles: `aria-pressed` draws their edge",
    "rounded-button border border-field-line px-2 py-1 text-sm text-meta" => "the top bar's ⌘K launcher, a launcher button drawn as a field-like box; it opens the palette, whose own input is bare",
    "rounded-button border border-field-line px-2 py-1.5 text-left text-sm text-meta" => "the sidebar's ⌘K launcher, a launcher button drawn as a field-like box; it opens the palette, whose own input is bare"
  }.freeze

  test "no hand-built button: nothing pressable in CS Studio draws a field-line edge, but the named controls" do
    offences = CONTROL_SOURCES.flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, index|
        next unless line.match?(PRESSABLE) && line.match?(FIELD_LINE_EDGE)
        next if HAND_BUTTON_ALLOWED.keys.any? { |marker| line.include?(marker) }

        "#{Pathname(path).relative_path_from(Rails.root)}:#{index + 1}"
      end
    end
    assert_empty offences, "draw it with Admin::Ui::ButtonComponent (or `.classes`), or name the control in HAND_BUTTON_ALLOWED"
  end

  test "the hand-built button patterns match a button with a field-line edge, and not a well or a frame" do
    [ '<button class="rounded-cs border border-field-line px-2">', 'tag.button type: "button", class: "border border-field-line"',
      'button_class: "inline-flex rounded-cs border border-field-line"', '<label class="cursor-pointer border border-field-line">',
      'element("button", "rounded-cs border border-field-line")' ].each do |sample|
      assert sample.match?(PRESSABLE) && sample.match?(FIELD_LINE_EDGE), sample
    end
    [ '<input class="rounded-t-field border-0 border-b border-field-line bg-field-fill">', '<div class="inline-flex rounded-cs border border-field-line">',
      '<button class="cursor-pointer bg-accent-tint text-accent">', '<span class="border-field-line-ish cursor-pointer">' ].each do |sample|
      assert_not sample.match?(PRESSABLE) && sample.match?(FIELD_LINE_EDGE), sample
    end
  end

  test "every hand-built button allowance is still used" do
    HAND_BUTTON_ALLOWED.each_key do |marker|
      assert CONTROL_SOURCES.any? { |path| File.readlines(path).any? { |line| line.include?(marker) && line.match?(PRESSABLE) && line.match?(FIELD_LINE_EDGE) } },
        "#{marker} does not draw a pressable field-line edge: drop it from HAND_BUTTON_ALLOWED"
    end
  end

  test "the block picker builds no button of its own" do
    source = Rails.root.join("app/components/admin/editor_screen/block_picker_component.rb").read.gsub(/^\s*#.*$/, "")
    assert_no_match(/VARIANT_CLASSES|SMALL_CLASS/, source)
    assert_match(/ButtonComponent\.classes\(:primary\)/, source)
  end

  test "the rich-text popover's script-built buttons and input are the component's strings" do
    source = Rails.root.join("app/javascript/rich_text/popover.js").read
    constant = ->(name) { source[/^const #{name} = "([^"]*)"$/, 1] }
    variants = source[/^const BUTTON_VARIANTS = \{\n(.*?)^\}/m, 1].to_s.scan(/^\s*(\w+): "([^"]*)"/).to_h
    assert_equal %w[primary secondary tertiary danger_text], variants.keys
    variants.each do |variant, classes|
      assert_equal Admin::Ui::ButtonComponent.classes(variant.to_sym, size: :small), "#{constant.("BUTTON_CLASS")} #{classes}", variant
    end
    helpers = Object.new.extend(SetupHelper)
    assert_equal helpers.setup_input_class, constant.("INPUT_CLASS")
    assert_equal helpers.setup_label_class, constant.("LABEL_CLASS")
  end

  # The stylesheet's rules as `[selectors, declarations]`, comments stripped,
  # a selector list split at its top-level commas (not those inside `:is()`),
  # so a rule is found by its whole selector or by what it declares, never by
  # where it happens to stand in the file.
  def self.css_rules(name)
    css = Rails.root.join("app/assets/tailwind", name).read.gsub(%r{/\*.*?\*/}m, "")
    css.scan(/([^{}]+)\{([^{}]*)\}/).map do |selector, body|
      depth = 0
      parts = selector.strip.each_char.slice_when do |char, _|
        depth += 1 if char == "("
        depth -= 1 if char == ")"
        char == "," && depth.zero?
      end
      [ parts.map { |part| part.join.delete_suffix(",").squish }, body ]
    end
  end

  WELL_CONTAINERS = ":is(.admin-column, .admin-field, .admin-filter-bar, .admin-filter-panel, .admin-rich-text-popover, .admin-translation-suggestion)".freeze
  WELL_CONTROLS = ':is(input:not([type="file"], [type="hidden"], [type="checkbox"], [type="radio"], [type="range"], [type="color"], ' \
                  '[type="submit"], [type="button"], [type="reset"], [type="image"], :where(.admin-prefix-input input, .admin-chip-field input)), ' \
                  "textarea, select, .admin-rich-text-editor, .admin-chip-field)".freeze
  WELL_SELECTORS = [ "#{WELL_CONTAINERS} #{WELL_CONTROLS}", ".admin-well" ].freeze
  WELL_FOCUS_SELECTORS = [ "#{WELL_CONTAINERS} #{WELL_CONTROLS}:is(:focus, :focus-within)", ".admin-well:is(:focus, :focus-within)" ].freeze

  def rule_for(selectors, name = "content-spiel.tailwind.css")
    matches = self.class.css_rules(name).select { |found, _| found == selectors }
    assert_equal 1, matches.size, "one rule is #{selectors.join(", ")}"
    matches.first.last
  end

  def single_rule(selector, name = "content-spiel.tailwind.css") = rule_for([ selector ], name)

  test "a text field is a well: the field fill and a field-line bottom edge, the accent outline on focus; a checkbox and a toggle keep a full outline" do
    shared = rule_for(WELL_SELECTORS)
    # `background-color`, not the shorthand: the shorthand would wipe a select's chevron.
    assert_match(/background-color:\s*var\(--cs-field-fill\);/, shared)
    assert_match(/border-width:\s*0 0 1px;/, shared)
    assert_includes shared, "var(--cs-field-invalid-border, var(--cs-field-line))"
    assert_match(/border-radius:\s*var\(--cs-radius-field\) var\(--cs-radius-field\) 0 0;/, shared)
    assert_match(/outline:\s*2px solid var\(--cs-accent\);/, rule_for(WELL_FOCUS_SELECTORS))
    assert_match(/border-width:\s*0 0 1px;/, single_rule(".cs-select"))
    assert_match(/border-bottom-color:\s*var\(--cs-field-line\);/, single_rule(".cs-select"))
    assert_match(/background-color:\s*var\(--cs-field-fill\);/, single_rule(".cs-select"))
    assert_match(/border:\s*1px solid var\(--cs-field-line\);/, single_rule(".cs-toggle"))
    assert_match(/\A\s*border-color:\s*var\(--cs-field-line\);/, single_rule(".admin-column:not(:has(> [id$=\"-errors\"] > p)) .admin-prefix-input:not(:focus-within)"))
    assert_no_match(/font-size:\s*10px/, Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read)
  end

  test "a filter bar and a filter panel reset the invalid edge, as every wrapper of wells does" do
    reset = self.class.css_rules("content-spiel.tailwind.css").find { |_, body| body.include?("--cs-field-invalid-border: initial") }
    assert_equal %w[.admin-column .admin-field .admin-filter-bar .admin-filter-panel .admin-rich-text-popover .admin-translation-suggestion], reset&.first
  end

  test "the rule parser finds a rule by its whole selector list and splits it only at top-level commas" do
    rules = self.class.css_rules("content-spiel.tailwind.css")
    assert rules.any? { |selectors, _| selectors == WELL_SELECTORS }
    assert_not rules.any? { |selectors, _| selectors.include?(".admin-column") && selectors.include?("textarea") }, "a comma inside :is() split the list"
  end

  # A text field is a well, from its wrapper (`.admin-column`,
  # `.admin-field`, `.admin-filter-bar`, the popover, the suggestion box) or
  # from `.admin-well`, so neither a full field-line outline nor a focus
  # colour of its own stands on an input in CS Studio's markup.
  TEXT_INPUT = /text_field_tag|search_field_tag|text_area_tag|email_field_tag|password_field_tag|number_field_tag|date_field_tag|url_field_tag|<input|<textarea|tag\.input|tag\.textarea|element\("(?:input|textarea)"|createElement\("(?:input|textarea)"\)|(?<![\w-])(?:focus|focus-visible|focus-within):(?:outline|border)-accent(?![\w-])/
  FULL_FIELD_LINE = /\A(?=.*(?<![\w:-])border(?![\w-]))(?=.*(?<![\w-])(?:[\w-]+:)*border-field-line(?![\w-]))/

  test "no text input in CS Studio is the old outlined box" do
    offences = CONTROL_SOURCES.flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, index|
        "#{Pathname(path).relative_path_from(Rails.root)}:#{index + 1}" if line.match?(TEXT_INPUT) && line.match?(FULL_FIELD_LINE)
      end
    end
    assert_empty offences, "a text field is a well: put it in a wrapper of wells or give it `admin-well`"
  end

  test "the old-box pattern matches an outlined input, and not a well, a frame or a choice tile" do
    [ 'text_field_tag :q, nil, class: "block rounded-cs border border-field-line bg-surface px-3"',
      'class: "w-32 rounded-cs border border-field-line bg-surface focus-visible:outline-2 focus-visible:outline-accent"',
      '<div class="relative rounded-cs border border-field-line bg-surface focus-within:border-accent">',
      'element("textarea", "block w-full rounded-cs border border-field-line bg-surface")' ].each do |sample|
      assert sample.match?(TEXT_INPUT) && sample.match?(FULL_FIELD_LINE), sample
    end
    [ 'text_field_tag :q, nil, class: "admin-well block w-56 px-3"', '<input class="rounded-t-field border-0 border-b border-field-line bg-field-fill">',
      '<div class="inline-flex overflow-hidden rounded-cs border border-field-line bg-surface">',
      '<label class="border border-field-line has-focus-visible:outline-accent">' ].each do |sample|
      assert_not sample.match?(TEXT_INPUT) && sample.match?(FULL_FIELD_LINE), sample
    end
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
    "CONTENT·SPIEL" => "the wordmark of the product and setup layouts"
  }.freeze
  # CS Studio's sources, the setup pages and the three layouts around them.
  # The public site is the theme's and out of scope: its pages keep their look.
  # The visitor's two layouts (`application`, the public page's, and
  # `form_send`) are a visitor's page, not CS Studio's.
  VISITOR_LAYOUTS = %w[application form_send].map { |name| Rails.root.join("app/views/layouts/#{name}.html.erb").to_s }.freeze
  TYPE_VOICE_SOURCES = (ADMIN_SOURCES - Dir[Rails.root.join("app/{views/layouts/public,components/public}/**/*")] - VISITOR_LAYOUTS).concat(
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

  # The rail docks by the editor area's width: a classic scrollbar that
  # comes and goes with the page's height must not move it across.
  test "CS Studio's document keeps its scrollbar gutter, so a scrollbar takes no width from the editor area" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.css").read.gsub(%r{/\*.*?\*/}m, "")
    assert_match(/^html\[data-surface="studio"\]\s*\{[^}]*scrollbar-gutter:\s*stable;/m, css)
    assert_equal 1, css.scan(/scrollbar-gutter/).size, "the gutter is the studio surface's alone"
  end

  # The theme switch's cross-fade (theme_controller.js) is timed by two
  # tokens written once, and its two rules set only the duration and the
  # easing: an `animation` shorthand would reset the browser's own fade-out
  # and fade-in keyframes to none.
  test "the theme fade is two tokens written once, read by the root's old and new view-transition rules" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.css").read.gsub(%r{/\*.*?\*/}m, "")
    assert_equal [ "250ms" ], css.scan(/--cs-theme-fade-duration:\s*([^;]+);/).flatten
    assert_equal [ "ease-out" ], css.scan(/--cs-theme-fade-easing:\s*([^;]+);/).flatten
    rules = self.class.css_rules("content-spiel.css").select { |selectors, _| selectors.any? { |selector| selector.include?("::view-transition") } }
    assert_equal 1, rules.size, "one rule for the fade"
    selectors, body = rules.first
    assert_equal [ 'html[data-surface="studio"]::view-transition-old(root)', 'html[data-surface="studio"]::view-transition-new(root)' ], selectors
    assert_match(/animation-duration:\s*var\(--cs-theme-fade-duration\);/, body)
    assert_match(/animation-timing-function:\s*var\(--cs-theme-fade-easing\);/, body)
    assert_no_match(/(?<![\w-])animation:/, body, "no shorthand: it would drop the browser's fade keyframes")
    assert_equal 4, css.scan(/--cs-theme-fade-/).size, "two definitions and the fade rule's two reads"
    other = Dir[Rails.root.join("app/assets/tailwind/**/*.css")].reject { |path| path.end_with?("/content-spiel.css") }
    assert_empty other.select { |path| File.read(path).include?("--cs-theme-fade-") }, "the tokens are content-spiel.css's alone"
  end

  # The form-send pages' required word keeps its capitals: a visitor's page,
  # not CS Studio's. Only a selector under `.form-send-page` is let through: a
  # CS Studio selector beside it in the same list, or on the same line, is not.
  def capitals_offences(name, rules = self.class.css_rules(name))
    rules.flat_map do |selectors, body|
      next [] unless body.match?(/text-transform:\s*uppercase/)

      selectors.reject { |selector| selector.match?(/\A\.form-send-page(?![\w-])/) }.map { |selector| "#{name}: #{selector}" }
    end
  end

  test "the stylesheets set no label in capitals" do
    %w[content-spiel.tailwind.css admin-rich-text.css].each { |name| assert_empty capitals_offences(name) }
  end

  test "the capitals check lets through a form-send selector and nothing beside it" do
    rules = [ [ [ ".form-send-page .form-field__required" ], "text-transform: uppercase;" ],
              [ [ ".form-send-page .x", ".admin-badge" ], "text-transform: uppercase;" ],
              [ [ ".form-send-pager" ], "text-transform: uppercase;" ] ]
    assert_equal [ "x.css: .admin-badge", "x.css: .form-send-pager" ], capitals_offences("x.css", rules)
  end

  # Mono is for code and for a value a person copies or compares exactly. Everything else (counts, times,
  # addresses, ⌘K, a field error's "!", language codes, initials, badges, the sidebar's numbers) is the sans.
  MONO_CODE = /<code|<pre|tag\.code|tag\.pre/
  MONO_ALLOWED = {
    "app/components/admin/ui/save_status_component.rb" => "the save status line stays mono capitals",
    "app/components/admin/editor_screen/tile_summary_component.rb" => "the Code block's tile shows its source as the mono look",
    "app/components/admin/fields/code_field.rb" => "the Code block's source field is code",
    "app/views/setup/token.html.erb" => "the setup token's input holds a key value, and the log's commands are code",
    "app/components/admin/ui/copy_value_component.html.erb" => "a value a person copies exactly: a token, an address, a command",
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

  # A heading is drawn at a size token's utility; a token with no utility is
  # written as a bare size instead, which the type voice cannot see.
  test "each heading size token has its utility" do
    theme = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")[/@theme inline \{(.*?)\n\}/m, 1]
    tokens = Rails.root.join("app/assets/tailwind/content-spiel.css").read.gsub(%r{/\*.*?\*/}m, "")
    %w[h1 h2 h3].each do |size|
      assert_includes theme, "--text-#{size}: var(--cs-t-#{size});", "the @theme block maps text-#{size}"
      assert_match(/--cs-t-#{size}:\s*\d+px/, tokens, "--cs-t-#{size} is a size")
    end
    assert_includes theme, "--text-h3--font-weight: 600;"
  end

  # A count is a figure in a pill, `text-count`; the 12px label would grow it
  # with the label. A line that draws a count (a count helper, a tab's count,
  # a total, the graph legend's count, the presence marker's) carries no
  # `text-label`, but where the number is inside words.
  COUNT_MARKER = /(?<![\w-])(?:count|counts|open_count|count_for|badge_count|presence_marker_count)(?![\w-])|\.total(?![\w-])|tab\[:count\]|data-legend-count/
  LABEL_CLASS = /(?<![\w-])text-label(?![\w-])/
  COUNT_LABEL_ALLOWED = {
    "admin.note_inbox.card.new" => "the inbox card's “3 new” is words with a number in them, not a figure in a pill"
  }.freeze

  test "a count is text-count, not the 12px label" do
    offences = TYPE_VOICE_SOURCES.flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, index|
        next unless line.match?(COUNT_MARKER) && line.match?(LABEL_CLASS)
        next if COUNT_LABEL_ALLOWED.keys.any? { |marker| line.include?(marker) }

        "#{Pathname(path).relative_path_from(Rails.root)}:#{index + 1}"
      end
    end
    assert_empty offences, "a count is `text-count`; words with a number go in COUNT_LABEL_ALLOWED"
  end

  test "the count pattern matches a count helper, a tab's count, a total and the markers, and not text-count or a word" do
    [ '<span class="text-label"><%= count %></span>', "<%= open_count %>", "tab[:count]", "@page.total", "data-legend-count", "presence_marker_count(row)", "count_for(name)" ]
      .each { |sample| assert_match COUNT_MARKER, sample }
    [ "text-count", "account", "counter", "discount", "totally", "count-down" ].each { |sample| assert_no_match COUNT_MARKER, sample }
  end

  test "every count-label allowance is still used" do
    COUNT_LABEL_ALLOWED.each_key do |marker|
      assert TYPE_VOICE_SOURCES.any? { |path| File.readlines(path).any? { |line| line.include?(marker) && line.match?(COUNT_MARKER) && line.match?(LABEL_CLASS) } },
        "#{marker} does not draw a count in the label: drop it from COUNT_LABEL_ALLOWED"
    end
  end

  # 10px thin text looks faint, so the smallest is 11px, everywhere, and a
  # person's initials join it: an avatar draws its letters at `text-count`.
  test "no text under 11px in CS Studio's markup, and a mono label is text-label" do
    assert_empty design_offences(/text-\[(?:[0-9]|10)px\]/)
    assert_empty design_offences(/font-cs-mono[^"'`]*text-\[11px\]|text-\[11px\][^"'`]*font-cs-mono/)
  end

  # The screens drawn on the type scale (media, Trash, Translations, Forms,
  # the audit log, and the people and system screens as each joins) speak in
  # the type scale's tokens and draw no box of their own: a card is an
  # elevation, a table's lines stay inside its card, and a control keeps its
  # field-line frame. Each screen's folders join `TYPE_SCALE_SCREENS` (globs
  # from the root) as it is drawn on the scale.
  # Refused there, line by line: an arbitrary pixel size, `text-xs` (the
  # label is `text-label`), a dashed edge and an important danger edge. And,
  # string by string: the hand-drawn box, `rounded-cs` with `border-line` (or
  # `-strong`, under any variant) in one quoted class string, in whatever
  # order. A Ruby literal continued on the next line (`"…" \` then `"…"`) is
  # one string, and a `#{NAME}` of a string constant the same file assigns
  # (`NAME = "…"`) is read as that constant's classes. Not seen: `+` or
  # adjacent literals, a constant from another file, ERB or a ternary inside
  # the attribute, `class_names(…)`, an array or `%w[…]` (the reference's
  # "No guard" list, `docs/reference/design-system.md`).
  TYPE_SCALE_SCREENS = %w[
    app/components/admin/media_library/*
    app/views/admin/media/*
    app/components/admin/ui/media_picker_component.*
    app/components/admin/notes_screen/media_section_component.*
    app/components/admin/trash_screen/*
    app/views/admin/trash/*
    app/components/admin/translation_screen/matrix_component.*
    app/components/admin/translation_screen/summary_card_component.*
    app/views/admin/translations/*
    app/components/admin/forms_screen/*
    app/views/admin/forms/*
    app/views/admin/form_submissions/*
    app/components/admin/audit_screen/*
    app/views/admin/audit_events/*
    app/components/admin/users_screen/*
    app/views/admin/users/*
    app/components/admin/groups_screen/*
    app/views/admin/groups/*
    app/components/admin/tokens_screen/*
    app/views/admin/api_tokens/*
    app/views/layouts/product.html.erb
    app/views/admin/shared/_auth_heading.html.erb
    app/views/admin/shared/_product_wordmark.html.erb
    app/views/admin/sessions/*
    app/views/admin/passwords/*
    app/views/invitations/*
    app/views/admin/accounts/*
    app/views/admin/system_status/*
    app/views/admin/errors/*
    app/views/setup/*
    app/views/layouts/setup.html.erb
  ].freeze
  OFF_SCALE = /(?<![\w-])text-\[\d+px\]|(?<![\w-])text-xs(?![\w-])|(?<![\w-])border-dashed(?![\w-])|(?<![\w-])!border-danger(?![\w-])/
  QUOTED = /"((?:[^"\n]|"[ \t]*\\\n[ \t]*")*)"|'([^'\n]*)'/
  BOX_EDGE = /\A(?:[\w-]+:)*border-line(?:-strong)?\z/
  CONTINUED = /"[ \t]*\\\n[ \t]*"/
  STRING_CONSTANT = /\b([A-Z][A-Z0-9_]*)\s*=\s*"((?:[^"\n]|#{CONTINUED.source})*)"/
  # A file of those screens that may keep one of the refused looks, mapped to
  # the reason.
  HAND_BOX_ALLOWED = {
    "app/views/admin/media/index.html.erb" => "the drop overlay's dashed accent frame: creating is violet",
    "app/views/admin/shared/_product_wordmark.html.erb" => "the wordmark's 12px capitals, the product's mark as every layout's header draws it"
  }.freeze

  def self.type_scale_sources = TYPE_SCALE_SCREENS.flat_map { |glob| Dir[Rails.root.join(glob)] }.uniq

  # `[line number, what was refused]` for each refused look in `source`.
  def self.refused_looks(source)
    constants = source.scan(STRING_CONSTANT).to_h { |name, value| [ name, value.gsub(CONTINUED, " ") ] }
    source = source.gsub(/#\{([A-Z][A-Z0-9_]*)\}/) { constants.fetch(Regexp.last_match(1), Regexp.last_match(0)) }
    lines = source.each_line.each_with_index.filter_map { |line, index| [ index + 1, line[OFF_SCALE] ] if line.match?(OFF_SCALE) }
    boxes = source.to_enum(:scan, QUOTED).filter_map do
      match = Regexp.last_match
      classes = (match[1] || match[2]).gsub(CONTINUED, " ").split
      [ source[0...match.begin(0)].count("\n") + 1, match[0] ] if classes.include?("rounded-cs") && classes.any? { |name| name.match?(BOX_EDGE) }
    end
    (lines + boxes).sort_by(&:first)
  end

  test "the content-side screens draw no off-scale size and no hand-drawn box" do
    TYPE_SCALE_SCREENS.each { |glob| assert Dir[Rails.root.join(glob)].any?, "#{glob} matches no file: the guard looks at nothing there" }
    offences = self.class.type_scale_sources.flat_map do |path|
      relative = Pathname(path).relative_path_from(Rails.root).to_s
      next [] if HAND_BOX_ALLOWED.key?(relative)

      self.class.refused_looks(File.read(path)).map { |line, look| "#{relative}:#{line}: #{look}" }
    end
    assert_empty offences, "a size is a type token (text-small, text-body, text-label) and a box is a card's elevation"
    HAND_BOX_ALLOWED.each_key do |path|
      assert_includes self.class.type_scale_sources, Rails.root.join(path).to_s, "#{path} is allowed but is on no type-scale screen"
      assert self.class.refused_looks(Rails.root.join(path).read).any?, "#{path} draws none of the refused looks: drop it from HAND_BOX_ALLOWED"
    end
  end

  test "the off-scale check finds a pixel size, text-xs, a hand-drawn box in any order, a dashed edge and an important danger edge, and not a token, a table's line or a control's frame" do
    [ "text-[13px]", "text-xs", %(class="rounded-cs border border-line"), "border-dashed", "!border-danger",
      %(class="border border-line bg-sunken rounded-cs"), %(class="rounded-cs border hover:border-line-strong"),
      %(CARD = "block rounded-cs border " \\\n         "border-line".freeze),
      %(BASE = "block rounded-cs".freeze\nPICK = "\#{BASE} border border-line".freeze) ].each do |sample|
      assert_not_empty self.class.refused_looks(sample), sample
    end
    [ "text-small", %(class="border-b border-line"), "text-xs-foo", %(class="rounded-cs border border-field-line"),
      %(class="rounded-cs px-2" title="border-line"),
      %(BASE = "block rounded-cs".freeze\nPICK = "\#{OTHER} border border-line".freeze) ].each do |sample|
      assert_empty self.class.refused_looks(sample), sample
    end
  end

  # A triangle glued to its words reads "▾PAGE SETTINGS". A mono-label
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

  # One cap, one place. The rail's widths (the 360px rail, the 28px between
  # it and the main column, the 1680px a docked composition grows to) are
  # tokens of the same kind, beside it.
  RAIL_WIDTH_LITERAL = /(?<![\w-])(?:w|max-w|min-w|basis|gap|gap-x)-\[(?:1680|360|28)px\]|(?:max-|min-)?width:\s*(?:1680|360)px|(?:column-)?gap:\s*28px/
  RAIL_WIDTH_ALLOWED = {}.freeze

  test "the form column's width is a token: 760px and 1144px are written once, in content-spiel.css" do
    tokens = Rails.root.join("app/assets/tailwind/content-spiel.css").read
    assert_equal 1, tokens.scan("--cs-form-max: 760px;").size
    assert_equal 1, tokens.scan("--cs-form-max-pair: 1144px;").size
    assert_equal 1, tokens.scan("--cs-rail-width: 360px;").size
    assert_equal 1, tokens.scan("--cs-rail-gap: 28px;").size
    assert_equal 1, tokens.scan("--cs-content-max: 1680px;").size
    assert_equal 1, tokens.scan("--cs-text-measure: 72ch;").size
    assert_equal 1, tokens.scan("--cs-code-measure: 100ch;").size
    assert_equal 1, tokens.scan(/\b360px/).size, "360px is the token's alone in content-spiel.css"
    assert_equal 1, tokens.scan(/\b1680px/).size, "1680px is the token's alone in content-spiel.css"
    assert_no_match(/--cs-editor-column/, tokens, "the blocks column is no track of its own: it takes what the rail leaves")

    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    assert_match(/\.admin-form-column\s*\{\s*max-width:\s*var\(--cs-form-max\);\s*\}/, css)
    assert_match(/\.admin-form-column--pair\s*\{\s*max-width:\s*var\(--cs-form-max-pair\);\s*\}/, css)
    assert_match(/@container admin-pair \(min-width: 824px\)\s*\{\s*\.admin-translation-pair\s*\{\s*grid-template-columns:\s*repeat\(2, minmax\(0, 560px\)\);/m, css)
    # The media library's middle range starts at 760px of the library: a
    # container's width, not the form column's, and a container query cannot
    # read the token.
    assert_no_match(/\b(?:760|1144)px/, css.sub("@container admin-media (min-width: 760px)", ""))
    assert_empty design_offences(/\[(?:760|1144)px\]|max-width:\s*(?:760|1144)px/)

    assert_no_match(/\b(?:1680|360|28)px|\b(?:72|100)ch\b/, css)
    assert_no_match(/--cs-editor-column/, css)
    assert_empty design_offences(RAIL_WIDTH_LITERAL, except: RAIL_WIDTH_ALLOWED.keys)
    RAIL_WIDTH_ALLOWED.each_key { |path| assert_match RAIL_WIDTH_LITERAL, Rails.root.join(path).read, "#{path} does not write the width: drop its allowance" }
  end

  test "the rail width pattern matches a hard-coded column, rail or gap, and not a token or a type size" do
    [ "max-w-[1680px]", "w-[360px]", "gap-x-[28px]", "max-width: 1680px", "width: 360px", "column-gap: 28px" ].each { |sample| assert_match RAIL_WIDTH_LITERAL, sample }
    [ "max-w-(--cs-content-max)", "text-[28px]", "width: var(--cs-rail-width)", "28px 56px" ].each { |sample| assert_no_match RAIL_WIDTH_LITERAL, sample }
  end

  # A CSS block's body by its head (`@container …`, `@media …`): from the head's
  # brace to the brace that closes it, comments stripped.
  def self.css_blocks(name, head)
    css = Rails.root.join("app/assets/tailwind", name).read.gsub(%r{/\*.*?\*/}m, "")
    css.to_enum(:scan, head).map do
      start = Regexp.last_match.end(0)
      depth = 1
      finish = (start...css.size).find do |index|
        depth += 1 if css[index] == "{"
        depth -= 1 if css[index] == "}"
        depth.zero?
      end
      css[start...finish]
    end
  end

  # The editors' rail: the editor area is the container, so a folded tree or
  # a narrower content column gives the rail room the window does not show.
  # The blocks column opts in by its class, found anywhere in the grid (a
  # `display: contents` form between), and nothing else is placed in it.
  test "the rail is laid out by the editor area's container, never the window" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    assert_match(/\.admin-editor-area\s*\{\s*container:\s*admin-editor\s*\/\s*inline-size;\s*\}/, css)

    docked = self.class.css_blocks("content-spiel.tailwind.css", /@container admin-editor \(min-width: 1200px\)\s*\{/)
    assert_equal 1, docked.size, "one block docks the rail"
    grid = docked.first[/\.admin-rail-grid\s*\{([^}]*)\}/, 1]
    assert grid, "the docked grid is .admin-rail-grid"
    assert_grows_to_content_max(grid)
    assert_match(/--admin-rail-docked:\s*1;/, grid, "the controller reads the docked state from the property the query sets")
    ground = docked.first[/\.admin-rail-grid::before\s*\{([^}]*)\}/, 1]
    assert ground, "the rail's ground is the grid's ::before"
    %w[background:\s*var\(--cs-rail\) box-shadow:\s*var\(--cs-shadow-2\) border-radius:\s*var\(--cs-radius-rail\) grid-column:\s*2].each do |declaration|
      assert_match(/#{declaration};/, ground)
    end
    assert_match(/\.admin-rail-grid \.admin-rail__main\s*\{\s*grid-column:\s*1;\s*grid-row:\s*1\s*\/\s*-1;\s*\}/, docked.first)
    assert_no_match(/\.admin-rail-grid[^{,]*>\s*:not\(/, docked.first, "nothing but the marked blocks column is placed in the first column")
    %w[admin-rail__tabs admin-rail__panel admin-rail__main].each do |item|
      assert_no_match(/\.admin-rail-grid[^{,]*>\s*\.#{item}/, docked.first, "#{item} is matched anywhere in the grid, not only as a child")
    end
    assert_match(/\.admin-rail-grid \.admin-form-column\s*\{\s*max-width:\s*none;\s*\}/, docked.first, "the blocks column takes its track whole")
    assert_match(/\.admin-rail-grid\s*\{[^}]*--admin-rail-docked:\s*0;[^}]*grid-template-columns:\s*minmax\(0, 1fr\);/, css, "one column below the threshold")

    medias = self.class.css_blocks("content-spiel.tailwind.css", /@media[^{]*\{/)
    assert medias.any?, "the stylesheet's @media blocks were found"
    assert_empty medias.select { |body| body.include?("admin-rail") }, "no window media query lays out the rail"
  end

  # A row's people narrow by the width of a container, never the window's:
  # a tree row by its own (the next test), a posts row by its list's. The
  # tree's column is no container: a column under 260px has every row under
  # the row's rule, so a column rule could never show.
  test "a row's people narrow by the row's own width, never the window" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    assert_no_match(/container:\s*admin-tree-column|@container admin-tree-column/, css, "the tree's people are decided by the row alone")
    blocks = self.class.css_blocks("content-spiel.tailwind.css", /@container admin-list \(max-width: 639px\)\s*\{/)
    assert_equal 1, blocks.size, "one @container admin-list (max-width: 639px) block"
    assert_includes blocks.first, "[data-presence-more-narrow] { display: flex; }"
    assert_includes blocks.first, "[data-presence-more] { display: none; }"
    windowed = self.class.css_blocks("content-spiel.tailwind.css", /@media[^{]*\{/).select { |body| body.include?("admin-presence-marker") }
    assert_empty windowed, "a row's people are asked of a container, not an @media block"
  end

  # Two letters reach about 19px into a 22px circle, so a circle over the one
  # before covers its second letter: a stack's circles stand apart, and with
  # nothing overlapping no ring separates them.
  test "an avatar stack never overlaps and draws no ground ring" do
    # A file that renders a circle writes no negative start margin anywhere
    # in it: the classes of a stack's slots are often built apart from the
    # render (a `circle_class` method, a sibling component file).
    stacks = Dir[Rails.root.join("app/components/**/*.{rb,erb}")].select { |path| File.read(path).include?("AvatarComponent.new") }
    stacks = stacks.flat_map { |path| [ path, *Dir[path.sub(/\.(html\.erb|rb)\z/, ".{rb,html.erb}")] ] }.uniq
    assert stacks.any? { |path| path.end_with?("people_component.rb") }, "the stacks' files are read"
    overlapping = stacks.flat_map do |path|
      self.class.without_comments(path).lines.each_with_index.filter_map do |line, index|
        "#{path.delete_prefix("#{Rails.root}/")}:#{index + 1}" if line.match?(/(?<![\w-])-m[ls]-/)
      end
    end
    assert_empty overlapping, "a circle never stands over the one before it (a negative start margin in a file that draws circles)"
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    marker_rules = css.scan(/[^{}]*\.admin-presence-marker[^{}]*\{[^}]*\}/)
    assert marker_rules.any?, "the marker's rules are read"
    assert_empty marker_rules.grep(/margin(?:-inline-start|-left|-inline)?:[^;]*-\d/), "a marker's circles never overlap"
    grounds = Dir[Rails.root.join("app/**/*.{rb,erb,js,css}")].reject { |path| path.include?("/app/assets/builds/") }.select { |path| File.read(path).include?("--admin-avatar-ground") }
    assert_empty grounds, "no ring in the colour of a stack's ground: nothing overlaps to be separated"
    marker = Rails.root.join("app/components/admin/ui/presence_marker_component.html.erb").read
    assert_includes marker, "inline-flex flex-none items-center gap-0.5", "the marker's parts stand 2px apart"
  end

  # The title is as wide as its words (the state mark stands 6px after them),
  # and what keeps it from being cut by its markers is the presence marker
  # stepping down to one circle where the row is short: one person's own, or
  # the count from two. Presence never gives way to nothing.
  test "a tree row's title keeps its words' width and the marker gives way to one circle under 240px of the row: one person's own, or the count from two" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    assert_match(/\.admin-tree-row\s*\{[^}]*container:\s*admin-tree-row\s*\/\s*inline-size;/, css)
    assert_match(/\.admin-tree-row__title\s*\{[^}]*flex:\s*0 1 auto;[^}]*min-width:\s*0;/, css)
    assert_match(/\.admin-tree-row__trailing\s*\{[^}]*flex:\s*none;/, css, "the markers do not shrink")
    assert_includes css, ".admin-tree-row__title:has(+ :is(.admin-tree-row__trailing, .admin-tree-row__add)),\n.admin-tree-row__state:has(+ :is(.admin-tree-row__trailing, .admin-tree-row__add)) { margin-inline-end: 6px; }",
      "on a full row the auto margin is 0, so the title's own 6px keeps its ellipsis off the markers"
    assert_match(/\.admin-presence-marker > :is\(\[data-presence-more-narrow\], \[data-presence-total\]\)\s*\{\s*display:\s*none;\s*\}/, css, "the count circle rests hidden")
    blocks = self.class.css_blocks("content-spiel.tailwind.css", /@container admin-tree-row \(max-width: 239\.98px\)\s*\{/)
    assert_equal 1, blocks.size, "one row rule"
    assert_includes blocks.first, ".admin-presence-marker > :is([data-presence-avatar] ~ [data-presence-avatar], [data-presence-more], [data-presence-more-narrow]) { display: none; }"
    assert_includes blocks.first, '.admin-presence-marker:not([data-presence-count="1"]) > [data-presence-avatar] { display: none; }', "one person keeps their first circle"
    assert_includes blocks.first, '.admin-presence-marker:not([data-presence-count="1"]) > [data-presence-total] { display: flex; }', "two and more are the count circle"
    assert_no_match(/data-presence-marker-label|data-tooltip|\.admin-presence-marker\s*\{/, blocks.first, "the words and the tooltip stay, and so does the marker")
    assert_no_match(/admin-tree-row__title\s*\{[^}]*7rem/, css)
  end

  # The docked rail's ground is as tall as the tabs and the
  # current panel, never the blocks column, and the three stick under the
  # editor's header; a panel taller than the window scrolls inside itself.
  test "the rail's ground spans the tabs' and the panel's rows only, and the rail sticks under the header" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    assert_match(/\.admin-rail-grid\s*\{[^}]*--admin-rail-top:\s*calc\(var\(--admin-top-offset\) \+ var\(--admin-editor-header-height, 0px\) \+ var\(--admin-editor-header-gap\)\);/, css, "one top for every rail item, from the header's measured height and its gap")
    assert_equal 1, css.scan(/--admin-editor-header-gap:\s*1\.5rem;/).size, "the header's gap is written once"
    assert_includes Rails.root.join("app/components/admin/editor_screen/header_component.html.erb").read, "mb-(--admin-editor-header-gap)", "the header's margin is the gap"
    docked = self.class.css_blocks("content-spiel.tailwind.css", /@container admin-editor \(min-width: 1200px\)\s*\{/).first
    grid = docked[/\.admin-rail-grid\s*\{([^}]*)\}/, 1]
    assert_match(/grid-template-rows:\s*auto auto 1fr;/, grid, "the tabs, the panel, then a row that takes the canvas's remaining height")
    ground = docked[/\.admin-rail-grid::before\s*\{([^}]*)\}/, 1]
    assert_match(%r{grid-row:\s*1\s*/\s*3;}, ground, "the ground spans the tabs' and the panel's rows only")
    assert_no_match(%r{grid-row:\s*1\s*/\s*-1}, ground)
    assert_match(/position:\s*sticky;\s*top:\s*var\(--admin-rail-top\);/, ground)
    tabs = docked[/\.admin-rail-grid :is\(\.admin-rail__tabs, \.admin-rail__heading\)\s*\{([^}]*)\}/, 1]
    assert tabs, "the tabs and a one-tab rail's heading stick alike"
    %w[position:\s*sticky top:\s*var\(--admin-rail-top\) height:\s*var\(--admin-rail-tabs-height\)].each { |declaration| assert_match(/#{declaration};/, tabs) }
    panel = docked[/\.admin-rail-grid \.admin-rail__panel\s*\{([^}]*)\}/, 1]
    [ 'position:\s*sticky', 'top:\s*calc\(var\(--admin-rail-top\) \+ var\(--admin-rail-tabs-height\)\)', 'align-self:\s*start',
      'max-height:\s*calc\(100dvh - var\(--admin-rail-top\) - var\(--admin-rail-tabs-height\) - var\(--cs-sp-4\)\)', 'overflow-y:\s*auto' ].each do |declaration|
      assert_match(/#{declaration};/, panel)
    end
    # The notes are as tall as the panel may be and scroll their own list.
    assert_match(/\.admin-rail__panel:has\(> \.admin-notes-drawer\)\s*\{[^}]*overflow:\s*visible;/, docked)
    assert_match(/\.admin-notes-drawer\s*\{[^}]*height:\s*calc\(100dvh - var\(--admin-rail-top\) - var\(--admin-rail-tabs-height\) - var\(--cs-sp-4\)\);/m, docked)
    # The header's height is measured by the rail, the one writer.
    writers = Dir[Rails.root.join("app/javascript/**/*.js")].select { |path| File.read(path).match?(/setProperty\(\s*["']--admin-editor-header-height/) }
    assert_equal [ "app/javascript/controllers/admin/ui/rail_controller.js" ], writers.map { |path| Pathname(path).relative_path_from(Rails.root).to_s }
  end

  # Design System: a filter bar is 38px, set by the bar, never by a control.
  test "the filter bar's height is a token written once, and the bar sets it as a minimum, never a group height" do
    tokens = Rails.root.join("app/assets/tailwind/content-spiel.css").read
    assert_equal 1, tokens.scan("--cs-control-compact: 2.375rem;").size

    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    assert_match(/\.admin-filter-bar input:not\(\.sr-only\),.*?min-height:\s*var\(--cs-control-compact\);\s*padding-block:\s*0;/m, css)
    assert_no_match(/\.admin-filter-bar fieldset label/, css, "a segmented control is the bar's height by its own track, never by the bar")
    assert_includes css, ".admin-filter-bar a.inline-flex:not(.admin-chip__remove, .admin-segmented a)", "a segmented control's links are not sized by the bar's link rule"
    assert_no_match(/\.admin-filter-bar[^{,]*\.admin-segmented(?! a\))/, css, "no rule of the bar names the segmented control but to leave it out")
    assert_includes Admin::Ui::SegmentedComponent::TRACK_CLASS.split, "admin-segmented"
    assert_match(/\.admin-filter-bar select,\s*\.admin-filter-panel select,.*?min-height:\s*var\(--cs-control-compact\);/m, css, "a filter panel's selects are the bar's height")
    assert_no_match(/\b38px|2\.375rem/, css)

    assert_includes File.read(Rails.root.join("app/helpers/admin/filter_helper.rb")), "admin-filter-bar mb-4 flex flex-wrap items-start gap-3"
    public_css = Dir[Rails.root.join("app/assets/tailwind/themes/**/*.css")].sum("") { |f| File.read(f) }
    assert_no_match(/cs-control-compact|admin-filter-bar/, public_css, "nothing of CS Studio's reaches the public stylesheet")
  end

  # The dashboard's main column and its "At a glance" rail: laid out by the
  # dashboard's own width (the sidebar and the tree take room the window does
  # not show), never a window media query, docked on the editors' rail tokens.
  test "the dashboard's main column and rail are laid out by the dashboard's container, from the rail's tokens" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    assert_match(/\.admin-dashboard\s*\{\s*container:\s*admin-dashboard\s*\/\s*inline-size;\s*\}/, css)
    assert_match(/\.admin-dashboard__grid\s*\{\s*display:\s*grid;\s*grid-template-columns:\s*minmax\(0, 1fr\);\s*row-gap:\s*1\.5rem;\s*\}/, css, "one column below the threshold")
    assert_match(/\.admin-dashboard__main\s*\{\s*container:\s*admin-dashboard-main\s*\/\s*inline-size;/, css)

    docked = self.class.css_blocks("content-spiel.tailwind.css", /@container admin-dashboard \(min-width: 1200px\)\s*\{/)
    assert_equal 1, docked.size, "one block docks the dashboard's rail"
    grid = docked.first[/\.admin-dashboard__grid\s*\{([^}]*)\}/, 1]
    assert grid, "the docked block lays out .admin-dashboard__grid"
    assert_grows_to_content_max(grid)
    assert_match(/\.admin-dashboard__head,\s*\.admin-dashboard__notice\s*\{\s*max-width:\s*var\(--cs-content-max\);\s*margin-inline:\s*auto;\s*\}/, docked.first, "the heading row and the mail notice stop with the composition")
    tiles = self.class.css_blocks("content-spiel.tailwind.css", /@container admin-dashboard-main \(min-width: 64rem\)\s*\{/)
    assert_equal 1, tiles.size, "the draft tiles take a fourth column from 64rem of the main column"
    assert_match(/\.admin-draft-tiles\s*\{\s*grid-template-columns:\s*repeat\(4, minmax\(0, 1fr\)\);\s*\}/, tiles.first)
    rail = docked.first[/\.admin-dashboard__rail\s*\{([^}]*)\}/, 1]
    assert rail, "the docked block grounds .admin-dashboard__rail"
    %w[background:\s*var\(--cs-rail\) box-shadow:\s*var\(--cs-shadow-2\) border-radius:\s*var\(--cs-radius-rail\)].each do |declaration|
      assert_match(/#{declaration};/, rail)
    end

    medias = self.class.css_blocks("content-spiel.tailwind.css", /@media[^{]*\{/)
    assert medias.any?, "the stylesheet's @media blocks were found"
    assert_empty medias.select { |body| body.include?("admin-dashboard") }, "no window media query lays out the dashboard"
    sources = [ "app/views/admin/dashboard/show.html.erb", *Dir[Rails.root.join("app/components/admin/dashboard_screen/*").to_s] ]
    assert_empty sources.select { |path| Rails.root.join(path).read.include?("auto-fit") }, "the dashboard's columns are counted, never auto-fit"
    assert_no_match(/auto-fit/, css)
  end

  # The lists' rail (the posts list's filters, the Tags screen's detail):
  # laid out by the list's own width, never a window media query, docked on
  # the editors' rail tokens. Its rail is matched anywhere in the grid, since
  # the posts panel stands inside a `display: contents` form.
  test "the lists' rail is laid out by the list's own container, from the rail's tokens" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    assert_match(/\.admin-list-rail\s*\{\s*container:\s*admin-list\s*\/\s*inline-size;\s*\}/, css)
    assert_match(/\.admin-list-rail__grid\s*\{\s*display:\s*grid;\s*grid-template-columns:\s*minmax\(0, 1fr\);\s*\}/, css, "one column below the threshold")

    docked = self.class.css_blocks("content-spiel.tailwind.css", /@container admin-list \(min-width: 1200px\)\s*\{/)
    assert_equal 1, docked.size, "one block docks the lists' rail"
    grid = docked.first[/\.admin-list-rail__grid\s*\{([^}]*)\}/, 1]
    assert grid, "the docked block lays out .admin-list-rail__grid"
    assert_grows_to_content_max(grid)
    assert_match(/grid-template-rows:\s*auto 1fr;/, grid, "a rail taller than the bar grows the list's row, never the bar's")
    rail = docked.first[/\.admin-list-rail__rail\s*\{([^}]*)\}/, 1]
    assert rail, "the docked block grounds .admin-list-rail__rail"
    %w[background:\s*var\(--cs-rail\) box-shadow:\s*var\(--cs-shadow-2\) border-radius:\s*var\(--cs-radius-rail\) grid-column:\s*2 grid-row:\s*1\s*/\s*span\s*2].each do |declaration|
      assert_match(/#{declaration};/, rail)
    end
    [ 'position:\s*sticky', 'top:\s*calc\(var\(--admin-top-offset\) \+ var\(--cs-sp-4\)\)',
      'max-height:\s*calc\(100dvh - var\(--admin-top-offset\) - 2 \* var\(--cs-sp-4\)\)', 'overflow-y:\s*auto' ].each do |declaration|
      assert_match(/#{declaration};/, rail, "docked, the list's rail sticks and scrolls inside itself")
    end
    assert_no_match(/>\s*\.admin-list-rail__rail/, css, "the rail is matched anywhere in the grid, not only as a child")
    assert_match(/\.admin-list-rail__head\s*\{[^}]*max-width:\s*var\(--cs-content-max\);/, docked.first, "the heading row stops with the composition")
    # The Tags screen's detail docks in the same block: shown with its empty
    # line, and on the rail's ground through `.admin-list-rail__rail`, which
    # stands after its card rule and so wins on order.
    assert_match(/\.admin-tag-detail:has\(\[data-tag-detail-empty\]\)\s*\{\s*display:\s*block;\s*\}/, docked.first, "docked, the empty line is shown")
    assert_match(/\.admin-notes-threads\s*\{[^}]*margin-top:\s*0/, docked.first, "docked, the open threads' rail sits at the grid's top")
    row = Rails.root.join("app/components/admin/notes_screen/open_thread_row_component.html.erb").read
    assert_includes row, "hover:bg-paper motion-reduce", "the rail's row takes the paper hover"
    assert_includes row, "-mx-2 flex min-w-0 items-center gap-2.5 rounded-tile px-2 py-1.5", "the fill is on the row's own padding"
    assert_includes row, "transition-colors duration-120 ease-(--cs-ease) hover:bg-paper"
    assert_includes row, "motion-reduce:transition-none"
    outside = css.sub(docked.first, "")
    assert_match(/\.admin-tag-detail:has\(\[data-tag-detail-empty\]\)\s*\{\s*display:\s*none;\s*\}/, outside, "below the threshold an unchosen rail takes no room")
    card = outside.index(/\.admin-tag-detail\s*\{[^}]*background:\s*var\(--cs-surface\)/)
    assert card, "below the threshold the detail is a card"
    assert_operator card, :<, css.index(docked.first), "the card rule stands before the docked block, so the rail's ground wins"
    threads_card = outside.index(/\.admin-notes-threads\s*\{[^}]*margin-top:\s*1rem[^}]*background:\s*var\(--cs-surface\)/)
    assert threads_card, "below the threshold the open threads' rail is a card after the list"
    assert_operator css.index(/\.admin-notes-threads\s*\{/), :<, css.index(docked.first), "its card rule stands before the docked block"

    medias = self.class.css_blocks("content-spiel.tailwind.css", /@media[^{]*\{/)
    assert medias.any?, "the stylesheet's @media blocks were found"
    assert_empty medias.select { |body| body.include?("admin-list-rail") }, "no window media query lays out the lists' rail"
  end

  # Settings' "At a glance" rail: laid out by the Settings area's own width,
  # never a window media query, docked on the rail's tokens. Below the
  # threshold the grid's areas put it above the cards, a compact card; the
  # nav's window rule changes the grid's columns and areas and names no
  # part of it.
  test "Settings' rail is laid out by the Settings area's own container, from the rail's tokens" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    assert_match(/\.admin-settings-layout\s*\{\s*container:\s*admin-settings\s*\/\s*inline-size;\s*\}/, css)
    grid = css[/\.admin-settings-layout__grid\s*\{([^}]*)\}/, 1]
    assert grid, "the grid's own rule"
    assert_match(/grid-template-columns:\s*minmax\(0, 1fr\);/, grid, "one column below the window's 1024px")
    assert_match(/grid-template-areas:\s*"nav" "glance" "cards";/, grid, "the nav, the rail, then the cards")
    assert_match(/column-gap:\s*var\(--cs-rail-gap\);/, grid)
    assert_match(/\.admin-settings-glance\s*\{[^}]*grid-area:\s*glance;/, css)
    card = css[/\.admin-settings-glance\s*\{([^}]*)\}/, 1]
    %w[background:\s*var\(--cs-surface\) box-shadow:\s*var\(--cs-shadow-1\) border-radius:\s*var\(--cs-radius-card\)].each do |declaration|
      assert_match(/#{declaration};/, card, "below the threshold the rail is a compact card")
    end

    window = self.class.css_blocks("content-spiel.tailwind.css", /@media \(min-width: 1024px\)\s*\{/).select { |body| body.include?("admin-settings") }
    assert_equal 1, window.size, "one window rule places the nav beside the cards"
    assert_match(/\A\s*\.admin-settings-layout__grid\s*\{[^}]*\}\s*\z/, window.first, "the window rule names the grid alone")
    assert_match(/grid-template-columns:\s*170px minmax\(0, var\(--cs-form-max\)\);/, window.first)
    assert_match(/grid-template-areas:\s*"nav glance" "nav cards";/, window.first, "the nav spans both rows; the rail stands above the cards")

    docked = self.class.css_blocks("content-spiel.tailwind.css", /@container admin-settings \(min-width: 1200px\)\s*\{/)
    assert_equal 1, docked.size, "one block docks Settings' rail"
    docked_grid = docked.first[/\.admin-settings-layout__grid\s*\{([^}]*)\}/, 1]
    assert docked_grid, "the docked block lays out the grid"
    assert_match(/grid-template-columns:\s*170px minmax\(0, var\(--cs-form-max\)\) var\(--cs-rail-width\);/, docked_grid, "the cards' column narrows as the area does; the rail keeps its width")
    assert_match(/grid-template-areas:\s*"nav cards glance";/, docked_grid)
    assert_no_match(/justify-content/, docked_grid, "spare width below the max falls right of the rail")
    rail = docked.first[/\.admin-settings-glance\s*\{([^}]*)\}/, 1]
    assert rail, "the docked block grounds the rail"
    [ 'background:\s*var\(--cs-rail\)', 'box-shadow:\s*var\(--cs-shadow-2\)', 'border-radius:\s*var\(--cs-radius-rail\)', 'position:\s*sticky',
      'top:\s*calc\(var\(--admin-top-offset\) \+ var\(--cs-sp-4\)\)', 'max-height:\s*calc\(100dvh - var\(--admin-top-offset\) - 2 \* var\(--cs-sp-4\)\)',
      'overflow-y:\s*auto' ].each do |declaration|
      assert_match(/#{declaration};/, rail, "docked, the rail is on the rail's ground, sticks and scrolls inside itself")
    end
    outside = css.sub(docked.first, "")
    assert_operator outside.index(/\.admin-settings-glance\s*\{/), :<, css.index(docked.first), "the card rule stands before the docked block, so the rail's ground wins"
    assert_equal 1, outside.scan(/\.admin-settings-glance\b/).size, "outside the docked block only the rail's own rule names it"

    medias = self.class.css_blocks("content-spiel.tailwind.css", /@media[^{]*\{/)
    assert medias.any?, "the stylesheet's @media blocks were found"
    assert_empty medias.select { |body| body.include?("admin-settings-glance") }, "no window media query lays out Settings' rail"
    view = Rails.root.join("app/views/admin/settings/show.html.erb").read
    assert_no_match(/\b(?:lg|xl|2xl):(?:grid|col|row)/, view, "the view leaves the grid to the stylesheet")
  end

  # The Media screen's rail: laid out by the library's own width, never a
  # window media query. Below 760px one column, the rail a card under the
  # grid; from 760px the card beside it at 340px, sticky; docked at the one
  # threshold on the rail's ground, with the tabs shown and one panel.
  test "the Media screen's panel is laid out by the library's own width, never a window media query" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    assert_match(/\.admin-media-library\s*\{\s*container:\s*admin-media\s*\/\s*inline-size;\s*\}/, css)
    assert_match(/\.admin-media-library__grid\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\);/, css, "one column in a narrow library")
    card = css[/\.admin-media-rail\s*\{([^}]*)\}/, 1]
    %w[background:\s*var\(--cs-surface\) box-shadow:\s*var\(--cs-shadow-1\) border-radius:\s*var\(--cs-radius-card\)].each do |declaration|
      assert_match(/#{declaration};/, card, "below the threshold the rail is a card")
    end

    middle = self.class.css_blocks("content-spiel.tailwind.css", /@container admin-media \(min-width: 760px\)\s*\{/)
    assert_equal 1, middle.size
    assert_match(/\.admin-media-library__grid\s*\{\s*grid-template-columns:\s*minmax\(0, 1fr\) 340px;\s*\}/, middle.first, "from 760px the card stands 340px beside the grid")
    assert_match(/\.admin-media-rail\s*\{[^}]*position:\s*sticky;[^}]*overflow-y:\s*auto;/, middle.first, "and sticks, scrolling inside itself")
    assert_no_match(/admin-rail__tabs/, middle.first, "the card has no tabs")

    docked = self.class.css_blocks("content-spiel.tailwind.css", /@container admin-media \(min-width: 1200px\)\s*\{/).first
    rail = docked[/(?:\A|[};])\s*\.admin-media-rail\s*\{([^}]*)\}/, 1]
    assert rail, "the docked block grounds the rail"
    [ '--admin-rail-docked:\s*1', 'background:\s*var\(--cs-rail\)', 'box-shadow:\s*var\(--cs-shadow-2\)', 'border-radius:\s*var\(--cs-radius-rail\)' ].each do |declaration|
      assert_match(/#{declaration};/, rail, "docked, the rail is on the rail's ground and says it is docked")
    end
    assert_match(/\.admin-media-rail \.admin-rail__tabs\s*\{\s*display:\s*flex;/, docked, "docked, the tabs are shown")
    assert_match(/\.admin-media-rail \.admin-rail__panel:not\(\[data-current\]\)\s*\{\s*display:\s*none;\s*\}/, docked, "docked, one panel is shown")
    assert_match(/\.admin-media-rail__section-heading\s*\{\s*display:\s*none;\s*\}/, docked, "docked, the tab names the notes and their heading goes")
    assert_match(/\.admin-media-rail__close\s*\{[^}]*position:\s*absolute;[^}]*top:[^}]*right:/, css, "Close stands over the rail's top-right corner")

    medias = self.class.css_blocks("content-spiel.tailwind.css", /@media[^{]*\{/)
    assert medias.any?, "the stylesheet's @media blocks were found"
    assert_empty medias.select { |body| body.include?("admin-media") }, "no window media query lays out the Media screen"
    view = Rails.root.join("app/views/admin/media/index.html.erb").read
    assert_no_match(/\blg:/, view, "the view leaves the layout to the library's container")
  end

  # The Tags list's usage bar takes the structure hue through a token of its
  # own, as a tag's square on the canvas does, so it can change without
  # moving the icons; the bar is drawn in one place.
  test "the usage bar is the structure hue, as a token of its own" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.css").read.gsub(%r{/\*.*?\*/}m, "")
    light = css[/:root, \[data-theme="light"\]\s*\{(.*?)\}/m, 1]
    dark = css[/\[data-theme="dark"\]\s*\{(.*?)\}/m, 1]
    [ light, dark ].each { |block| assert_equal 1, block.scan("--cs-tag-usage: var(--cs-ic-structure);").size }
    assert_match(/--color-tag-usage:\s*var\(--cs-tag-usage\);/, Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read)

    users = Dir[Rails.root.join("app/{views,components,helpers,javascript}/**/*.{erb,rb,js}")].select { |path| File.read(path).include?("bg-tag-usage") }
    assert_equal [ "app/views/admin/tags/index.html.erb" ], users.map { |path| Pathname(path).relative_path_from(Rails.root).to_s }
    tailwind = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    assert_match(/\.admin-tag-usage__bar\s*\{[^}]*width:\s*calc\(var\(--usage\) \* 100%\);/, tailwind)
    assert_match(/\.admin-tag-usage\s*\{[^}]*height:\s*4px;[^}]*background:\s*var\(--cs-paper\);/, tailwind)
  end

  # The one rule for spare width: a docked composition is a
  # main column that takes what the rail leaves and the rail at its right,
  # the whole stopping at `--cs-content-max` and centred past it by its
  # auto inline margins (0 below the cap, so at the content's left edge
  # there); no `justify-content` of its own, so the grid's tracks start at
  # its own left edge.
  def assert_grows_to_content_max(grid)
    assert_match(/grid-template-columns:\s*minmax\(0, 1fr\) var\(--cs-rail-width\);/, grid, "the main column takes what the rail leaves")
    assert_match(/column-gap:\s*var\(--cs-rail-gap\);/, grid)
    assert_centres_past_content_max(grid)
    assert_no_match(/justify-content/, grid, "the tracks start at the composition's own left edge")
  end

  def assert_centres_past_content_max(rule, what = "the composition")
    assert_match(/max-width:\s*var\(--cs-content-max\);/, rule, "#{what} grows to the content max and no further")
    assert_match(/margin-inline:\s*auto;/, rule, "#{what} is centred past the content max")
  end

  # Design System v122: past the cap the spare width is split evenly either
  # side, for every docked composition and the head row over it, and only
  # inside its docked rule: undocked, nothing centres (a one-column screen
  # stays at the left under its heading). Written here, never as `mx-auto`
  # in a view ("nothing inside CS Studio is centred…").
  test "every docked composition and its head row centre past --cs-content-max" do
    { "admin-editor" => [ ".admin-rail-grid" ],
      "admin-dashboard" => [ ".admin-dashboard__grid", ".admin-dashboard__head,\n  .admin-dashboard__notice" ],
      "admin-list" => [ ".admin-list-rail__head", ".admin-list-rail__grid" ],
      "admin-settings" => [ ".admin-settings-layout__grid" ],
      "admin-media" => [ ".admin-media-library__head", ".admin-media-library__grid" ] }.each do |container, selectors|
      docked = self.class.css_blocks("content-spiel.tailwind.css", /@container #{container} \(min-width: 1200px\)\s*\{/).first
      selectors.each do |selector|
        rule = docked[/(?:\A|[};])\s*#{Regexp.escape(selector)}\s*\{([^}]*)\}/, 1]
        assert rule, "#{container}'s docked block lays out #{selector}"
        assert_centres_past_content_max(rule, selector)
      end
    end

    # The editor's header row over the docked rail: each of its rows, held
    # to the grid's box; the header itself keeps the window's width.
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    header = css[/\.admin-editor-header:has\(~ \.admin-editor-area \[data-rail-docked\]\) > \*,\s*\.admin-editor-area:has\(\[data-rail-docked\]\) \.admin-editor-header > \*\s*\{([^}]*)\}/, 1]
    assert header, "the page's header (the editor area's sibling) and the post's (inside it) are held to the docked grid"
    assert_centres_past_content_max(header, "the editor's header row")

    # Undocked nothing centres: no rule outside a docked block carries an
    # auto inline margin but the header's, which applies only while docked.
    outside = %w[admin-editor admin-dashboard admin-list admin-settings admin-media].reduce(css) do |rest, container|
      self.class.css_blocks("content-spiel.tailwind.css", /@container #{container} \(min-width: 1200px\)\s*\{/).reduce(rest) { |text, block| text.sub(block, "") }
    end
    assert_equal 1, outside.scan(/margin-inline:\s*auto/).size, "only the docked header row centres outside a docked block"
  end

  test "every docked composition grows to --cs-content-max from the rail's tokens, at the one threshold" do
    { "admin-editor" => /\.admin-rail-grid\s*\{([^}]*)\}/,
      "admin-dashboard" => /\.admin-dashboard__grid\s*\{([^}]*)\}/,
      "admin-list" => /\.admin-list-rail__grid\s*\{([^}]*)\}/,
      "admin-media" => /\.admin-media-library__grid\s*\{([^}]*)\}/ }.each do |container, rule|
      docked = self.class.css_blocks("content-spiel.tailwind.css", /@container #{container} \(min-width: 1200px\)\s*\{/)
      assert_equal 1, docked.size, "one block docks #{container}"
      grid = docked.first[rule, 1]
      assert grid, "#{container}'s docked grid"
      assert_grows_to_content_max(grid)
    end
  end

  # Inside the editor's grown blocks column a field of running text keeps a
  # measure and a wide block takes the column. The measure is on the field's
  # wrapper, so its label, help and error lines share it.
  test "a field of running text in the editor is capped at --cs-text-measure, the Code field at --cs-code-measure, and no wide block carries a measure" do
    docked = self.class.css_blocks("content-spiel.tailwind.css", /@container admin-editor \(min-width: 1200px\)\s*\{/).first
    field = '\.admin-rail-grid \.admin-rail__main :is\(\.admin-column, \.admin-field\)'
    assert_match(/#{field}\s*\{\s*max-width:\s*var\(--cs-text-measure\);\s*\}/, docked, "a field of running text keeps the text measure")
    assert_match(/#{field}:has\(\.admin-code-input\)\s*\{\s*max-width:\s*var\(--cs-code-measure\);\s*\}/, docked, "the Code field keeps the code measure")
    wide = docked[/#{field}:is\(([^{]*)\)\s*\{\s*max-width:\s*none;\s*\}/, 1]
    assert wide, "the wide fields take the column"
    [ '[data-controller~="admin--media--field"]', ".admin-rich-text-table", ".admin-groups-field" ].each { |hook| assert_includes wide, hook }
    assert_includes Admin::Fields::CodeField.instance_method(:input_class).source_location.then { |file, _| File.read(file) }, "admin-code-input"

    # The measure is the fields' alone: no wide part of the editor names it.
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    users = css.scan(/([^{}]*)\{[^}]*var\(--cs-(?:text|code)-measure\)[^}]*\}/).flatten.map(&:strip)
    pair_half = ".admin-rail-grid .admin-rail__main .admin-translation-pair > *"
    assert_equal 3, users.size, "the two measures are read by the two field rules and a pair's half alone: #{users.inspect}"
    assert_includes users, pair_half, "a translation pair's halves keep the text measure"
    (users - [ pair_half ]).each { |selector| assert_match(/\A#{field}/, selector) }
    assert_match(/#{field}:has\(> \.admin-translation-pair\)\s*\{\s*max-width:\s*none;\s*\}/, docked, "a field holding a pair takes the column, its halves keep the measure")
    %w[admin-block-card admin-section-card admin-section-lanes admin-rich-text-table admin-groups-field].each do |wide_part|
      assert_no_match(/\.#{wide_part}[^{]*\{[^}]*-measure/, css, "#{wide_part} carries no measure")
    end
    # Nothing under the editor's grid caps a block card or a section frame by width.
    assert_no_match(/\.(?:admin-block-card|admin-section-card|admin-section-lanes)[^{]*\{[^}]*max-width/, css, "a wide block takes the column")
  end

  # THE POST FORM HOLDS NO SIZE CONTAINER. Docked, `form#post-form` is
  # `display: contents`, and Chrome drops the layout of a size container's
  # content under such an ancestor once a stream replaces a node inside it
  # (the autosave's error slots): the post's title, address and body
  # collapse to nothing. So no stylesheet rule and no `@container` utility
  # may make a container of anything the post form or the components inside
  # it draw. The classes are read from those sources (`POST_FORM_SOURCES`),
  # and a rule is matched by the classes of its selector's subject, the last
  # compound, or, when the subject names no class (`> *`, a tag, an
  # attribute), by the classes of the compounds before it: whatever stands
  # under a post-form class is inside the form. The form's own
  # `.admin-translation-form` is the one exception, and only as the subject:
  # it is the contents element, no box and no container while docked. The
  # sources hold no `@container` utility and no arbitrary `[container…]` one.
  POST_FORM_SOURCES = [
    "app/components/admin/editor_screen/post_form_component.html.erb",
    "app/components/admin/columns/*", "app/components/admin/fields/*",
    "app/components/admin/ui/{field,chip_input,rail_panel,word_diff,prefix_input,translate_all,translate_button}_component.*",
    "app/components/admin/editor_screen/{related_posts,shared_fields,reference_card}_component.*",
    "app/components/admin/translation_screen/suggestion_component.*",
    "app/views/admin/shared/{_translation_box,_field_errors,_base_updated_at_field,_override_field}.html.erb",
    "app/javascript/rich_text/*.js", "app/javascript/controllers/admin/rich_text/*.js"
  ].freeze
  POST_FORM_CONTAINER_ALLOWED = {
    "admin-translation-form" => "the post form itself: display: contents while docked, so no box and no container there"
  }.freeze
  CONTAINER_UTILITY = /(?<![\w-])@container(?:\/[\w-]+)?(?![\w-])|\[container(?:-type)?:/
  CONTAINER_DECLARATION = /(?:\A|[;{\s])container(?:-type)?\s*:(?!\s*(?:none|normal)\b)\s*[^;}]+/

  def self.post_form_classes
    Dir[*POST_FORM_SOURCES.map { |glob| Rails.root.join(glob).to_s }].flat_map { |path| File.read(path).scan(/(?<![\w-])(?:admin-[a-z0-9_-]*[a-z0-9]|ProseMirror|tiptap)(?![\w-])/) }.uniq
  end

  # Each `[selector, classes of its subject, classes of the compounds before
  # it]` of a rule that makes a size container.
  def self.container_subjects(css)
    css.gsub(%r{/\*.*?\*/}m, "").scan(/([^{}]+)\{([^{}]*)\}/).select { |_, body| body.match?(CONTAINER_DECLARATION) }.flat_map do |selectors, _|
      selectors.split(",").map(&:strip).map do |selector|
        compounds = selector.split(/\s+|>|~|\+/).reject(&:empty?)
        classes = ->(parts) { parts.flat_map { |part| part.scan(/\.([\w-]+)/).flatten } }
        [ selector, classes.([ compounds.last.to_s ]), classes.(compounds[0...-1]) ]
      end
    end
  end

  # Whether a container rule's subject is something the post form draws.
  def self.post_form_container?(subject, earlier, classes)
    ((subject & classes) - POST_FORM_CONTAINER_ALLOWED.keys).any? || (subject.empty? && (earlier & classes).any?)
  end

  test "nothing the post form draws is a size container" do
    classes = self.class.post_form_classes
    %w[admin-post-main admin-field admin-column admin-translation-pair admin-rich-text-content ProseMirror admin-rail__panel].each { |name| assert_includes classes, name, "the sources hold #{name}" }
    sheets = Dir[Rails.root.join("app/assets/tailwind/*.css"), Rails.root.join("app/assets/stylesheets/*.css")]
    offences = sheets.flat_map do |path|
      self.class.container_subjects(File.read(path)).filter_map do |selector, subject, earlier|
        "#{Pathname(path).relative_path_from(Rails.root)}: #{selector}" if self.class.post_form_container?(subject, earlier, classes)
      end
    end
    assert_empty offences, "a size container inside the post form collapses its fields in Chrome after an autosave"
    utilities = Dir[*POST_FORM_SOURCES.map { |glob| Rails.root.join(glob).to_s }].select { |path| File.read(path).match?(CONTAINER_UTILITY) }
    assert_empty utilities, "no Tailwind @container or [container…] utility in the post form's sources"
    POST_FORM_CONTAINER_ALLOWED.each_key { |name| assert_includes classes, name, "a stale allowance: #{name}" }
  end

  test "the container pattern finds a container of a post-form class, or of a classless subject under one, and not a none" do
    css = ".admin-rail-grid .admin-post-main { padding: 0; container-type: inline-size; } .x > .admin-field { container: pair / inline-size } " \
          ".admin-column { container-type: normal } .admin-post-main .y { container-type: size } .admin-post-main > * { container-type: inline-size } " \
          ".admin-post-main div { container-type: inline-size } .admin-post-main [data-field-name] { container-type: inline-size } " \
          ".admin-translation-form { container: admin-pair / inline-size } .admin-translation-form > div { container-type: inline-size } .admin-dashboard > * { container-type: size }"
    found = self.class.container_subjects(css)
    assert_equal [ ".admin-rail-grid .admin-post-main", ".x > .admin-field", ".admin-post-main .y", ".admin-post-main > *", ".admin-post-main div",
                   ".admin-post-main [data-field-name]", ".admin-translation-form", ".admin-translation-form > div", ".admin-dashboard > *" ], found.map(&:first), "a none or normal is no container"
    classes = %w[admin-post-main admin-field admin-translation-form]
    offences = found.select { |_, subject, earlier| self.class.post_form_container?(subject, earlier, classes) }.map(&:first)
    assert_equal [ ".admin-rail-grid .admin-post-main", ".x > .admin-field", ".admin-post-main > *", ".admin-post-main div", ".admin-post-main [data-field-name]", ".admin-translation-form > div" ], offences,
      "the form's own class is allowed only as the subject; a classed subject outside the form and a rule outside it are not offences"
    assert_match CONTAINER_UTILITY, %(class="[container-type:inline-size] p-4")
    assert_match CONTAINER_UTILITY, %(class="@container/main")
    assert_no_match CONTAINER_UTILITY, %(class="admin-container-ish container-fluid")
  end

  # A container query cannot read a custom property, so the threshold is a
  # number written in five places (the media library's too); this holds them to one.
  test "the editors' rail, the dashboard's, the lists' and Settings' dock at one threshold" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read.gsub(%r{/\*.*?\*/}m, "")
    # The editor area asks one other width: 1244px, where a docked post's
    # main column's content box (the area less the rail, its gap and the
    # column's 32px of padding) is 824px, its pairs' threshold, since the
    # post form is no container while docked.
    widths = css.scan(/@container admin-editor \(min-width: ([^)]+)\)/).flatten
    assert_equal [ "1200px", "1244px" ], widths.sort, "the editor's container widths"
    post_main = self.class.css_blocks("content-spiel.tailwind.css", /@container admin-editor \(min-width: 1244px\)\s*\{/).first
    selectors = post_main.scan(/([^{}]+)\{/).flatten.map(&:strip)
    assert_equal 6, selectors.size, "the side-by-side rules, for the main column"
    selectors.each { |selector| assert selector.start_with?(".admin-rail-grid .admin-post-main .admin-translation-pair"), "1244px lays out a docked post's main-column pairs alone: #{selector}" }
    editor = [ "1200px" ]
    # Every width the dashboard's container asks: the rail's two columns
    # below the threshold, and the threshold itself; a block at any other
    # width (one that docked only the rail's ground or its panels) fails.
    dashboard = css.scan(/@container admin-dashboard \(min-width: ([^)]+)\)/).flatten
    assert_equal [ "40rem", editor.first ].sort, dashboard.sort, "the dashboard's container widths"
    assert_equal [ editor.first ], css.scan(/@container admin-list \(min-width: ([^)]+)\)/).flatten, "the lists' container asks the threshold alone"
    assert_equal [ editor.first ], css.scan(/@container admin-settings \(min-width: ([^)]+)\)/).flatten, "the Settings area's container asks the threshold alone"
    # The media library asks the threshold and 760px, where its rail stands
    # beside the grid as a card.
    assert_equal [ "1200px", "760px" ].sort, css.scan(/@container admin-media \(min-width: ([^)]+)\)/).flatten.sort

    docked = self.class.css_blocks("content-spiel.tailwind.css", /@container admin-dashboard \(min-width: #{Regexp.escape(editor.first)}\)\s*\{/)
    assert_equal 1, docked.size
    %w[admin-dashboard__grid admin-dashboard__rail].each { |name| assert_match(/\.#{name}\s*\{/, docked.first, "#{name} docks in the threshold's block") }
    outside = css.sub(docked.first, "")
    assert_no_match(/\.admin-dashboard__rail \.admin-dashboard-panel/, outside, "the rail's panels change only in the threshold's block")
    # The docked head outweighs a kind's tint (0,2,0) by specificity, not
    # by standing later, and the panel's parts that lose their inset are named.
    assert_match(/\.admin-dashboard__rail \.admin-dashboard-panel \.admin-dashboard-panel__head\s*\{[^}]*background:\s*transparent;/, docked.first)
    assert_no_match(/:not\(/, docked.first, "the docked rules name what they change")
  end

  # The buttons are tokens only. A Tailwind palette
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

  # The accent fill means "press me" or "this needs you": a button, a count
  # pill, the unread bubble, a progress bar, and the unsaved marks -- the save
  # bar's dot here, and a changed field's dot, which the stylesheet draws from
  # `data-save-bar-changed` and no utility carries.
  ACCENT_FILL = /(?<![\w-])bg-accent(?![\w-])/
  ACCENT_FILL_ALLOWED = {
    "app/components/admin/ui/button_component.rb" => "the buttons",
    "app/components/admin/shell/sidebar_component.rb" => "the Dashboard's count pill",
    "app/components/admin/notes_screen/header_button_component.html.erb" => "the unread count pill",
    "app/components/admin/notes_screen/thread_row_component.html.erb" => "the unread bubble",
    "app/components/admin/notes_screen/inbox_row_component.html.erb" => "the New chip's dot",
    "app/javascript/controllers/admin/notes/inbox_controller.js" => "the unread bubble",
    "app/javascript/mind_graph/card_notes.js" => "the unread bubble",
    "app/javascript/notes/merge.js" => "the NEW divider",
    "app/components/admin/ui/translate_all_component.html.erb" => "a progress bar",
    "app/javascript/media/upload_tiles.js" => "a progress bar",
    "app/javascript/rich_text/popover.js" => "a script-built button that cannot render the component",
    "app/views/admin/posts/index.html.erb" => "the primary's own split half, New post's type chooser",
    "app/components/admin/ui/save_bar_component.html.erb" => "the save bar's unsaved dot, beside its words",
    "app/views/setup/_steps.html.erb" => "the wizard's progress bar"
  }.freeze

  test "only a button, the checkbox, a count pill, the unread bubble, a progress bar and the unsaved marks carry the accent fill" do
    assert_empty class_offences(ACCENT_FILL, allowed: ACCENT_FILL_ALLOWED)
  end

  test "every accent-fill allowance is still used" do
    ACCENT_FILL_ALLOWED.each_key do |relative|
      assert File.read(Rails.root.join(relative)).match?(ACCENT_FILL), "#{relative} does not carry bg-accent: drop it from ACCENT_FILL_ALLOWED"
    end
  end

  # The tinted fill with accent words is the secondary button's look; a thing
  # that is not pressable and wears it reads as a button.
  TINT_PAIR = /(?=.*(?<![\w-])bg-accent-tint(?![\w-]))(?=.*(?<![\w-])text-accent(?![\w-]))/
  TINT_PAIR_ALLOWED = {
    "app/components/admin/ui/button_component.rb" => "the secondary button",
    "app/javascript/rich_text/popover.js" => "the popover's secondary, a script-built button",
    "app/components/admin/ui/badge_component.rb" => "the accent badge, the MCP channel chip's, not pressable",
    "app/components/admin/shell/sidebar_component.rb" => "the current module's row, a link marked aria-current",
    "app/components/admin/notes_screen/body_component.rb" => "your own mention",
    "app/components/admin/notes_screen/inbox_row_component.html.erb" => "the New chip: unread and for you, never pressable",
    "app/components/admin/ui/segmented_component.rb" => "the chosen segment, a selection behind aria-current or :checked, with its accent edge"
  }.freeze

  test "the tint with accent words is a secondary button's, a chip's, your own mention, the current module's row or the chosen segment, and nothing else" do
    assert_empty class_offences(TINT_PAIR, allowed: TINT_PAIR_ALLOWED)
  end

  test "every tint-pair allowance is still used" do
    TINT_PAIR_ALLOWED.each_key do |relative|
      assert File.read(Rails.root.join(relative)).each_line.any? { |line| line.match?(TINT_PAIR) }, "#{relative} does not wear the pair: drop it from TINT_PAIR_ALLOWED"
    end
  end

  # Icon chips: a family's hue is drawn by one component, so a
  # restyle of the palette is one file, and a hue never stands for a thing
  # that is not a type or a module.
  ICON_HUE = /(?<![\w-])(?:text|bg|fill|stroke)-ic-|--cs-ic-/
  # The hue of people: the pair's utilities (`bg-people`, `text-people-tint`,
  # `inset-ring-people`), the two tokens and the icon family they alias.
  PEOPLE_HUE = /ic-people|(?<![\w-])(?:bg|text|ring|inset-ring|outline|border|fill|stroke)-people(?:-tint)?(?![\w-])|--cs-people/
  ICON_CHIP = "app/components/admin/ui/icon_chip_component.rb".freeze
  # Where the people hue may be drawn, each file with its reason. A task that
  # draws it in one more file adds the file here.
  PEOPLE_HUE_ALLOWED = {
    "app/components/admin/editor_screen/hold_strip_component.html.erb" => "the hold strip's ground",
    ICON_CHIP => "the people family's chip",
    "app/components/admin/ui/avatar_component.rb" => "the circle of a person",
    "app/javascript/ui/avatar.js" => "the scripts' circle, held to the component's classes",
    "app/assets/tailwind/content-spiel.css" => "where the two aliases are written (a stylesheet, not one of ADMIN_SOURCES: named here, read by the still-used test only)"
  }.freeze
  # The stylesheet's rules (`content-spiel.tailwind.css`) that may draw the
  # hue, each as its selector list joined with ", ". The `@theme` block maps
  # the tokens to utilities and is not a rule that draws.
  PEOPLE_RULES = [
    ".admin-notes-marker[data-has-notes]",
    ".admin-rail__tab [data-tab-count]",
    PEOPLE_FRAME.join(", "),
    SECTION_FRAME.join(", "),
    ".admin-block-card:has(> .admin-block-card__head [data-editing-mark]:not(.admin-editing-mark--leaving)):not([data-card-edge=\"held\"]):not([data-notes-active])"
  ].freeze

  def relative_sources = ADMIN_SOURCES.map { |path| Pathname(path).relative_path_from(Rails.root).to_s }

  test "an icon's hue is drawn only by the icon chip" do
    offences = design_offences(ICON_HUE, except: [ ICON_CHIP ])
    assert_empty offences
    assert File.read(Rails.root.join(ICON_CHIP)).match?(ICON_HUE), "the chip does not draw a hue: the guard looks at nothing"
  end

  test "a block type's icon is drawn only through BlockIconComponent" do
    pattern = /\.icon_for\(|(?<![\w:])definition\.icon\b|\btype\.icon\b/
    offences = design_offences(pattern, except: [ "app/components/admin/ui/block_icon_component.rb" ])
    assert_empty offences
  end

  test "the people hue is drawn only where PEOPLE_HUE_ALLOWED says, never by a button" do
    assert_empty design_offences(PEOPLE_HUE, except: PEOPLE_HUE_ALLOWED.keys)
    assert_no_match PEOPLE_HUE, File.read(Rails.root.join("app/components/admin/ui/button_component.rb"))
    assert_match PEOPLE_HUE, File.read(Rails.root.join(ICON_CHIP)), "the chip draws the people hue"
  end

  test "the stylesheet draws the people hue only in the people's rules" do
    offences = self.class.css_rules("content-spiel.tailwind.css").filter_map do |selectors, body|
      list = selectors.join(", ")
      list if body.match?(PEOPLE_HUE) && !list.include?("@theme") && PEOPLE_RULES.exclude?(list)
    end
    assert_empty offences, "a rule that draws the people hue is added to PEOPLE_RULES, with the people's component that sets its class"
  end

  test "every people allowance and rule is still used" do
    PEOPLE_HUE_ALLOWED.each_key do |path|
      assert_match PEOPLE_HUE, Rails.root.join(path).read, "#{path} does not draw the people hue: drop it from PEOPLE_HUE_ALLOWED"
    end
    rules = self.class.css_rules("content-spiel.tailwind.css")
    PEOPLE_RULES.each do |selector|
      body = rules.find { |selectors, _| selectors.join(", ") == selector }&.last
      assert body&.match?(PEOPLE_HUE), "#{selector} does not draw the people hue: drop it from PEOPLE_RULES"
    end
  end

  # A circle of a person's letters is `Admin::Ui::AvatarComponent`, so one
  # person has one size, tone and pair of letters wherever they are drawn. A
  # hand-built one is a round element whose own line draws letters: upper-case
  # or a person's initial(s). It is a line heuristic and misses a circle whose
  # class string is wrapped onto another line, whose letters are written on a
  # line of their own, or that says neither `uppercase` nor `initial(s)`
  # (`<%= name[0] %>`).
  HAND_BUILT_AVATAR = /(?<![\w-])rounded-full(?![\w-]).*(?:(?<![\w-])uppercase(?![\w-])|\binitials?\b)|\binitials?\b.*(?<![\w-])rounded-full(?![\w-])/
  AVATAR_COMPONENT = "app/components/admin/ui/avatar_component.rb".freeze
  # The circles still drawn by hand, each with the reason it is not the
  # component yet. The list may only shrink.
  HAND_BUILT_AVATAR_ALLOWED = {
    # The one script that builds a circle in the browser from the letters the
    # server sends, with the component's own classes.
    "app/javascript/ui/avatar.js" => "the scripts' circle, held to the component's classes"
  }.freeze

  test "nobody draws a circle of initials but AvatarComponent" do
    assert_empty design_offences(HAND_BUILT_AVATAR, except: [ AVATAR_COMPONENT, *HAND_BUILT_AVATAR_ALLOWED.keys ]),
      "a person's circle is Admin::Ui::AvatarComponent, never a hand-built span"
    assert_match HAND_BUILT_AVATAR, File.read(Rails.root.join(AVATAR_COMPONENT)), "the component does not match: the guard looks at nothing"
  end

  test "every hand-built circle allowed still draws one" do
    HAND_BUILT_AVATAR_ALLOWED.each_key do |path|
      assert_match HAND_BUILT_AVATAR, Rails.root.join(path).read, "#{path} does not draw a circle by hand: drop it from HAND_BUILT_AVATAR_ALLOWED"
    end
  end

  test "the hand-built circle pattern matches a span of letters, and not a dot, a chip or the component's render" do
    [
      %(<span class="flex size-6 shrink-0 items-center justify-center rounded-full bg-sunken text-xs font-semibold text-ink" aria-hidden="true"><%= initial %></span>),
      %(<span class="size-7 rounded-full uppercase bg-sunken"><%= initials %></span>),
      %(avatar.className = "flex size-5 items-center rounded-full font-medium uppercase"),
      %(tag.span(initials, class: "rounded-full bg-ink"))
    ].each { |sample| assert_match HAND_BUILT_AVATAR, sample }
    [
      %(<span aria-hidden="true" class="size-2 rounded-full bg-ok"></span>),
      %(<%= render Admin::Ui::AvatarComponent.new(initials: person.initials, size: :md) %>),
      %(class_names(TooltipComponent::HOST, "flex-none rounded-full")),
      %(<span class="rounded-full-ish uppercase">)
    ].each { |sample| assert_no_match HAND_BUILT_AVATAR, sample }
  end

  test "the icon guards' patterns match a hue utility and the token, and not a word" do
    [ "text-ic-code", "bg-ic-form-bg", "fill-ic-text", "stroke-ic-media", "hover:text-ic-lists", "var(--cs-ic-code)" ].each { |sample| assert_match ICON_HUE, sample }
    [ "magic-text", "text-dim", "bg-sunken", "topic-codes", "--cs-accent", "logic-people" ].each { |sample| assert_no_match ICON_HUE, sample }
    assert_match PEOPLE_HUE, "text-ic-people"
    assert_no_match PEOPLE_HUE, "text-ic-code"
    %w[bg-people inset-ring-people text-people-tint hover:bg-people var(--cs-people) var(--cs-people-tint) ring-people].each { |sample| assert_match PEOPLE_HUE, sample }
    %w[people_component peoples bg-peoples text-people_x group-people].each { |sample| assert_no_match PEOPLE_HUE, sample }
  end

  # Elevation and radii: a shadow is one of the four elevation tokens and a
  # radius is one of the radius tokens, so depth and shape are decided in the stylesheet and
  # not per element. The public site is the theme's and out of scope (its
  # language switcher keeps `shadow-menu`, which its own stylesheet defines).
  SHADOW = /(?<![\w-])shadow-(?:2xs|xs|sm|md|lg|xl|2xl|inner|menu|\[[^\]]*\])(?![\w-])/
  SHADOW_ALLOWED = {}.freeze
  RADIUS = /(?<![\w-])rounded-(?:(?:[trblse]|tl|tr|bl|br|ss|se|es|ee)-)?(?:xs|sm|md|lg|xl|2xl|3xl|4xl|\[[^\]]*\])(?![\w-])/
  ELEVATION_SOURCES = ADMIN_SOURCES - Dir[Rails.root.join("app/{views/layouts/public,components/public}/**/*")] - VISITOR_LAYOUTS

  def elevation_offences(pattern, allowed = {})
    (ELEVATION_SOURCES - allowed.keys.map { |path| Rails.root.join(path).to_s }).flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, index|
        "#{Pathname(path).relative_path_from(Rails.root)}:#{index + 1}: #{line[pattern]}" if line.match?(pattern)
      end
    end
  end

  test "a shadow is an elevation token" do
    assert_empty elevation_offences(SHADOW, SHADOW_ALLOWED)
  end

  test "a radius is a radius token" do
    assert_empty elevation_offences(RADIUS)
  end

  test "the elevation and radius patterns match Tailwind's own and arbitrary values, and not a token or a word" do
    [ "shadow-sm", "hover:shadow-lg", "shadow-[0_1px_0_red]", "shadow-menu", "shadow-inner" ].each { |sample| assert_match SHADOW, sample }
    [ "shadow-1", "shadow-4", "shadow-3", "no shadow, no arrow", "box-shadow: x" ].each { |sample| assert_no_match SHADOW, sample }
    [ "rounded-md", "rounded-t-lg", "rounded-[3px]", "md:rounded-xl", "rounded-bl-2xl" ].each { |sample| assert_match RADIUS, sample }
    [ "rounded-cs", "rounded-full", "rounded-t-field", "rounded-r-none", "rounded down", "rounded-card", "rounded-tile" ].each { |sample| assert_no_match RADIUS, sample }
  end

  test "every shadow allowance is still there" do
    assert_empty SHADOW_ALLOWED, "an allowance is added with its reason; this guard reads each entry for the shadow it excuses" if SHADOW_ALLOWED.empty?
    SHADOW_ALLOWED.each_key { |path| assert Rails.root.join(path).read.match?(SHADOW), "#{path} does not draw a shadow: drop its allowance" }
  end

  # The layers: a z-index is one of the `--cs-z-*` tokens of THE LAYERS
  # (`content-spiel.css`), so which layer covers which is decided in one list
  # and not per element. A class writes `z-(--cs-z-<name>)`; a stylesheet
  # writes `z-index: var(--cs-z-<name>)`, or `auto`, which is no layer. Any
  # other spelling of a z-index is refused wherever CS Studio's code is: a
  # Tailwind value, another custom property, an arbitrary property, an
  # inline style, a script's `style.zIndex`, an `@apply`. The tree it reads
  # is CS Studio's: its scripts and helpers, and every component and view
  # but what only a visitor's page draws. The public site's templates,
  # blocks and scripts are left out, because a visitor's page loads the
  # theme's stylesheet, which defines no `--cs-z-*`: a token written there
  # is invalid at computed time and falls back to `auto` without a word.
  # Left out are the public components and layouts (the language switcher
  # and the preview bar keep their own values), the blocks and the posts'
  # components, the page templates and the form-send pages, the entry
  # script `site.js` and the two controllers it alone draws with
  # (`code-copy`, `form-send`), and the theme folders.
  RAW_Z_UTILITY = /(?<![\w-])-?z-(?:\d+|\[[^\]]*\]|auto)(?![\w-])/
  Z_OTHER_PROPERTY = /(?<![\w-])-?z-\((?!--cs-z-[a-z-]+\))/
  # Outside a stylesheet a z-index has no spelling but the utility: the
  # property's name in any form (an inline style, `cssText`, `setProperty`,
  # an arbitrary `[z-index:…]`) and a script's `zIndex` are each one.
  Z_PROPERTY_OUTSIDE_STYLESHEETS = /(?<![\w-])z-index(?![\w-])|(?<!\w)zIndex(?!\w)/
  Z_TOKEN_UTILITY = /(?<![\w-])z-\(--cs-z-([a-z-]+)\)/
  Z_TOKEN_VAR = /var\(--cs-z-([a-z-]+)\)/
  Z_CODE_SOURCES = (Dir[Rails.root.join("app/javascript/**/*.js")] + Dir[Rails.root.join("app/helpers/**/*.rb")] +
                    Dir[Rails.root.join("app/{components,views}/**/*.{rb,erb}")] -
                    Dir[Rails.root.join("app/{views/layouts/public,components/public,components/blocks,components/posts,views/pages,views/form_sends}/**/*")] -
                    VISITOR_LAYOUTS -
                    %w[site.js controllers/code_copy_controller.js controllers/form_send_controller.js].map { |name| Rails.root.join("app/javascript", name).to_s }).freeze
  Z_STYLESHEET_SOURCES = (Dir[Rails.root.join("app/assets/{tailwind,stylesheets}/**/*.css")] - Dir[Rails.root.join("app/assets/tailwind/themes/**/*")]).freeze
  Z_STYLESHEETS = Z_STYLESHEET_SOURCES.map { |path| Pathname(path).relative_path_from(Rails.root.join("app/assets/tailwind")).to_s }.freeze
  # Lowest first; each covers the one before it wherever the two meet.
  LOCAL_LAYERS = %w[lift raised raised-top].freeze
  PAGE_LAYERS = %w[sticky slide-over header sheet divider top-bar popover drop scrim drawer toast].freeze

  def self.stylesheet_without_comments(name) = Rails.root.join("app/assets/tailwind", name).read.gsub(%r{/\*.*?\*/}m, "")

  # `[name, value]` of every `--cs-z-*` the scale writes, in its order.
  def z_scale = self.class.stylesheet_without_comments("content-spiel.css").scan(/--cs-z-([a-z-]+):\s*([^;]+);/).map { |name, value| [ name, value.strip ] }

  def z_offences(paths, pattern, strip_comments: false)
    paths.flat_map do |path|
      text = File.read(path)
      text = text.gsub(%r{/\*.*?\*/}m) { |comment| "\n" * comment.count("\n") } if strip_comments
      text.lines.each_with_index.filter_map do |line, index|
        "#{Pathname(path).relative_path_from(Rails.root)}:#{index + 1}: #{line[pattern]}" if line.match?(pattern)
      end
    end
  end

  test "no z-index is a raw value outside the scale, in a stylesheet or a class" do
    assert_empty z_offences(Z_CODE_SOURCES, Regexp.union(RAW_Z_UTILITY, Z_OTHER_PROPERTY, Z_PROPERTY_OUTSIDE_STYLESHEETS))
    assert_empty z_offences(Z_STYLESHEET_SOURCES, Regexp.union(RAW_Z_UTILITY, Z_OTHER_PROPERTY, /\[z-index/), strip_comments: true), "a stylesheet's @apply"
    Z_STYLESHEETS.each do |name|
      values = self.class.stylesheet_without_comments(name).scan(/z-index:\s*([^;}]+)/).flatten.map(&:strip)
      assert_empty values.grep_v(/\A(?:var\(--cs-z-[a-z-]+\)|auto)\z/), "#{name}: a z-index is a --cs-z-* token or auto"
    end
    assert_no_match(/z-index:/, self.class.stylesheet_without_comments("content-spiel.css"), "content-spiel.css writes the scale, never a z-index of its own")
    names = z_scale.map(&:first)
    assert_not_empty names, "content-spiel.css writes the scale"
    assert_equal names.uniq, names, "each --cs-z-* is written once"
  end

  test "the z guard reads every place CS Studio's code is" do
    %w[app/javascript/editor/drag.js app/javascript/admin.js app/helpers/setup_helper.rb app/components/admin/ui/menu_component.rb
       app/views/admin/media/index.html.erb].each { |path| assert_includes Z_CODE_SOURCES, Rails.root.join(path).to_s, path }
    %w[application.css content-spiel.css content-spiel.tailwind.css admin-rich-text.css].each { |name| assert_includes Z_STYLESHEETS, name }
    %w[app/components/public/preview_bar_component.html.erb app/components/blocks/code_component.html.erb app/views/pages/show.html.erb
       app/javascript/controllers/code_copy_controller.js app/javascript/controllers/form_send_controller.js app/javascript/site.js].each do |path|
      assert Rails.root.join(path).exist?, "#{path} is gone: name another of the public site's files"
      assert_not_includes Z_CODE_SOURCES, Rails.root.join(path).to_s, "#{path} is the public site's"
    end
    assert Z_STYLESHEETS.none? { |name| name.start_with?("themes/") }, "a theme's stylesheet is the theme's"
  end

  test "every z token used is one the scale defines" do
    used = Z_CODE_SOURCES.flat_map { |path| File.read(path).scan(Z_TOKEN_UTILITY).flatten }
    used += Z_STYLESHEETS.flat_map { |name| self.class.stylesheet_without_comments(name).scan(Z_TOKEN_VAR).flatten }
    assert_not_empty used
    assert_empty used.uniq - z_scale.map(&:first), "a z token that THE LAYERS does not define"
  end

  test "the page layers stand in THE LAYERS' order" do
    values = z_scale.to_h.transform_values { |value| Integer(value) }
    assert_equal (LOCAL_LAYERS + PAGE_LAYERS).sort, values.keys.sort, "the scale is the three local layers and the page layers"
    [ LOCAL_LAYERS, PAGE_LAYERS ].each do |layers|
      order = layers.map { |name| values.fetch(name) }
      assert_equal order.sort.uniq, order, "lowest first, strictly increasing: #{layers.zip(order).to_h}"
    end
    # `raised` is used where it meets the page layers (a row's second link,
    # the rail's panels), so it stays under the lowest of them.
    assert_operator values.fetch("raised"), :<, values.fetch(PAGE_LAYERS.first), "raised stands under every page layer"
  end

  test "the z patterns match a raw value and not a token or a word" do
    [ "z-30", "-z-10", "z-[60]", "md:z-20", "z-auto", "@apply z-30;" ].each { |sample| assert_match RAW_Z_UTILITY, sample }
    [ "z-(--cs-z-popover)", "size-10", "fuzz-1", '"Zoom"' ].each { |sample| assert_no_match RAW_Z_UTILITY, sample }
    [ "z-(--my-layer)", "md:-z-(--other)" ].each { |sample| assert_match Z_OTHER_PROPERTY, sample }
    [ "z-(--cs-z-popover)", "md:z-(--cs-z-toast)", "size-(--x)" ].each { |sample| assert_no_match Z_OTHER_PROPERTY, sample }
    [ 'class="[z-index:30]"', 'style="z-index: 30"', "el.style.zIndex = 5", 'el.style.setProperty("z-index", "3")', 'tag.div(style: "z-index:2")' ]
      .each { |sample| assert_match Z_PROPERTY_OUTSIDE_STYLESHEETS, sample }
    [ "zoom", "size-10", "fuzzIndex" ].each { |sample| assert_no_match Z_PROPERTY_OUTSIDE_STYLESHEETS, sample }
    assert_equal [ [ "popover" ] ], "absolute z-(--cs-z-popover) mt-1".scan(Z_TOKEN_UTILITY)
  end

  # The canvas raises its own things (the rich-text popover, a table strip's
  # open entry, a block's menus) inside a stacking context of its own, so the
  # notes slide-over and the editor's sticky header, page layers over it,
  # cover all of them whatever their tokens.
  test "the canvas is its own stacking context, at lift" do
    rule = single_rule(".admin-rail__main")
    assert_match(/isolation:\s*isolate/, rule)
    assert_match(/z-index:\s*var\(--cs-z-lift\)/, rule)
  end

  # The rail's other panels raise their popovers (the tags' and related
  # posts' suggestions) inside a context of their own, under the slide-over;
  # the notes' panel holds the slide-over and stays out. Of a panel and the
  # canvas, the one first in the document is the higher, since its popovers
  # drop onto the other: a panel before the canvas at `raised`, over the
  # canvas's `lift`, and one after it at level 0, under it.
  test "every rail panel but the notes' is a context of its own: at raised before the canvas, under it after" do
    rule = single_rule(":where(.admin-rail__panel):not(:has(> .admin-notes-drawer))")
    assert_match(/position:\s*relative/, rule)
    assert_match(/z-index:\s*var\(--cs-z-raised\)/, rule)
    after = single_rule(":where(.admin-rail__main ~ .admin-rail__panel, :has(.admin-rail__main) ~ .admin-rail__panel):not(:has(> .admin-notes-drawer))")
    assert_match(/z-index:\s*auto/, after)
    assert_match(/isolation:\s*isolate/, after)
  end

  # A card is told apart by its shadow. These keep an edge because the edge is
  # the thing: an alert's tint and an error's outline, a drop zone's dashes.
  CARD_BORDER_ALLOWED = {
    "app/components/admin/ui/error_summary_component.html.erb" => "an alert keeps its tinted edge",
    "app/components/admin/ui/file_drop_component.html.erb" => "the drop zone's dashed edge"
  }.freeze

  # `border` as a class of its own, wherever it stands in the string: after a
  # space and before a space or the closing quote, or first in the string.
  CARD_BORDER = /rounded-card[^"']*\sborder(?=[\s"'])|(?<=[\s"'])border\s[^"']*rounded-card/

  test "the card-border pattern matches border before, after and last beside rounded-card, and not a border utility" do
    [ 'class="rounded-card border"', "class='rounded-card bg-surface border'", 'class="border rounded-card"', 'class="p-2 border bg-surface rounded-card"' ]
      .each { |sample| assert_match CARD_BORDER, sample }
    [ 'class="rounded-card border-b"', 'class="rounded-card border-line"', 'class="border-t rounded-card"', 'class="rounded-card bg-surface"' ]
      .each { |sample| assert_no_match CARD_BORDER, sample }
  end

  test "a card has no border of its own; the tree column and the dragged tile take their elevation from the stylesheet" do
    assert_empty elevation_offences(CARD_BORDER, CARD_BORDER_ALLOWED)
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read
    assert_match(/\.admin-shell__tree \{[^}]*box-shadow: var\(--cs-shadow-1\)/, css)
    assert_no_match(/\.admin-shell__tree \{[^}]*border-right/, css)
    %w[.admin-drag-chosen .admin-drag-fallback].each do |selector|
      assert_match(/#{Regexp.escape(selector)} \{[^}]*var\(--cs-shadow-4\)/, css, selector)
    end
    assert_no_match(/--shadow-menu/, css)
  end

  # Status colour belongs to the status components. The Live and Scheduled
  # fills are the solid chips', so a new use of them is a new state of the
  # chip; the ok, warn and danger fills are held to the files that draw one.
  # The list shrinks as screens move their fills into a status
  # component, and a status component joins it only in place of the screens'
  # fills it takes over. The wizard's step list draws a done step's check in
  # the ok tone, never the Live fill: a finished step is not a publication.
  LIVE_SCHEDULED_FILL = /(?<![\w-])(?:bg|text|border)-(?:live|on-live|scheduled|on-scheduled)(?![\w-])/
  LIVE_SCHEDULED_FILES = %w[app/components/admin/ui/status_chip_component.html.erb app/components/admin/ui/status_chip_component.rb
    app/components/admin/ui/scheduled_date_component.rb].freeze
  STATUS_FILL = /(?<![\w-])bg-(?:ok|warn|danger)(?:-tint)?(?![\w-])/
  STATUS_FILL_FILES = %w[
    app/components/admin/editor_screen/hold_strip_component.html.erb
    app/components/admin/editor_screen/no_address_chip_component.html.erb
    app/components/admin/pages_screen/tree_state_mark_component.rb
    app/components/admin/ui/badge_component.rb
    app/components/admin/ui/button_component.rb
    app/components/admin/ui/chip_input_component.rb
    app/components/admin/ui/error_summary_component.html.erb
    app/components/admin/ui/language_progress_component.html.erb
    app/components/admin/ui/notice_component.rb
    app/components/admin/ui/state_chip_component.rb
    app/components/admin/ui/translation_chip_component.rb
    app/components/admin/ui/unpublished_chip_component.html.erb
    app/components/admin/ui/word_diff_component.rb
    app/javascript/controllers/admin/ui/chip_input_controller.js
    app/javascript/controllers/password_field_controller.js
    app/views/setup/_steps.html.erb
  ].freeze

  test "the live and scheduled fills are drawn only by the status chip and the scheduled date" do
    assert_empty design_offences(LIVE_SCHEDULED_FILL, except: LIVE_SCHEDULED_FILES)
    %w[status_chip_component.rb scheduled_date_component.rb].each do |file|
      assert File.read(Rails.root.join("app/components/admin/ui", file)).match?(LIVE_SCHEDULED_FILL), "#{file} does not draw them: the guard looks at nothing"
    end
  end

  test "the ok, warn and danger fills are in no file beyond today's: a new one goes in a status component" do
    drawn = relative_sources.select { |path| Rails.root.join(path).read.match?(STATUS_FILL) }
    assert_empty drawn - STATUS_FILL_FILES, "these files draw a status fill: put it in a status component, not here"
  end

  test "the status-fill list holds only files that still draw a status fill" do
    STATUS_FILL_FILES.each do |path|
      assert Rails.root.join(path).read.match?(STATUS_FILL), "#{path} does not draw a status fill: drop it from STATUS_FILL_FILES"
    end
  end

  test "the status patterns match a fill utility and not a word or another token" do
    [ "bg-live", "text-on-live", "hover:border-scheduled", "text-on-scheduled" ].each { |sample| assert_match LIVE_SCHEDULED_FILL, sample }
    [ "bg-live-ness", "text-delivered", "live-region", "bg-sunken" ].each { |sample| assert_no_match LIVE_SCHEDULED_FILL, sample }
    [ "bg-ok", "bg-warn-tint", "md:bg-danger", "bg-danger-tint" ].each { |sample| assert_match STATUS_FILL, sample }
    [ "bg-okay", "text-warn-ink", "bg-warning", "border-danger" ].each { |sample| assert_no_match STATUS_FILL, sample }
  end

  # An alert box is `Admin::Ui::NoticeComponent`: a status tint on a radius,
  # in one quoted class string (a constant the file spells is read in place
  # of its interpolation), is a box of words drawn by hand. A chip or a badge
  # has a tint but no card radius in its string, a fill that is a state's mark
  # no radius at all. Not seen: a radius and a tint written in separate
  # strings (`class: [ "rounded-cs", "bg-warn-tint" ]`), and a script's
  # `classList.add(...)`. What may keep a box of its own, with the reason:
  HAND_NOTICE_ALLOWED = {
    "app/components/admin/ui/error_summary_component.html.erb" => "the error summary is its own component, focused on arrival"
  }.freeze
  NOTICE_TINT = /\A(?:[\w-]+:)*bg-(?:warn|ok|danger)-tint\z/
  NOTICE_RADII = %w[rounded-cs rounded-card].freeze

  # `[line number, class string]` for each hand-drawn box in `source`.
  def self.hand_notices(source)
    constants = source.scan(STRING_CONSTANT).to_h { |name, value| [ name, value.gsub(CONTINUED, " ") ] }
    source = source.gsub(/#\{([A-Z][A-Z0-9_]*)\}/) { constants.fetch(Regexp.last_match(1), Regexp.last_match(0)) }
    source.to_enum(:scan, QUOTED).filter_map do
      match = Regexp.last_match
      classes = (match[1] || match[2]).gsub(CONTINUED, " ").split
      [ source[0...match.begin(0)].count("\n") + 1, match[0] ] if classes.intersect?(NOTICE_RADII) && classes.any? { |name| name.match?(NOTICE_TINT) }
    end
  end

  test "an alert box is NoticeComponent: no file outside it draws a box of bg-warn-tint, bg-ok-tint or bg-danger-tint beside rounded-cs or rounded-card" do
    skipped = [ "app/components/admin/ui/notice_component.rb", *HAND_NOTICE_ALLOWED.keys ]
    offences = (relative_sources - skipped).flat_map do |path|
      self.class.hand_notices(Rails.root.join(path).read).map { |line, box| "#{path}:#{line}: #{box}" }
    end
    assert_empty offences, "a box of words is Admin::Ui::NoticeComponent (or its classes, for a box a script fills)"
    HAND_NOTICE_ALLOWED.each_key do |path|
      assert self.class.hand_notices(Rails.root.join(path).read).any?, "#{path} draws no box of its own: drop it from the list"
    end
  end

  test "the hand-drawn notice pattern matches the stale banner's old box and the sign-in's, and not a state chip or the badge's warn tone" do
    [ %(<div role="alert" class="rounded-cs border border-warn bg-warn-tint px-4 py-3 text-sm text-ink">),
      %(<p class="rounded-cs bg-danger-tint px-3 py-2.5 text-[13px] leading-normal text-danger-ink" role="alert" id="alert">),
      %(BOX = "rounded-card px-3".freeze\ntag.p(class: "\#{BOX} bg-ok-tint text-ok-ink")) ].each do |sample|
      assert_not_empty self.class.hand_notices(sample), sample
    end
    [ Admin::Ui::StateChipComponent::GROUNDS.fetch(:warn), %(CLASS = "admin-state-chip rounded-cs border px-2".freeze),
      %(class="#{Admin::Ui::BadgeComponent::TONES.fetch(:warn)}"), %(class="rounded-full bg-ok-tint text-ok-ink") ].each do |sample|
      assert_empty self.class.hand_notices(sample), sample
    end
  end

  # The page tree's width state on <html>: the chosen width
  # (`--admin-tree-width`) and the fold (`data-tree-folded`). The layout's head
  # script writes them before the first paint and `admin--shell--tree-width`
  # from then on; a third writer would lay the column out by a rule neither
  # of them knows. A write is a `setProperty` or `removeProperty` of the
  # property, a `setAttribute`, `toggleAttribute` or `removeAttribute` of an
  # attribute, or a `dataset` assignment or delete (`.treeFolded` or
  # `["treeFolded"]`), each named by its string or by a constant the same file
  # binds to that string. Not seen: a name imported or computed, and an
  # attribute the server draws on <html> (CLAUDE.md names both).
  TREE_STATE_NAMES = %w[--admin-tree-width data-tree-folded].freeze
  TREE_STATE_WRITERS = %w[app/views/admin/shared/_tree_head.html.erb app/javascript/controllers/admin/shell/tree_width_controller.js].freeze
  TREE_STATE_SOURCES = Dir[Rails.root.join("app/{javascript,views,components}/**/*.{erb,rb,js}")]

  def self.tree_state_write?(source)
    quoted = TREE_STATE_NAMES.map { |name| %(["'`]#{Regexp.escape(name)}["'`]) }
    constants = source.scan(/\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*["'`](#{TREE_STATE_NAMES.map { |name| Regexp.escape(name) }.join("|")})["'`]/).map(&:first)
    named = Regexp.union(quoted.map { |pattern| Regexp.new(pattern) } + constants.map { |name| /(?<![\w$])#{Regexp.escape(name)}(?![\w$])/ })
    source.match?(/\b(?:setProperty|removeProperty|setAttribute|toggleAttribute|removeAttribute)\(\s*(?:#{named.source})/) ||
      source.match?(/\bdataset(?:\.treeFolded|\[\s*["'`]treeFolded["'`]\s*\])\s*=(?!=)|\bdelete\s+[\w$.]*dataset(?:\.treeFolded\b|\[\s*["'`]treeFolded["'`]\s*\])/)
  end

  test "the tree's width and fold are written by the head script and the tree-width controller alone" do
    writers = TREE_STATE_SOURCES.select { |path| self.class.tree_state_write?(File.read(path)) }.map { |path| path.delete_prefix("#{Rails.root}/") }
    assert_equal TREE_STATE_WRITERS.sort, writers.sort, "the tree's width state on <html> has two writers, the head script and admin--shell--tree-width"
  end

  # THE OPEN SET HAS ONE WRITER. The cookie `cs_tree_open` is written by
  # `tree/open_set.js` alone and read on the server by `TreeOpenSet` alone,
  # which names it (`TreeOpenSet::COOKIE`); no script beside it touches
  # `document.cookie`, and no Ruby writes or deletes a cookie named by either.
  # Comments are stripped first. Not seen: a theme's or a gem's script, a
  # cookie written through a name bound elsewhere, `document["cookie"]`, and
  # the Cookie Store API (`cookieStore`).
  OPEN_SET_WRITER = "app/javascript/tree/open_set.js"
  OPEN_SET_READER = "app/values/tree_open_set.rb"
  OPEN_SET_NAMES = /cs_tree_open|TreeOpenSet::COOKIE/
  COOKIE_WRITE = /\bcookies\b(?:\s*\.\s*\w+)*\s*\[[^\]]*\]\s*=(?![=~>])|\bcookies\b(?:\s*\.\s*\w+)*\s*\.\s*delete\b/

  # `{ path => text }` -> the paths whose text breaks the rule above.
  def self.open_set_offences(sources)
    sources.filter_map do |path, raw|
      text = uncommented(raw, path)
      if path.end_with?(".js")
        path if path != OPEN_SET_WRITER && text.match?(/\bdocument\s*\.\s*cookie\b|cs_tree_open/)
      elsif path != OPEN_SET_READER && (text.include?("cs_tree_open") || text.each_line.any? { |line| line.match?(OPEN_SET_NAMES) && line.match?(COOKIE_WRITE) })
        path
      end
    end
  end

  def self.open_set_sources
    Dir[Rails.root.join("{app,lib,config}/**/*.{rb,erb,js}")].to_h { |path| [ Pathname(path).relative_path_from(Rails.root).to_s, File.read(path) ] }
  end

  test "the open set has one writer" do
    sources = self.class.open_set_sources
    assert_empty self.class.open_set_offences(sources), "cs_tree_open is written by tree/open_set.js alone, and named in Ruby by TreeOpenSet alone"
    assert_match(/document\.cookie\s*=/, self.class.without_comments(Rails.root.join(OPEN_SET_WRITER).to_s), "the writer writes the cookie")
    assert_includes File.read(Rails.root.join(OPEN_SET_READER)), %(COOKIE = "cs_tree_open")
    assert sources.any? { |path, text| path.end_with?("authentication.rb") && text.match?(COOKIE_WRITE) }, "the session cookie's write is in the sources read, and not matched"
  end

  test "the open set's writer guard reports each sample" do
    assert_equal [ "app/javascript/other.js" ], self.class.open_set_offences("app/javascript/other.js" => %(document.cookie = "x"\n))
    assert_equal [ "app/javascript/other.js" ], self.class.open_set_offences("app/javascript/other.js" => %(const name = "cs_tree_open"\n))
    assert_equal [ "app/controllers/x.rb" ], self.class.open_set_offences("app/controllers/x.rb" => %(cookies[TreeOpenSet::COOKIE] = "1"\n))
    assert_equal [ "app/controllers/x.rb" ], self.class.open_set_offences("app/controllers/x.rb" => %(cookies.permanent[TreeOpenSet::COOKIE] = { value: "1" }\n))
    assert_equal [ "app/controllers/x.rb" ], self.class.open_set_offences("app/controllers/x.rb" => %(cookies.delete(TreeOpenSet::COOKIE)\n))
    assert_equal [ "app/controllers/x.rb" ], self.class.open_set_offences("app/controllers/x.rb" => %(raw = "cs_tree_open"\n))

    assert_empty self.class.open_set_offences(
      "app/javascript/tree/open_set.js" => %(document.cookie = `cs_tree_open=1`\n),
      "app/javascript/other.js" => %(// document.cookie is open_set.js's\n),
      "app/controllers/concerns/authentication.rb" => %(cookies.signed.permanent[:session_id] = { value: 1 }\ncookies.delete(:session_id)\n),
      "app/controllers/x.rb" => %(open_cookie: cookies[TreeOpenSet::COOKIE]\n# cookies[TreeOpenSet::COOKIE] = "1"\n),
      "app/views/x.html.erb" => %(<%= render Tree.new(open_cookie: cookies[TreeOpenSet::COOKIE]) %>\n<%# cookies.delete(TreeOpenSet::COOKIE) %>\n)
    )
  end

  test "the writer pattern matches each way of writing the two" do
    [
      %(root.style.setProperty("--admin-tree-width", "300px")),
      %(document.documentElement.style.removeProperty('--admin-tree-width')),
      %(root.setAttribute("data-tree-folded", "")),
      %(root.toggleAttribute("data-tree-folded", true)),
      %(this.root.removeAttribute("data-tree-folded")),
      %(const PROPERTY = "--admin-tree-width"\nthis.root.style.setProperty(PROPERTY, width)),
      %(const FOLD = "data-tree-folded"\nthis.root.toggleAttribute(FOLD, folded)),
      %(const FOLDED = "data-tree-folded"\nthis.root.setAttribute(FOLDED, "")),
      %(const FOLDED = "data-tree-folded"\nthis.root.removeAttribute( FOLDED )),
      %(document.documentElement.dataset.treeFolded = ""),
      %(root.dataset.treeFolded = "true"),
      %(root.dataset["treeFolded"] = ""),
      %(root.dataset['treeFolded']="1"),
      %(delete document.documentElement.dataset.treeFolded),
      %(delete root.dataset["treeFolded"])
    ].each { |sample| assert self.class.tree_state_write?(sample), "not seen as a write: #{sample}" }

    [
      %(root.hasAttribute("data-tree-folded")),
      %(root.style.getPropertyValue("--admin-tree-width")),
      %(:root[data-tree-folded] { --admin-tree-column: var(--admin-tree-strip); }),
      %(const FOLDED = "data-tree-folded"\nif (root.hasAttribute(FOLDED)) open()),
      %(const OTHER = "data-other"\nroot.setAttribute(OTHER, "")),
      %(root.setAttribute("data-tree-resizing", "")),
      %(if (root.dataset.treeFolded === "") fold()),
      %(if (root.dataset["treeFolded"] == null) fold()),
      %(root.setAttribute("data-tree-fits", ""))
    ].each { |sample| assert_not self.class.tree_state_write?(sample), "seen as a write: #{sample}" }
  end

  # The notes stand in the editors' rail, or over the canvas below its
  # threshold, and never beside the page tree: the open state is the rail's
  # current tab, so nothing on <html> says the notes are open, and nothing
  # says whether the tree fits beside them. A source that names either
  # attribute again (to read it or to write it) brings back the 400px
  # column's rules or the tree's fold beside it.
  RETIRED_NOTES_STATE = %w[data-notes-open data-tree-fits notesOpen treeFits --admin-notes-width].freeze

  test "nothing reads or writes data-notes-open or data-tree-fits" do
    sources = Dir[Rails.root.join("app/{javascript,views,components,assets/tailwind}/**/*.{erb,rb,js,css}")] +
      Dir[Rails.root.join("config/**/*.rb")]
    offences = sources.flat_map do |path|
      source = File.read(path)
      RETIRED_NOTES_STATE.select { |name| source.include?(name) }.map { |name| "#{path.delete_prefix("#{Rails.root}/")}: #{name}" }
    end
    assert_empty offences, "the notes' open state is the rail's current tab, and the tree never folds for the notes"
  end

  # A hover a touch screen keeps after a tap is a stuck
  # highlight, so every button's hover stands under `@media (hover: hover)`.
  # Tailwind's `hover:` variant writes it so; read from the BUILT stylesheet,
  # so a redefined variant, or a class that never reached the build, fails.
  test "a button's hover is under @media (hover: hover)" do
    sources = Dir[Rails.root.join("app/assets/tailwind/**/*.css")].sum("") { |path| File.read(path) }
    assert_no_match(/@custom-variant\s+hover\b/, sources, "Tailwind's own hover variant, under (hover: hover), is the one a button uses")
    built = Rails.root.join("app/assets/builds/tailwind.css")
    assert built.file?, "run bin/rails tailwindcss:build first"
    css = built.read.gsub(%r{/\*.*?\*/}m, "")
    hovers = Admin::Ui::ButtonComponent::VARIANT_CLASSES.keys.product(%i[regular small])
      .flat_map { |variant, size| Admin::Ui::ButtonComponent.classes(variant, size: size).split }.grep(/hover:/).uniq
    assert_operator hovers.size, :>, 5, "the buttons' hovers were found"
    hovers.each do |name|
      escaped = ".#{name.gsub(/([:\[\](),.\/])/) { "\\#{Regexp.last_match(1)}" }}"
      at = css.index(escaped)
      assert at, "#{name} is in the built stylesheet"
      enclosing = []
      css[0...at].scan(/([^{};]*)\{|\}/).each { |(prelude)| prelude ? enclosing.push(prelude.strip) : enclosing.pop }
      assert enclosing.any? { |prelude| prelude.match?(/\A@media \(hover:\s*hover\)\z/) }, "#{name} stands under #{enclosing.inspect}"
    end
  end

  # A row's closing verb, when it is words: dim at rest, so a read row holds
  # no accent, and accent only under the pointer or the focus. Read from the
  # BUILT stylesheet (CI builds it before the unit shards), so a class name
  # that only looks right, or a rule a later one overrides, cannot pass.
  test "a row's closing verb is dim at rest and accent only on the row's hover or focus" do
    built = Rails.root.join("app/assets/builds/tailwind.css")
    assert built.file?, "run bin/rails tailwindcss:build first"
    rules = built.read.gsub(%r{/\*.*?\*/}m, "").scan(/([^{}]+)\{([^{}]*)\}/).map { |selector, body| [ selector.split(",").map(&:strip), body ] }
    colours = rules.filter_map { |selectors, body| [ selectors, body[/(?<![-\w])color:\s*([^;]+)/, 1] ] if selectors.any? { |selector| selector.include?(".admin-row-verb") } && body.match?(/(?<![-\w])color:/) }

    rest = colours.select { |selectors, _| selectors.include?(".admin-row-verb") }
    assert_equal [ "var(--cs-dim)" ], rest.map(&:last), "the verb at rest"
    lit = colours - rest
    assert_equal [ "var(--cs-accent)" ], lit.map(&:last).uniq, "the verb under the pointer or the focus"
    selectors = lit.flat_map(&:first)
    assert selectors.all? { |selector| selector.match?(/:(hover|focus-within|focus-visible)/) }, selectors.inspect
    # The Waiting for you row, the draft tile, a Translations row and a table
    # row of one link (`.admin-row-link`) around their stretched links, and
    # the Notes for you row that is the link, each on hover and focus.
    assert_equal [ ".admin-waiting-row:hover .admin-row-verb", ".admin-waiting-row:focus-within .admin-row-verb",
                   ".admin-translation-row:hover .admin-row-verb", ".admin-translation-row:focus-within .admin-row-verb",
                   "tr:has(.admin-row-link):hover .admin-row-verb", "tr:has(.admin-row-link):focus-within .admin-row-verb",
                   ".admin-draft-tile:hover .admin-row-verb", ".admin-draft-tile:focus-within .admin-row-verb",
                   "a:hover>.admin-row-verb", "a:focus-visible>.admin-row-verb" ].sort, selectors.sort
  end

  # A row that opens one thing is pressed anywhere: its one link is
  # `.admin-row-link`, whose `::after` covers the row, and the focus ring is
  # drawn on that cover. The rule is the stylesheet's alone, so a row never
  # spells the stretch in utilities of its own, and its other controls stand
  # above the cover at `--cs-z-raised`.
  ROW_LINK_PARTS = [ /\A(?:[\w-]+:)*after:absolute\z/, /\A(?:[\w-]+:)*after:inset-0\z/ ].freeze

  # `[line number, the string]` for each quoted class string in `source` that
  # holds both an `after:absolute` and an `after:inset-0`, in either order
  # and whatever stands between them.
  def self.hand_row_links(source)
    source.to_enum(:scan, QUOTED).filter_map do
      match = Regexp.last_match
      classes = (match[1] || match[2]).gsub(CONTINUED, " ").split
      [ source[0...match.begin(0)].count("\n") + 1, match[0] ] if ROW_LINK_PARTS.all? { |part| classes.any? { |name| name.match?(part) } }
    end
  end

  test "a row's stretched link is .admin-row-link, written once" do
    offences = ADMIN_SOURCES.flat_map do |path|
      self.class.hand_row_links(File.read(path)).map { |line, string| "#{Pathname(path).relative_path_from(Rails.root)}:#{line}: #{string}" }
    end
    assert_empty offences, "a row's stretched link takes .admin-row-link, never after:absolute and after:inset-0 of its own"
    [ %(class="font-medium after:absolute after:inset-0 after:content-['']"), %(class="after:inset-0 text-ink after:absolute"),
      %(class: "after:absolute font-medium focus-visible:after:outline-2 after:inset-0") ].each do |sample|
      assert_not_empty self.class.hand_row_links(sample), sample
    end
    [ %(class="admin-row-link font-medium after:absolute-ish after:inset-0"), %(class="after:absolute" title="after:inset-0"),
      %(class="after:absolute after:top-0") ].each do |sample|
      assert_empty self.class.hand_row_links(sample), sample
    end

    assert_match(/position:\s*relative;/, rule_for([ "tr:has(.admin-row-link)", "li:has(> * .admin-row-link)" ]))
    cover = single_rule(".admin-row-link::after")
    assert_match(/content:\s*"";/, cover)
    assert_match(/position:\s*absolute;/, cover)
    assert_match(/inset:\s*0;/, cover)
    assert_match(/outline:\s*none;/, single_rule(".admin-row-link:focus-visible"))
    ring = single_rule(".admin-row-link:focus-visible::after")
    assert_match(/outline:\s*2px solid var\(--cs-accent\);/, ring)
    assert_match(/outline-offset:\s*-2px;/, ring)

    named = self.class.css_rules("content-spiel.tailwind.css").select { |selectors, _| selectors.any? { |selector| selector.include?("admin-row-link") } }
    verb, named = named.partition { |selectors, _| selectors.any? { |selector| selector.include?(".admin-row-verb") } }
    # The verb at a link row's end stands in a cell of its own, outside the
    # link, so the row lights it: the accent rule names the row link's row.
    assert_equal 1, verb.size, "the row verb's accent is one rule: #{verb.map(&:first).inspect}"
    assert_includes verb.first.first, "tr:has(.admin-row-link):hover .admin-row-verb"
    assert_includes verb.first.first, "tr:has(.admin-row-link):focus-within .admin-row-verb"
    sticky, link = named.partition { |selectors, _| selectors.any? { |selector| selector.include?(":first-child") } }
    assert_equal 4, link.size, "the row link is four rules, written once: #{link.map(&:first).inspect}"
    # A sticky cell is the containing block of the cover, which would then
    # cover that cell alone: a table whose row is one link has no sticky first column.
    assert_equal 1, sticky.size, "the sticky first column is one rule: #{sticky.map(&:first).inspect}"
    assert_match(/:where\(table:not\(:has\(\.admin-row-link\)\)\)/, sticky.first.first.join(","))
    assert_match(/position:\s*sticky;/, sticky.first.last)
  end

  # A box that cannot be changed keeps its full colour, so its tick reads at
  # the browser's own 3:1 on the card; the cursor and the label's meta words
  # say it is fixed, never a faded box.
  test "a disabled checkbox keeps its colour, refuses the pointer and its label reads meta" do
    box = single_rule(".cs-checkbox:disabled")
    assert_match(/cursor:\s*not-allowed;/, box)
    assert_match(/opacity:\s*1;/, box)
    assert_match(/(?<![-\w])color:\s*var\(--cs-meta\);/, rule_for([ ".cs-checkbox:disabled + label", "label:has(> .cs-checkbox:disabled)" ]))
  end

  # A switch that cannot be changed is never faded either: off, the sunken
  # track and field-line outline it has at rest with the meta knob; on, a
  # meta track (not the accent, which says it can be pressed) with the
  # surface knob, but for a held form's, which keeps the accent; its label
  # reads meta. A disabled segment keeps its
  # colour too: meta words, no hover, and a chosen one keeps the chosen look.
  test "a disabled switch keeps its colour, refuses the pointer, is meta when on and its label reads meta" do
    switch = single_rule(".cs-toggle:disabled")
    assert_match(/cursor:\s*not-allowed;/, switch)
    assert_match(/opacity:\s*1;/, switch)
    off = single_rule(".cs-toggle:disabled:not(:checked)")
    assert_match(/background:\s*var\(--cs-sunken\);/, off)
    assert_match(/border-color:\s*var\(--cs-field-line\);/, off)
    assert_match(/background:\s*var\(--cs-meta\);/, single_rule(".cs-toggle:disabled:not(:checked)::before"))
    on = single_rule(".cs-toggle:disabled:checked")
    assert_match(/background:\s*var\(--cs-meta\);/, on)
    assert_match(/border-color:\s*var\(--cs-meta\);/, on)
    assert_match(/background:\s*var\(--cs-surface\);/, single_rule(".cs-toggle:disabled:checked::before"))
    assert_match(/(?<![-\w])color:\s*var\(--cs-meta\);/, rule_for([ ".cs-toggle:disabled + label", "label:has(> .cs-toggle:disabled)" ]))
    # A held form is read-only, not off-limits: its switch that is on keeps
    # the accent (`test/system/admin/editing_holds_test.rb`: "a held post's
    # switch that is on keeps its accent").
    held = single_rule(".admin-held .cs-toggle:disabled:checked")
    assert_match(/background:\s*var\(--cs-accent\);/, held)
    assert_match(/border-color:\s*var\(--cs-accent\);/, held)
    rules = self.class.css_rules("content-spiel.tailwind.css").select { |selectors, _| selectors.any? { |selector| selector.include?(".cs-toggle") } }
    rules.each { |selectors, body| assert_no_match(/opacity:\s*0/, body, selectors.join(", ")) }

    segment = Admin::Ui::SegmentedComponent::RADIO_SEGMENT_CLASS.split
    assert_empty segment.grep(/opacity/), "a disabled segment is not faded"
    %w[has-[:disabled]:cursor-not-allowed has-[:disabled]:not-has-[:checked]:text-meta has-[:disabled]:not-has-[:checked]:hover:bg-transparent
       has-[:checked]:bg-accent-tint has-[:checked]:text-accent].each { |name| assert_includes segment, name }
  end

  # THE TREE: both trees draw one row (`Admin::Ui::TreeItemComponent`), whose
  # geometry is the four `--cs-tree-*` lengths and whose looks are the one
  # `.admin-tree` block. The files that draw a tree row, where an indent or a
  # tint of their own would part the two trees.
  TREE_FILES = [
    "app/components/admin/pages_screen/tree_*", "app/components/admin/ui/tree_item_component.*",
    "app/components/admin/ui/tree_find_component.*", "app/javascript/mind_graph/node_list.js"
  ].freeze
  TREE_LENGTHS = %w[--cs-tree-row --cs-tree-disclosure --cs-tree-mark --cs-tree-step].freeze
  TREE_INDENT = /(?<![\w-])(?:[\w\[\]-]+:)*-?(?:ml|pl|ms|ps)-|(?<![\w-])(?:margin|padding)-(?:left|inline-start)(?![\w-])|\b(?:margin|padding)(?:Left|InlineStart)\b/
  TREE_TINT = /(?<![\w-])(?:[\w\[\]-]+:)*bg-accent-tint(?![\w-])/

  # A tree file's text without its comments: ERB's `<%# %>`, Ruby's `#`, and
  # a script's `//` and `/* */`.
  def self.without_comments(path) = uncommented(File.read(path), path)

  # `text`, as the file at `path` would hold it, without its comments.
  def self.uncommented(text, path)
    text = text.gsub(/<%#.*?%>/m, "") if path.end_with?(".erb")
    text = text.gsub(/^\s*#.*$/, "").gsub(/\s#\s.*$/, "") if path.end_with?(".rb")
    text = text.gsub(%r{/\*.*?\*/}m, "").gsub(%r{(?<![:"'])//.*$}, "") if path.end_with?(".js")
    text
  end

  def self.tree_files = TREE_FILES.flat_map { |glob| Dir[Rails.root.join(glob)] }.sort.map { |path| Pathname(path).relative_path_from(Rails.root).to_s }

  # The tree files whose text, comments stripped, matches `pattern`.
  def self.tree_offences(pattern, files = tree_files)
    files.select { |path| without_comments(Rails.root.join(path).to_s).match?(pattern) }
  end

  # Each `--cs-tree-*` declaration in `content-spiel.css`, comments
  # stripped, as `[selector of the rule it stands in, name, value]`.
  def tree_length_declarations
    self.class.css_rules("content-spiel.css").flat_map do |selectors, body|
      body.scan(/(--cs-tree-[\w-]+):\s*([^;]+);/).map { |name, value| [ selectors.join(", "), name, value.strip ] }
    end
  end

  test "a tree's geometry is its four tokens, written once" do
    declarations = tree_length_declarations
    assert_equal TREE_LENGTHS.sort, declarations.map { |_, name, _| name }.sort, "each tree length is defined once in content-spiel.css"
    assert_equal [ ":root" ], declarations.map(&:first).uniq, "the tree lengths are defined on :root"
    assert_no_match(/--cs-tree-[\w-]+:/, self.class.stylesheet_without_comments("content-spiel.tailwind.css"), "a tree length is written once, in content-spiel.css")

    step = declarations.find { |_, name, _| name == "--cs-tree-step" }.last
    rule = single_rule(".admin-tree__children")
    margin = rule[/margin-inline-start:\s*(\d+)px/, 1]
    guide = rule[/border-inline-start:\s*(\d+)px solid var\(--cs-line-strong\)/, 1]
    padding = rule[/padding-inline-start:\s*(\d+)px/, 1]
    assert [ margin, guide, padding ].all?, "the children list's margin, guide and padding are pixels: #{rule.squish}"
    assert_equal step, "#{margin.to_i + guide.to_i + padding.to_i}px", "one level's step is the children list's margin, guide and padding"

    offences = self.class.tree_offences(TREE_INDENT)
    assert_empty offences, "a tree file sets no indent of its own (ml-, pl-, padding-inline-start): the step is the .admin-tree block's"
  end

  test "the match's tint is the tree's own rule, with the title's ink" do
    rule = single_rule(".admin-tree mark")
    assert_match(/background:\s*var\(--cs-accent-tint\);/, rule)
    assert_match(/(?<![\w-])color:\s*inherit;/, rule)
    offences = self.class.tree_offences(TREE_TINT)
    assert_empty offences, "a tree file draws no accent tint of its own: a match's is the .admin-tree block's"
  end

  test "the tree patterns match an indent and a tint, and not a token, a margin of another side or a comment" do
    [ "ml-2", "pl-[7px]", "hover:pl-1", "ms-2", "ps-1", "-ml-4", "-pl-1", "-ms-2", "md:-ps-1", "padding-inline-start: 4px", "margin-inline-start: 13px",
      "margin-left: 4px", "padding-left: 2px", "button.style.paddingInlineStart = x", "el.style.marginInlineStart = x", "el.style.marginLeft = x",
      "el.style.paddingLeft = x" ].each { |sample| assert_match TREE_INDENT, sample }
    [ "html-", "mr-2", "pr-1", "me-2", "pe-1", "url-path", "items-center", "steps-2", "margin-inline-end: 8px", "padding-right: 2px",
      "el.style.marginRight = x", "admin-tree-row__mark" ].each { |sample| assert_no_match TREE_INDENT, sample }
    [ "bg-accent-tint", "aria-[current]:bg-accent-tint" ].each { |sample| assert_match TREE_TINT, sample }
    [ "bg-accent", "text-accent-tint", "bg-accent-tint-strong" ].each { |sample| assert_no_match TREE_TINT, sample }
    Dir.mktmpdir do |dir|
      { "a.html.erb" => "<%# ml-2 %>\n<li>", "b.rb" => "# pl-2\nx = 1 # ml-1\n", "c.js" => "// pl-2\n/* ml-2 */ const a = \"https://x\"" }.each do |name, text|
        path = File.join(dir, name)
        File.write(path, text)
        assert_no_match TREE_INDENT, self.class.without_comments(path), name
      end
    end
  end

  # One ring, on the focused element: a row never draws an outline from a
  # focus inside it, which would stand beside the control's own.
  test "no tree row draws an outline from :has(:focus-visible)" do
    rules = self.class.css_rules("content-spiel.tailwind.css")
    from_inside = rules.select { |selectors, body| body.match?(/(?<![\w-])outline(?:-[\w-]+)?:/) && selectors.any? { |selector| selector.match?(/:has\([^)]*:focus/) && selector.include?("admin-tree") } }
    assert_empty from_inside.map(&:first), "a tree row draws no outline for a focus inside it"
    ring = rule_for([ ".admin-tree-row :focus-visible", '.admin-tree [role="treeitem"]:focus-visible > .admin-tree-row' ])
    assert_match(/outline:\s*2px solid var\(--cs-accent\);/, ring)
    assert_match(/outline-offset:\s*-2px;/, ring)
    # The one exception: a focused treeitem draws its ring on its own row,
    # which the rule above draws, and not round its whole branch.
    assert_equal [ [ '.admin-tree [role="treeitem"]:focus-visible' ] ],
                 rules.select { |selectors, body| selectors.any? { |selector| selector.include?("admin-tree") && selector.include?("focus") } && body.match?(/outline:\s*none/) }.map(&:first),
      "no tree rule takes a focused element's ring away, but the treeitem's, whose ring is on its row"
  end

  # The selected row is a place, not a row being worked on: at rest it shows
  # its markers and count, never its handle or "+", which show on any row
  # by hover, focus within and a coarse pointer alone.
  test "no tree rule reveals the handle or the + from the selected row" do
    rules = self.class.css_rules("content-spiel.tailwind.css")
    parts = Admin::Ui::TreeItemComponent::CLASSES.values_at(:handle, :add)
    selected = Admin::Ui::TreeItemComponent::CLASSES[:row_selected]
    revealing = rules.select do |selectors, body|
      selectors.any? { |selector| selector.include?(selected) && (parts.any? { |part| selector.include?(part) } || body.match?(/(?<![\w-])opacity:/)) }
    end
    assert_empty revealing.map(&:first), "the selection reveals the handle or the +"
    shown = rules.select { |selectors, body| body.match?(/opacity:\s*1;/) && selectors.any? { |selector| parts.all? { |part| selector.include?(part) } } }
    assert_equal 2, shown.size, "the handle and the + are shown by hover and focus within, and by a coarse pointer"
    assert shown.flat_map(&:first).none? { |selector| selector.include?(selected) }
  end

  test "the tree's rules are one block" do
    rules = self.class.css_rules("content-spiel.tailwind.css")
    tree = /\.admin-tree(?:-row|-node__handle|__children|(?![\w-]))/
    indices = rules.each_index.select { |index| rules[index].first.any? { |selector| selector.match?(tree) } }
    assert_operator indices.size, :>=, 10, "the .admin-tree block was not found"
    assert_equal (indices.first..indices.last).to_a, indices, "every rule of the tree stands in the one .admin-tree block, with no other rule between"
    assert_equal 1, rules.count { |selectors, _| selectors == [ ".admin-tree-row--selected" ] }, ".admin-tree-row--selected is defined once"
  end
end
