require "test_helper"

# Design pass spec §3: tokens only, red only for destruction and failure,
# and none of the components the shared parts replaced. These rules are easy to
# break one innocent edit at a time, so they are pinned here.
class AdminDesignRulesTest < ActiveSupport::TestCase
  # Everything that draws CS Studio, or is drawn inside it: its views (the
  # invitation page `views/invitations`, a product-layout page, among them) and
  # components, the media components it shares with the public site
  # (`components/media`: the picker and the picture tag), the public site's own
  # components (`components/public`: the preview bar, whose two colours are
  # theme tokens too), and every script -- the Stimulus controllers and the
  # modules beside them (`media/`, `saving/`, `search/`, `rich_text/`,
  # `mind_graph/`), which build markup and set classes as well. The mind
  # graph's draw onto a canvas, where a colour is a string handed to the
  # context: its modules read every one from the tokens (`mind_graph/theme.js`).
  SOURCE_DIRECTORIES = %w[
    views/admin views/layouts views/setup views/invitations components/admin components/media components/public
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

  # A block card's and a tile's state (held, its type gone, its thread open)
  # is an outline inside its edge, drawn by the stylesheet from an attribute,
  # so nothing changes size and no shadow is overwritten; a border utility on
  # the wrapper or the head would be a second edge beside it.
  EDITOR_CARDS = %w[block_card_component.html.erb block_tile_component.html.erb section_card_component.html.erb].map { |f| "app/components/admin/editor_screen/#{f}" }.freeze
  EDITOR_CARD_WRAPPER = /class[=:].*(?<![\w-])admin-block-(?:card|tile)(?:__head)?(?![\w-])/
  BORDER_EDGE = /(?<![\w-])border(?:-(?:line|line-strong|danger|accent|field-line))?(?=[\s"'])/
  # In the order they win by: the later rule, at one weight.
  CARD_EDGES = { '.admin-block-card[data-card-edge="held"]' => "--cs-field-line",
                 ".admin-block-card:where(:not(.admin-section-card))[data-notes-active]" => "--cs-accent",
                 '.admin-block-card[data-card-edge="unavailable"]' => "--cs-danger" }.freeze

  test "the editor's cards and tiles draw no border utility: their edges are the stylesheet's state outlines" do
    wrappers = EDITOR_CARDS.flat_map { |path| Rails.root.join(path).readlines.each_with_index.select { |line, _| line.match?(EDITOR_CARD_WRAPPER) }.map { |line, index| [ path, index, line ] } }
    assert_operator wrappers.size, :>=, 3, "the wrapper lines are found: the card's, its head's and the tile's"
    offences = wrappers.select { |_, _, line| line.match?(BORDER_EDGE) }.map { |path, index, _| "#{path}:#{index + 1}" }
    assert_empty offences, "a border utility on a card or tile wrapper"

    CARD_EDGES.each do |selector, token|
      body = single_rule(selector)
      assert_match(/outline:\s*2px solid var\(#{token}\)/, body, selector)
      assert_match(/outline-offset:\s*-2px/, body, selector)
    end
    order = CARD_EDGES.keys.map { |selector| self.class.css_rules("content-spiel.tailwind.css").index { |found, _| found == [ selector ] } }
    assert_equal order.sort, order, "held, then notes-active, then unavailable: the later edge wins"
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
  # the accent ring outside its edge, its thread open the accent outline
  # inside it. No border: the drop place's dashes are the only edge a tile
  # shows, and only while it is the place a drag would land.
  TILE_STATES = {
    [ ".admin-block-tile" ] => [ "var(--cs-radius-tile)", "background: var(--cs-surface)", "box-shadow: var(--cs-shadow-1)" ],
    [ ".admin-block-tile:where(:hover)" ] => [ "box-shadow: var(--cs-shadow-2)", "background: var(--cs-tile-raised)" ],
    [ '.admin-block-tile:where(:has(> .admin-block-tile__face[aria-expanded="true"]))', ".admin-block-tile:where(:has(> .admin-block-tile__face:focus-visible))" ] =>
      [ "box-shadow: var(--cs-shadow-3), 0 0 0 2px var(--cs-accent)", "background: var(--cs-tile-raised)" ],
    [ ".admin-block-tile[data-notes-active]" ] => [ "outline: 2px solid var(--cs-accent)", "outline-offset: -2px" ],
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

  test "the border pattern matches a border utility of the card's colours, and not a radius, an outline or a hover" do
    [ 'class="border ', "border-line ", "border-line-strong\"", "border-danger'", "border-accent ", "border-field-line\"", "data-[notes-active]:border-accent " ].each { |sample| assert_match BORDER_EDGE, sample }
    [ "rounded-card ", "outline-accent ", "border-b ", "borderless ", "admin-border-x " ].each { |sample| assert_no_match BORDER_EDGE, sample }
  end

  # A button is `Admin::Ui::ButtonComponent`'s (or its `.classes`, which a
  # link, a label and a script take): an outlined box with a field-line edge on
  # a button, a menu's trigger or anything a pointer presses is the old look
  # drawn by hand. A script takes the strings from the view (a `data-` value),
  # or, where it cannot, is held to them string for string (the popover, below).
  # What may keep a field-line edge and still be pressed is a control that is
  # not a button, each named with its reason.
  PRESSABLE = /<button|tag\.button|button_class:|(?<![\w-])cursor-pointer(?![\w-])|element\("button"|createElement\("button"\)/
  FIELD_LINE_EDGE = /(?<![\w-])(?:[\w-]+:)*border-field-line(?![\w-])/
  HAND_BUTTON_ALLOWED = {
    "admin-rich-text-button" => "the rich-text toolbar's toggles: `aria-pressed` draws their edge",
    "has-checked:border-accent has-checked:bg-accent-tint" => "New post's type choice, a radio group drawn as tiles",
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
        "#{marker} no longer draws a pressable field-line edge: drop it from HAND_BUTTON_ALLOWED"
    end
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

  WELL_CONTAINERS = ":is(.admin-column, .admin-field, .admin-filter-bar, .admin-rich-text-popover, .admin-translation-suggestion)".freeze
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

  test "a filter bar resets the invalid edge, as every wrapper of wells does" do
    reset = self.class.css_rules("content-spiel.tailwind.css").find { |_, body| body.include?("--cs-field-invalid-border: initial") }
    assert_equal %w[.admin-column .admin-field .admin-filter-bar .admin-rich-text-popover .admin-translation-suggestion], reset&.first
  end

  test "the rule parser finds a rule by its whole selector list and splits it only at top-level commas" do
    rules = self.class.css_rules("content-spiel.tailwind.css")
    assert rules.any? { |selectors, _| selectors == WELL_SELECTORS }
    assert_not rules.any? { |selectors, _| selectors.include?(".admin-column") && selectors.include?("textarea") }, "a comma inside :is() split the list"
  end

  # The old field was a white box with a full field-line outline and an
  # accent focus. A text field is a well, from its wrapper (`.admin-column`,
  # `.admin-field`, `.admin-filter-bar`, the popover, the suggestion box) or
  # from `.admin-well`, so neither that outline nor a focus colour of its own
  # stands on an input in CS Studio's markup.
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
    "CONTENT·SPIEL" => "the product layout's wordmark",
    "Content·Spiel</span>" => "the setup layout's wordmark"
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
        "#{marker} no longer draws a count in the label: drop it from COUNT_LABEL_ALLOWED"
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
    "app/components/admin/ui/icon_chip_component.rb" => "the accent icon chip, not pressable",
    "app/components/admin/shell/sidebar_component.rb" => "the current module's row, a link marked aria-current",
    "app/components/admin/notes_screen/body_component.rb" => "your own mention"
  }.freeze

  test "the tint with accent words is a secondary button's, a chip's, your own mention or the current module's row, and nothing else" do
    assert_empty class_offences(TINT_PAIR, allowed: TINT_PAIR_ALLOWED)
  end

  test "every tint-pair allowance is still used" do
    TINT_PAIR_ALLOWED.each_key do |relative|
      assert File.read(Rails.root.join(relative)).each_line.any? { |line| line.match?(TINT_PAIR) }, "#{relative} no longer wears the pair: drop it from TINT_PAIR_ALLOWED"
    end
  end

  # Icon chips: a family's hue is drawn by one component, so a
  # restyle of the palette is one file, and a hue never stands for a thing
  # that is not a type or a module.
  ICON_HUE = /(?<![\w-])(?:text|bg|fill|stroke)-ic-|--cs-ic-/
  PEOPLE_HUE = /ic-people/
  ICON_CHIP = "app/components/admin/ui/icon_chip_component.rb".freeze
  # Where the people hue may be drawn once built (the spec); none uses it yet.
  PEOPLE_HUE_ALLOWED = %w[
    app/components/admin/ui/icon_chip_component.rb app/components/admin/ui/avatar_component.rb
  ].freeze

  def relative_sources = ADMIN_SOURCES.map { |path| Pathname(path).relative_path_from(Rails.root).to_s }

  test "an icon's hue is drawn only by the icon chip" do
    offences = design_offences(ICON_HUE, except: [ ICON_CHIP ])
    assert_empty offences
    assert File.read(Rails.root.join(ICON_CHIP)).match?(ICON_HUE), "the chip no longer draws a hue: the guard looks at nothing"
  end

  test "a block type's icon is drawn only through BlockIconComponent" do
    pattern = /\.icon_for\(|(?<![\w:])definition\.icon\b|\btype\.icon\b/
    offences = design_offences(pattern, except: [ "app/components/admin/editor_screen/block_icon_component.rb" ])
    assert_empty offences
  end

  test "the people hue is drawn only by the icon chip and the people's own components, never by a button" do
    allowed = PEOPLE_HUE_ALLOWED + Dir[Rails.root.join("app/components/admin/{notes_screen/marker_component*,notes_screen/row_pill_component*,presence_screen/row_marker_component*,editor_screen/hold_strip_component*}")].map { |path| Pathname(path).relative_path_from(Rails.root).to_s }
    assert_empty design_offences(PEOPLE_HUE, except: allowed)
    assert_no_match PEOPLE_HUE, File.read(Rails.root.join("app/components/admin/ui/button_component.rb"))
    assert_match PEOPLE_HUE, File.read(Rails.root.join(ICON_CHIP)), "the chip draws the people hue"
  end

  test "the icon guards' patterns match a hue utility and the token, and not a word" do
    [ "text-ic-code", "bg-ic-form-bg", "fill-ic-text", "stroke-ic-media", "hover:text-ic-lists", "var(--cs-ic-code)" ].each { |sample| assert_match ICON_HUE, sample }
    [ "magic-text", "text-dim", "bg-sunken", "topic-codes", "--cs-accent", "logic-people" ].each { |sample| assert_no_match ICON_HUE, sample }
    assert_match PEOPLE_HUE, "text-ic-people"
    assert_no_match PEOPLE_HUE, "text-ic-code"
  end

  # Elevation and radii: a shadow is one of the four elevation tokens and a
  # radius is one of the radius tokens, so depth and shape are decided in the stylesheet and
  # not per element. The public site is the theme's and out of scope (its
  # language switcher keeps `shadow-menu`, which its own stylesheet defines).
  SHADOW = /(?<![\w-])shadow-(?:2xs|xs|sm|md|lg|xl|2xl|inner|menu|\[[^\]]*\])(?![\w-])/
  SHADOW_ALLOWED = {
    "app/components/admin/pages_screen/tree_node_component.rb" => "the selected row's bar; stage 2 draws it in the accent"
  }.freeze
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
    SHADOW_ALLOWED.each_key { |path| assert Rails.root.join(path).read.match?(SHADOW), "#{path} no longer draws a shadow: drop its allowance" }
  end

  # A card is told apart by its shadow. These keep an edge because the edge is
  # the thing: an alert's tint and an error's outline, a drop zone's dashes.
  CARD_BORDER_ALLOWED = {
    "app/components/admin/ui/error_summary_component.html.erb" => "an alert keeps its tinted edge",
    "app/components/admin/ui/insecure_notice_component.rb" => "an alert keeps its tinted edge",
    "app/components/admin/ui/mail_failed_notice_component.rb" => "an alert keeps its tinted edge",
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
  # chip; the ok, warn and danger fills are held to the files that draw one
  # today, a list that may only shrink as screens move their fills into a
  # status component.
  LIVE_SCHEDULED_FILL = /(?<![\w-])(?:bg|text|border)-(?:live|on-live|scheduled|on-scheduled)(?![\w-])/
  LIVE_SCHEDULED_FILES = %w[app/components/admin/ui/status_chip_component.html.erb app/components/admin/ui/status_chip_component.rb].freeze
  STATUS_FILL = /(?<![\w-])bg-(?:ok|warn|danger)(?:-tint)?(?![\w-])/
  STATUS_FILL_FILES = %w[
    app/components/admin/dashboard_screen/translation_card_component.html.erb
    app/components/admin/editor_screen/changed_elsewhere_component.html.erb
    app/components/admin/editor_screen/changes_overview_component.html.erb
    app/components/admin/editor_screen/delete_block_dialog_component.rb
    app/components/admin/editor_screen/hold_strip_component.html.erb
    app/components/admin/editor_screen/live_region_component.html.erb
    app/components/admin/editor_screen/no_address_chip_component.html.erb
    app/components/admin/editor_screen/publish_changes_dialog_component.html.erb
    app/components/admin/editor_screen/table_controls_component.html.erb
    app/components/admin/forms_screen/list_component.rb
    app/components/admin/forms_screen/new_form_dialog_component.html.erb
    app/components/admin/forms_screen/submission_component.html.erb
    app/components/admin/groups_screen/permission_matrix_component.html.erb
    app/components/admin/groups_screen/scope_editor_component.html.erb
    app/components/admin/notes_screen/thread_component.rb
    app/components/admin/pages_screen/tree_state_mark_component.rb
    app/components/admin/settings_screen/language_dialogs_component.html.erb
    app/components/admin/settings_screen/mail_alert_component.rb
    app/components/admin/settings_screen/mail_state_component.rb
    app/components/admin/settings_screen/mail_test_outcome_component.rb
    app/components/admin/tokens_screen/create_step_component.html.erb
    app/components/admin/translation_screen/summary_card_component.html.erb
    app/components/admin/ui/badge_component.rb
    app/components/admin/ui/button_component.rb
    app/components/admin/ui/chip_input_component.rb
    app/components/admin/ui/error_summary_component.html.erb
    app/components/admin/ui/insecure_notice_component.rb
    app/components/admin/ui/language_tabs_component.html.erb
    app/components/admin/ui/mail_failed_notice_component.rb
    app/components/admin/ui/system_check_row_component.rb
    app/components/admin/ui/translation_chip_component.rb
    app/components/admin/ui/unpublished_chip_component.html.erb
    app/components/admin/ui/word_diff_component.rb
    app/components/admin/users_screen/invite_dialog_component.html.erb
    app/javascript/controllers/admin/ui/chip_input_controller.js
    app/javascript/controllers/password_field_controller.js
    app/javascript/mind_graph/card.js
    app/views/admin/accounts/edit.html.erb
    app/views/admin/passwords/edit.html.erb
    app/views/admin/passwords/new.html.erb
    app/views/admin/sessions/new.html.erb
    app/views/admin/shared/_stale_banner.html.erb
    app/views/invitations/show.html.erb
    app/views/setup/_flash.html.erb
  ].freeze

  test "the live and scheduled fills are drawn only by the status chip" do
    assert_empty design_offences(LIVE_SCHEDULED_FILL, except: LIVE_SCHEDULED_FILES)
    assert File.read(Rails.root.join(LIVE_SCHEDULED_FILES.last)).match?(LIVE_SCHEDULED_FILL), "the chip no longer draws them: the guard looks at nothing"
  end

  test "the ok, warn and danger fills are in no file beyond today's: a new one goes in a status component" do
    drawn = relative_sources.select { |path| Rails.root.join(path).read.match?(STATUS_FILL) }
    assert_empty drawn - STATUS_FILL_FILES, "these files draw a status fill: put it in a status component, not here"
  end

  test "the status-fill list holds only files that still draw a status fill" do
    STATUS_FILL_FILES.each do |path|
      assert Rails.root.join(path).read.match?(STATUS_FILL), "#{path} no longer draws a status fill: drop it from STATUS_FILL_FILES"
    end
  end

  test "the status patterns match a fill utility and not a word or another token" do
    [ "bg-live", "text-on-live", "hover:border-scheduled", "text-on-scheduled" ].each { |sample| assert_match LIVE_SCHEDULED_FILL, sample }
    [ "bg-live-ness", "text-delivered", "live-region", "bg-sunken" ].each { |sample| assert_no_match LIVE_SCHEDULED_FILL, sample }
    [ "bg-ok", "bg-warn-tint", "md:bg-danger", "bg-danger-tint" ].each { |sample| assert_match STATUS_FILL, sample }
    [ "bg-okay", "text-warn-ink", "bg-warning", "border-danger" ].each { |sample| assert_no_match STATUS_FILL, sample }
  end
end
