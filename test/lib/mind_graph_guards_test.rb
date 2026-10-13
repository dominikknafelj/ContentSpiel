require "test_helper"

# Two rules of the mind graph that nothing else would catch (pages in the
# mind graph, spec §4 and decision 3). A node's publishing state is
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

  # WHAT A NAME CANNOT SEE, AND HOW IT IS HELD INSTEAD (Task 3's review, m2).
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
  # A TOGGLE OF THE LEGEND IS A FILTER ON WHAT IS DRAWN, NOT A NEW LAYOUT (the
  # ruling on the pages plan's Task 6): the layout is computed once over
  # everything the data holds, so the worker has no `filter` message and
  # nothing sends one. Until the build's last task the worker and its client
  # still knew the message the old radios had used, and this guard had an
  # exception for them; the message is gone, so the guard now holds its
  # ABSENCE, from the client and the worker too: whoever brings a second
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
end
