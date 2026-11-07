require "test_helper"

# Two rules of the mind graph that nothing else would catch. A node's publishing state is
# `Publishing::State`'s: no query and no script decides anything from
# `published_at` itself. And the graph shows the rows: no query reads a
# published copy.
#
# HOW THEY ARE HELD: by refusing every MENTION, not by guessing the forms a
# comparison can take. A query would be written as `where(published_at:
# ..now)`, `arel_table[:published_at].gt(now)`, `Post.published` or
# `if post.published_at`, a script as `!node.publishedAt`, and a pattern
# that wants an operator after the name sees none of them. So a line of the
# graph's queries and scripts that names the column (`published_at`,
# `publishedAt`), one of `Publishable`'s scopes that compare it, or a
# published copy fails, unless it is one of the exact lines below, each of
# which only CARRIES the column to where the rule is kept. A new line that
# needs the column is added here with its reason, and read by a person.
class MindGraphGuardsTest < ActiveSupport::TestCase
  RUBY = (Dir[Rails.root.join("app/queries/post_graph.rb")] + Dir[Rails.root.join("app/queries/post_graph/**/*.rb")]).freeze
  SCRIPTS = Dir[Rails.root.join("app/javascript/mind_graph/**/*.js")].freeze

  COLUMN = /published_?at/i
  # `Publishable`'s scopes that are a comparison of the column with the
  # clock or with nothing (`app/models/concerns/publishable.rb`), and the
  # predicates a record answers from it. In the queries only: a script has
  # no scope, and its message keys end in ".scheduled" and ".live".
  SCOPES = /\.(?:published|scheduled|with_unpublished_changes|status)\b(?![:_?])|\.(?:live|draft|scheduled|unpublished_changes)\?/
  COPIES = /Publishing\.(?:published|current|pending|newest|in_force)|published_all|Publishing::(?:Listing|Version|Snapshot)|published_versions|\.in_force\b|current_for/

  # The exact lines (stripped) that may name the column, a scope or a copy,
  # each with why it decides nothing about a node's state.
  ALLOWED = {
    "PAGE_COLUMNS = %i[id title parent_id position published_at unpublished_changes_at].freeze" =>
      "site.rb: the columns loaded of a page; `Publishing::State` is handed the record and reads them",
    "posts.pluck(:id, :content_type, :published_at, :updated_at).map { |id, type, published_at, updated_at| [ id, type, (published_at || updated_at).to_f, updated_at ] }" =>
      "site.rb: RECENCY, not state: the time is loaded and turned into a number on this one line, so no row carries it on (a page's posts newest first, a draft by when it was last changed)",
    "COLUMNS = %i[id title content_type published_at unpublished_changes_at].freeze" =>
      "builder.rb: the columns loaded of a post; `Publishing::State` is handed the record and reads them",
    "status: state.status," =>
      "builder.rb (a post's node and a page's): `state` is a `Publishing::State`, and the answer is its own",
    "Publishing::Version.pending(@now).where(record_type: type, record_id: ids.to_a).order(id: :desc).pluck(:record_id, :live_at).to_h" =>
      "builder.rb: WHEN a pending copy comes into force, for `Publishing::State`, by `Publishing.pending`'s own scope; no content of a copy is read"
  }.freeze

  def lines(files)
    files.flat_map do |path|
      File.readlines(path).each_with_index.reject { |line, _| line.match?(%r{\A\s*(#|//)}) }
          .map { |line, index| [ "#{Pathname(path).relative_path_from(Rails.root)}:#{index + 1}", line.strip ] }
    end
  end

  def offences(files, pattern) = lines(files).select { |_where, line| line.match?(pattern) && !ALLOWED.key?(line) }.map { |where, line| "#{where}: #{line}" }

  test "no query and no script of the mind graph compares published_at: a node's state is Publishing::State's" do
    assert_operator RUBY.size + SCRIPTS.size, :>, 10
    assert_empty offences(RUBY + SCRIPTS, COLUMN), "a line that names the column: ask Publishing::State, or add the exact line to ALLOWED with its reason"
    assert_empty offences(RUBY, SCOPES), "a scope or a predicate that is a comparison of published_at"
  end

  test "the mind graph reads the rows: no query of it reads a published copy" do
    assert_empty offences(RUBY, COPIES)
  end

  test "every allowed line is still there, so the list names nothing that has gone" do
    present = lines(RUBY + SCRIPTS).map(&:last).to_set

    assert_empty ALLOWED.keys.reject { |line| present.include?(line) }
  end

  # WHAT A NAME CANNOT SEE, AND HOW IT IS HELD INSTEAD.
  # (1) A row that carries the time as a place in an array is compared under
  # whatever name a block parameter gives it. So no row carries it: `Site`
  # turns it into a recency on the line that loads it (allowed above), and
  # `test/queries/post_graph/site_test.rb` holds that a row's places are an
  # id, a type, a number and `updated_at`. (2) A script could decide a look
  # by comparing a scheduled change's time with the clock (a corner dot that
  # goes when the time has passed while the page is open): that is a state
  # decided without `Publishing::State`, and it names no column. So no
  # script of the graph names the time the data carries (`change_at`; the
  # card says the day in the server's words, `change_on`) and none reads a
  # clock for a date: a look is the `status` and `changes` the server
  # answered, until the data is read again.
  CLOCK = /\bDate\s*\.\s*(?:now|parse)\b|\bnew\s+Date\b|\bchange_?at\b|\bTemporal\b/i
  PAGE_SCRIPTS = (SCRIPTS + Dir[Rails.root.join("app/javascript/controllers/admin/mind_graph/**/*.js")]).freeze

  test "no script of the mind graph reads the clock for a date or names a scheduled change's time: a look is what the server answered" do
    assert_operator PAGE_SCRIPTS.size, :>, SCRIPTS.size
    assert_empty offences(PAGE_SCRIPTS, CLOCK)
    [ "if (Date.now() > Date.parse(node.change_at)) return LOOKS.live", "const due = new Date(node.changeAt)", "node.change_at", "Temporal.Now.instant()" ].each { |line| assert_match CLOCK, line }
    [ "const started = performance.now()", "const date = node.change_on ?? \"\"", "state.updated = true" ].each { |line| assert_no_match CLOCK, line }
  end

  # Each form a query or a script would really be written in.
  test "the patterns can fail" do
    [ "post.published_at.nil?", "if page.published_at > now", "node.publishedAt < Date.now()", "record.published_at == nil",
      "readable.where(published_at: ..now)", "Post.where(published_at: nil)", "posts.where.not(published_at: nil)",
      "Post.arel_table[:published_at].gt(now)", "table[:published_at].lteq(@now)", "now >= post.published_at", "Time.current > published_at",
      "if post.published_at", "published_at ? 1 : 0", "post.published_at&.past?", "if (!node.publishedAt) return", "const live = node.publishedAt ? 1 : 0",
      "node.published_at", "(published_at || updated_at).to_f" ].each { |line| assert_match COLUMN, line }
    [ "Post.published", "readable_posts.published.count", "Publishable.scheduled", "site.readable_posts.scheduled", "Page.with_unpublished_changes",
      "post.live?", "page.draft?", "record.scheduled?", "post.unpublished_changes?", "post.status" ].each { |line| assert_match SCOPES, line }
    [ "state.status_at", "graph[:status]", "{ status: 1 }", "published: true" ].each { |line| assert_no_match SCOPES, line }
    [ "Publishing.published(page)", "Publishing.published_all(records)", "Publishing::Listing.call", "Publishing.current(page)", "Publishing.pending(page)",
      "Publishing::Version.in_force(now)", "Publishing::Version.of(page)", "Publishing::Snapshot.of(page)", "Arel::Table.new(:published_versions)",
      "versions.in_force", "Publishing::Version.current_for(pages)" ].each { |line| assert_match COPIES, line }
  end

  test "the allow-list is exact: an allowed line with anything added to it is refused" do
    ALLOWED.each_key do |line|
      changed = "#{line}.select { |row| row }"
      assert_not ALLOWED.key?(changed)
      assert(changed.match?(COLUMN) || changed.match?(SCOPES) || changed.match?(COPIES), line)
    end
  end
  # A TOGGLE OF THE LEGEND IS A FILTER ON WHAT IS DRAWN, NOT A NEW LAYOUT:
  # the layout is computed once over everything the data holds, so the
  # worker has no `filter` message and nothing sends one. The guard holds
  # that ABSENCE, from the page, the client and the worker: whoever brings a second
  # layout back for a toggle has to take this test away first, and read why
  # (`layout_worker.js`, "THERE IS NO `filter` MESSAGE"). What this cannot
  # see, that a toggle moves nothing, is the browser test "a toggle moves
  # nothing: after each of the eight, off and on again, every node is where
  # it was and the layout was told nothing".
  FILTER_SENT = /\blayout\??\.filter\(|type:? ===? "filter"|type: "filter"|^\s*filter\(nodeIds/

  test "no script of the mind graph knows a filter message for the layout: not the page, not the client, not the worker" do
    knowing = Dir[Rails.root.join("app/javascript/mind_graph/*.js"), Rails.root.join("app/javascript/controllers/admin/mind_graph/*.js")]
      .select { |path| File.read(path).lines.reject { |line| line.strip.start_with?("//") }.any? { |line| line.match?(FILTER_SENT) } }

    assert_empty knowing.map { |path| File.basename(path) }
  end

  test "the filter guard can fail: each line the message was written in is one it reads" do
    [
      "    layout?.filter(state.visibleNodes.map((index) => state.nodes[index].id), state.visibleEdges)",
      "    filter(nodeIds, edgeIndexes) { send({ type: \"filter\", nodeIds, edgeIndexes }) },",
      "  } else if (message.type === \"filter\") {"
    ].each { |line| assert_match FILTER_SENT, line }
    [ "    const freed = message.ids.map(find).filter(Boolean)", "    filter: refilter," ].each { |line| assert_no_match FILTER_SENT, line }
  end

  # "All posts" has no record, so its id is a word the scripts must agree on
  # with the server (`PostGraph::ALL_POSTS`). It is written once, in
  # `ids.js`; every other script asks for the constant.
  test "the id of All posts is written in one script, ids.js, and is the server's" do
    scripts = Dir[Rails.root.join("app/javascript/mind_graph/*.js"), Rails.root.join("app/javascript/controllers/admin/mind_graph/*.js")]
    naming = scripts.select { |path| File.read(path).lines.reject { |line| line.strip.start_with?("//") }.any? { |line| line.include?(%("#{PostGraph::ALL_POSTS}")) } }

    assert_equal [ "ids.js" ], naming.map { |path| File.basename(path) }
    assert_includes File.read(Rails.root.join("app/javascript/mind_graph/ids.js")), %(export const ALL_POSTS = "#{PostGraph::ALL_POSTS}")
  end

  # An export says "something else reads this". Four constants were exported
  # and imported by nothing, so a reader looked for the reader; they are the
  # file's own now.
  test "the layout's and the drawing's own constants are exported by nothing" do
    exported = { "renderer.js" => "HIDE_TAG_LINES_BELOW", "labels.js" => "LABEL_BUDGET", "camera.js" => "MIN_ZOOM|MAX_ZOOM" }.select do |file, names|
      File.read(Rails.root.join("app/javascript/mind_graph", file)).match?(/^export const (?:#{names})\b/)
    end
    assert_empty exported.keys
  end

  # THE CANVAS'S TEXT IS IN THE SANS: mono is for code and a key's value in
  # CS Studio, and a canvas's words are neither. A script that reads the
  # mono token or names a mono face brings it back.
  MONO = /--cs-mono|mono(?:font|space)|\bmono\b|plex mono/i

  test "the canvas's text is in the sans: no script of the mind graph reads --cs-mono or names a mono font" do
    assert_empty offences(PAGE_SCRIPTS, MONO)
    [ 'read("--cs-mono")', "theme.monoFont", "theme.strongMonoFont", '`12px "IBM Plex Mono"`', '"11px monospace"' ].each { |line| assert_match MONO, line }
    [ "theme.countFont", "theme.strongFont", "a monotonic count", "context.font = labelFont(theme, node, chosen)" ].each { |line| assert_no_match MONO, line }
  end

  # WHAT FADES IS THE THEME'S (`--cs-graph-faded`, theme key `faded`), so
  # `admin_contrast_test` can measure it. Every strength the drawing scripts
  # set is one of these right-hand sides, each with why it is no colour of
  # the script's own. A new form is added here with its reason.
  STRENGTH_SCRIPTS = %w[marks.js renderer.js swatches.js].map { |file| Rails.root.join("app/javascript/mind_graph", file).to_s }.freeze
  ALPHA_ALLOWED = {
    "1" => "full strength: a hovered label, the rings, the plain and the bright pass of the lines",
    "dimmed(index) ? theme.faded : 1" => "a node a selection leaves out, its mark and its notes badge, at the theme's fade",
    "pass === \"faded\" ? theme.faded : 1" => "the lines a selection leaves out, at the theme's fade",
    "label.alpha * (dimmed(label.index) ? theme.faded : 1)" => "a label's fade-in at the edge of its reach (`labels.js`, motion and no colour) at the theme's fade"
  }.freeze
  ALPHA = /globalAlpha\s*=(?!=)\s*(.+?);?\s*\z/

  def strengths(files)
    lines(files).filter_map { |where, line| (match = line.match(ALPHA)) && [ where, match[1] ] }
  end

  test "no script of the mind graph sets a strength but 1: what fades is the theme's" do
    assert_operator strengths(STRENGTH_SCRIPTS).size, :>=, 4
    assert_empty strengths(STRENGTH_SCRIPTS).reject { |_where, value| ALPHA_ALLOWED.key?(value) }.map { |where, value| "#{where}: globalAlpha = #{value}" }
    refused = [ "context.globalAlpha = 0.35", "context.globalAlpha = dimmed ? 0.3 : 1", "context.globalAlpha = bright ? 0.9 : 1", "context.globalAlpha = label.alpha * 0.28" ]
    refused.each { |line| assert_not ALPHA_ALLOWED.key?(line[ALPHA, 1]), line }
    ALPHA_ALLOWED.each_key { |value| assert_equal value, "    context.globalAlpha = #{value}"[ALPHA, 1] }
  end

  test "every strength allowance is still written" do
    written = strengths(STRENGTH_SCRIPTS).map(&:last).to_set
    assert_empty ALPHA_ALLOWED.keys.reject { |value| written.include?(value) }
  end

  # A look names theme KEYS (`marks.js`'s `LOOKS`, `renderer.js`'s
  # `LINE_STYLES`), and a key `theme.js` does not read is drawn in no colour
  # at all, with no error.
  def script(file) = Rails.root.join("app/javascript/mind_graph", file).read
  def tokens_read = script("theme.js")[/^const TOKENS = \{(.*?)^\}/m, 1].scan(/(\w+): "(--cs-[\w-]+)"/).to_h

  test "every theme key LOOKS and LINE_STYLES name is one theme.js reads" do
    looks = script("marks.js")[/^export const LOOKS = \{(.*?)^\}/m, 1].scan(/(?:fill|outline|centre|corner): "(\w+)"/).flatten - [ "own" ]
    lines = script("renderer.js")[/^export const LINE_STYLES = \{(.*?)^\}/m, 1].scan(/colour: "(\w+)"/).flatten
    assert_operator looks.uniq.size, :>=, 4
    assert_equal 5, lines.size
    assert_empty (looks + lines).uniq - tokens_read.keys
  end

  # THE MARKS DRAWN IN CSS OUTSIDE THE CANVAS (the card's and a row's type
  # dot and tag square, and `ContentTypeDotComponent`'s dots, rings and
  # unregistered ring) are a second drawing of `marks.js`'s: each is held to
  # the token the canvas draws the same mark in.
  def utility_token(name) = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read[/^\s*--color-#{Regexp.escape(name)}: var\((--cs-[\w-]+)\);/, 1]
  def function_body(source, name) = source[/^function #{name}\(.*?^\}/m]

  test "the marks drawn in CSS outside the canvas are in the canvas's tokens" do
    card, marks = script("card.js"), script("marks.js")

    tag_border = card[/^export const TAG_MARK = "([^"]*)"/, 1][/\bborder-([\w-]+)/, 1]
    tag_key = function_body(marks, "drawTag")[/strokeStyle = theme\.(\w+)/, 1]
    assert_equal tokens_read.fetch(tag_key), utility_token(tag_border), "the card's tag square is border-#{tag_border}, the canvas strokes a tag in theme.#{tag_key}"

    retired_border = card[/colour_index == null \? "border border-([\w-]+)"/, 1]
    retired_key = function_body(marks, "drawPost")[/const hue = retired \? theme\.(\w+)/, 1]
    assert_equal tokens_read.fetch(retired_key), utility_token(retired_border), "a retired type's ring is border-#{retired_border}, the canvas draws it in theme.#{retired_key}"

    assert_includes script("theme.js"), "read(`--cs-cat-${index + 1}`)", "theme.categories[i] is --cs-cat-(i + 1)"
    dots = Admin::Ui::ContentTypeDotComponent
    dots::FILLED.zip(dots::RINGS).each_with_index do |(fill, ring), index|
      assert_equal "bg-cat-#{index + 1}", fill, "slot #{index + 1}'s dot is theme.categories[#{index}]"
      assert_equal "border border-cat-#{index + 1}", ring, "slot #{index + 7}'s ring is drawn in theme.categories[#{index}]"
      assert_equal "--cs-cat-#{index + 1}", utility_token("cat-#{index + 1}")
    end
    component_retired = Rails.root.join("app/components/admin/ui/content_type_dot_component.rb").read[/def mark = .*: "border border-([\w-]+)"/, 1]
    assert_equal tokens_read.fetch(retired_key), utility_token(component_retired), "the component's unregistered type is border-#{component_retired}, the canvas draws it in theme.#{retired_key}"
  end

  # THE STATUS WORDS ARE ONE SET (H6), written in three files: the legend's
  # five looks (`legend.states`, `mind_graph_screen.en.yml`), the shared
  # chips' labels (`status_chip.labels` and `unpublished_chip.label`,
  # `ui.en.yml`), which are the card's words for a record in one state and
  # the words of a list row's name (`list.stated`), and the card's sentences
  # for the two states of a live record (`script.card.status`,
  # `mind_graph.en.yml`), which carry the day of a scheduled change. A word
  # changed in one of them and not in the others fails here. A two-state look
  # is the Live chip's word, a comma and the second chip's word as the
  # sentence goes on ("Live, unpublished changes"). That join is English's,
  # and the guard reads the English files, the only ones CS Studio has.
  def status_words
    {
      legend: I18n.t("admin.components.mind_graph_screen.legend.states", locale: :en),
      chips: I18n.t("admin.components.ui.status_chip.labels", locale: :en),
      unpublished: I18n.t("admin.components.ui.unpublished_chip.label", locale: :en),
      card: I18n.t("admin.mind_graph.script.card.status", locale: :en)
    }
  end

  def status_word_mismatches(words)
    legend, chips, card = words.fetch(:legend), words.fetch(:chips), words.fetch(:card)
    joined = ->(second) { "#{chips.fetch(:live)}, #{second[0].downcase}#{second[1..]}" }
    expected = {
      live: chips.fetch(:live), draft: chips.fetch(:draft), scheduled: chips.fetch(:scheduled),
      live_with_changes: card.fetch(:live_with_changes),
      live_change_scheduled: card.fetch(:live_change_scheduled).delete_suffix(" %{date}")
    }
    mismatches = expected.reject { |state, word| legend[state] == word }.map { |state, word| "legend.states.#{state} is #{legend[state].inspect}, the chip's words are #{word.inspect}" }
    mismatches << "legend.states has #{legend.keys.sort}, not the five looks" unless legend.keys.sort == expected.keys.sort
    mismatches << "card.status.live_change_scheduled names no day" unless card.fetch(:live_change_scheduled).end_with?(" %{date}")
    mismatches << "card.status.live_with_changes is not the Live chip's word with the unpublished chip's" unless card.fetch(:live_with_changes) == joined.call(words.fetch(:unpublished))
    mismatches << "card.status.live_change_scheduled is not the Live chip's word with change_scheduled's" unless card.fetch(:live_change_scheduled) == joined.call(card.fetch(:change_scheduled))
    mismatches
  end

  test "the legend's status words are the chip's: the status chip's three labels and the card's two sentences without their day" do
    assert_empty status_word_mismatches(status_words)
    assert_equal I18n.t("admin.components.ui.status_chip.labels", locale: :en).keys.sort, %i[draft live scheduled], "a chip label with no look of the legend's"
  end

  # Each word of each file, changed alone in a copy, is refused: the guard
  # holds every source, not only the legend.
  test "the status words guard can fail: one word changed in any one of its sources is refused" do
    words = status_words
    samples = words.flat_map do |source, value|
      value.is_a?(Hash) ? value.keys.map { |key| [ source, key ] } : [ [ source, nil ] ]
    end
    assert_equal 12, samples.size, "five looks, three chip labels, the unpublished chip and the card's three sentences"
    samples.each do |source, key|
      planted = words.transform_values { |value| value.is_a?(Hash) ? value.dup : value.dup }
      if key then planted[source][key] = "#{planted[source][key]}x" else planted[source] = "#{planted[source]}x" end
      assert_not_empty status_word_mismatches(planted), "#{source}#{".#{key}" if key} changed alone passed"
    end
  end
end
