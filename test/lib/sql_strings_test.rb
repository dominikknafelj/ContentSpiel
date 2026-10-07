require "test_helper"
require "ripper"

# How a query is written in `app/` (CLAUDE.md, "Queries are Active Record, then
# Arel, then SQL"), in that order of preference:
#
#   1. Active Record's own syntax where it says the thing exactly: a hash
#      condition, a range, `where.not`, `.or`, `where.missing`, `merge`,
#      `group(:column)`, `order(column: :desc)`, `where(id: relation.select(:id))`.
#   2. Arel nodes for what that syntax can't say -- a function, a jsonb
#      operator, a LIKE, a row comparison, an EXISTS, a join with its own ON,
#      an ordering by an expression -- built through `SqlNodes` (`app/values`).
#   3. A SQL string only where Arel has no node, and then with its reason on
#      the line: `# sql: <why this can't be nodes>`.
#
# A string of SQL is what Active Record can't see into: it can't alias the
# table, quote the identifier, cast the value or `unscope` the condition, and
# every value in it is one interpolation away from being SQL itself. So under
# `app/` every line of Ruby that
#
#   - hands a string (or a heredoc) to `where`, `.not`, `joins`, `select`,
#     `order`, `reorder`, `group`, `having`, `pluck` or `pick`,
#   - wraps one in `Arel.sql(`,
#   - opens a `SQL` heredoc,
#   - builds one with `sanitize_sql(`, `sanitize_sql_array(` or another
#     `sanitize_sql_for_...(` (`sanitize_sql_like` is escaping, not SQL),
#   - or sends a statement to the connection: `find_by_sql`, `select_value(s)`,
#     `select_rows`, `select_all`, `select_one`, `exec_query` and the other
#     `exec_...(`, `.execute(` (whatever the argument: an Arel statement run on
#     the connection says why no relation runs it)
#
# must carry `# sql: <reason>` -- at least MINIMUM_REASON characters -- on the
# line itself or alone on the line above. A template (`.erb`) has no excuse at
# all: a query that needs SQL belongs to a model.
#
# The lists can't rot: a `# sql:` mark that excuses nothing fails, and so does
# a FILES or NOT_SQL entry that matches nothing.
#
# What it does not see (the lexer reads tokens, not types): a string held in a
# variable or a constant and passed by name (`where(CONDITION)`), a string
# argument that is not the first, and a call without parentheses
# (`where "..."`). A tripwire for the habit, like `version_bump_test.rb`; the
# reviewer is still the proof. Migrations (`db/`) and `lib/` are out of scope.
class SqlStringsTest < ActiveSupport::TestCase
  ROOT = "app".freeze
  MINIMUM_REASON = 10

  # In the code with every string's text blanked (`split`), so what is left of
  # a string argument is its opening quote.
  STRING = /(?:"|'|<<[~-]?|%[qQ]?[(\[{<|])/
  SQL = /
    (?<![\w.:])(?:where|joins|select|order|reorder|group|having|pluck|pick)\(\s*#{STRING}  # a bare call, as in a scope's body
    |
    \.(?:where|not|joins|select|order|reorder|group|having|pluck|pick)\(\s*#{STRING}
    |
    \bArel\.sql\(
    |
    <<[~-]?["']?SQL\b
    |
    \bsanitize_sql(?!_like\b)\w*\(
    |
    \bfind_by_sql\b
    |
    \bselect_(?:value|values|rows|all|one)\(
    |
    \bexec_\w+\(
    |
    \.execute\(
  /x

  # The whole trailing comment starts with it, so prose that mentions the mark
  # is not one.
  MARK = /\A#\s*sql:\s*(?<reason>.*)/

  # Files left as they are, each with its reason.
  FILES = {
    "app/models/public_site/paths.rb" => "the URL writer's read of a subtree is one reviewed `WITH RECURSIVE` heredoc with a single " \
      "bound id; it is left exactly as the paths parity tests pinned it"
  }.freeze

  # Lines that match and are not a query: `path => [ pattern of the line, reason ]`.
  NOT_SQL = {
    "app/queries/jump/search.rb" => [ /\bgroup\("(?:Pages|Sections)"/, "`group(label, rows)` is the palette's own method: a group of results, not a GROUP BY" ]
  }.freeze

  Found = Struct.new(:path, :line, :code)

  # The source with every comment and every string's text blanked (line breaks
  # kept, so a line number still names the line), and the comments by line.
  # Ripper does the lexing, so SQL quoted in a comment or named in a message is
  # not a query -- the call that would run it is.
  BLANKED = %i[on_comment on_embdoc_beg on_embdoc on_embdoc_end on_tstring_content].freeze

  def self.split(source)
    comments = {}
    code = Ripper.lex(source).map do |(line, _column), type, token, _state|
      next token unless BLANKED.include?(type)

      comments[line] = token if type == :on_comment
      token.gsub(/[^\n]/, " ")
    end.join
    [ code, comments ]
  end

  # Every guarded construction in `code`, by the line it starts on (an
  # argument may open on the next line: `where(\n  "..."`).
  def self.found(path, code, original)
    lines = original.lines
    code.to_enum(:scan, SQL).map { Regexp.last_match.begin(0) }.map { |offset| code[0...offset].count("\n") + 1 }.uniq
      .map { |line| Found.new(path, line, lines[line - 1].to_s.strip) }
  end

  # The reason marked for `line`: on it, or alone on the line above.
  def self.reason(line, comments, code_lines)
    own = comments[line].to_s.match(MARK)
    return own[:reason].strip if own

    above = comments[line - 1].to_s.match(MARK)
    above[:reason].strip if above && code_lines[line - 2].to_s.strip.empty?
  end

  def self.sources
    Rails.root.glob("#{ROOT}/**/*.{rb,rake,erb}").sort.to_h { |path| [ path.to_s.delete_prefix("#{Rails.root}/"), path.read ] }
  end

  # `[offences, exemptions used]` for `sources` (`{ relative path => source }`).
  def self.check(sources)
    offences = []
    used = []
    sources.each do |path, source|
      if path.end_with?(".erb")
        found(path, source, source).each { |hit| offences << "#{path}:#{hit.line}: #{hit.code} (a template: move the query to a model)" }
        next
      end

      code, comments = split(source)
      code_lines = code.lines
      hits = found(path, code, source)
      excused = []
      hits.each do |hit|
        if FILES.key?(path) then used << [ :file, path ]
        elsif NOT_SQL.key?(path) && hit.code.match?(NOT_SQL.fetch(path).first) then used << [ :not_sql, path ]
        elsif (reason = reason(hit.line, comments, code_lines))
          excused << hit.line
          offences << "#{path}:#{hit.line}: `# sql:` needs a reason of at least #{MINIMUM_REASON} characters" if reason.length < MINIMUM_REASON
        else
          offences << "#{path}:#{hit.line}: #{hit.code}"
        end
      end

      comments.each do |line, comment|
        next unless comment.match?(MARK)

        marks = [ line, (line + 1 if code_lines[line - 1].to_s.strip.empty?) ].compact
        offences << "#{path}:#{line}: `# sql:` on a line with no SQL string or connection call" unless marks.intersect?(excused)
      end
    end
    [ offences, used ]
  end

  test "no SQL string in app/ without its reason" do
    offences, = self.class.check(self.class.sources)

    assert_empty offences, <<~MESSAGE
      These lines build a query from SQL text. Say it in Active Record's own syntax if that
      says it exactly; otherwise build the Arel nodes through `SqlNodes` (app/values/sql_nodes.rb).
      Only where Arel has no node may the string stay, with `# sql: <why>` on the line or
      alone on the line above.

      #{offences.join("\n")}
    MESSAGE
  end

  test "every exemption still excuses something" do
    _, used = self.class.check(self.class.sources)

    FILES.each_key { |path| assert_includes used, [ :file, path ], "FILES[#{path.inspect}] excuses nothing any more: remove it" }
    NOT_SQL.each_key { |path| assert_includes used, [ :not_sql, path ], "NOT_SQL[#{path.inspect}] matches no line any more: remove it" }
  end

  # --- The guard itself --------------------------------------------------------

  def offences_in(source, path: "app/models/example.rb") = self.class.check(path => source).first

  test "a string handed to a query method is an offence, bare or on a receiver" do
    [
      %(scope :named, ->(name) { where("LOWER(tags.name) = ?", name) }),
      %(Tag.where("LOWER(tags.name) = ?", name)),
      %(Tag.where.not("tags.name IN (?)", names)),
      %(relation.joins("LEFT JOIN translation_states ON true")),
      %(relation.select("posts.*, 1 AS one")),
      %(relation.order("LOWER(tags.name) ASC")),
      %(relation.reorder('posts.id DESC')),
      %(relation.group("post_tags.tag_id").count),
      %(relation.having("COUNT(*) > 1")),
      %(relation.pluck("LOWER(name)")),
      %(relation.pick("COUNT(*)")),
      %(relation.where("\#{table}.id = 1")),
      %(relation.where(%(a = 1)))
    ].each { |line| assert_equal 1, offences_in("#{line}\n").size, line }
  end

  test "a string argument that opens on the next line, and a heredoc, are caught on the call's line" do
    assert_equal [ "app/models/example.rb:1: relation.where(" ], offences_in(%(relation.where(\n  "a = 1 " \\\n  "OR b = 2"\n)\n))
    assert_equal 1, offences_in("Page.where(<<~SQL.squish, id)\n  id = ?\nSQL\n").size
    assert_equal 1, offences_in("sql = <<~SQL\n  SELECT 1\nSQL\n").size
  end

  test "Arel.sql, the sanitizers that build SQL and a statement sent to the connection are caught" do
    [
      %(order(Arel.sql("posts_count DESC"))),
      %(Post.sanitize_sql_array([ "a = ?", 1 ])),
      %(ActiveRecord::Base.sanitize_sql([ "a = ?", 1 ])),
      %(sanitize_sql_for_conditions([ "a = ?", 1 ])),
      %(Post.find_by_sql(statement)),
      %(connection.select_value(statement)),
      %(connection.select_values(statement)),
      %(connection.select_rows(statement)),
      %(connection.select_all(statement)),
      %(connection.select_one(statement)),
      %(connection.exec_query(statement)),
      %(User.connection.execute(statement)),
      %(Page.with_connection { |c| c.execute(statement) })
    ].each { |line| assert_equal 1, offences_in("#{line}\n").size, line }
  end

  test "Active Record's own syntax and Arel nodes are not offences" do
    assert_empty offences_in(<<~RUBY)
      scope :named, ->(name) { where(arel_table[:name].lower.eq(name.to_s.downcase)) }
      Post.where(published_at: ..now).where.not(action: %w[a b]).order(updated_at: :desc, id: :desc)
      Post.joins(:tags).where(tags: { name: "ruby" }).group(:author_id).count
      Post.select(:id, :title).pluck(:id)
      Post.where(SqlNodes.like(Post.arel_table[:slug], SqlNodes.like_pattern(text)))
      Post.order(Post.arel_table[:title].lower.asc).pick(Arel.star.count)
      pattern = "%\#{sanitize_sql_like(text)}%"
      items.select { |item| item.name == "x" }.group_by(&:kind)
      settings.where_values_hash["name"]
      form.select_all_label("Posts")
    RUBY
  end

  test "SQL in a comment or in a message is not a query" do
    assert_empty offences_in(<<~RUBY)
      # where("LOWER(tags.name) = ?", name) is what this used to be; Arel.sql( too
      raise ArgumentError, 'use where("...") no more, nor connection.execute("...")'
    RUBY
  end

  test "a mark with a reason lets its own line through, or the line below when it stands alone" do
    assert_empty offences_in(%(connection.execute("LOCK TABLE users") # sql: Arel has no node for a table lock\n))
    assert_empty offences_in(%(# sql: upsert's ON CONFLICT clause takes SQL text\non_duplicate: Arel.sql("counter = counter + 1")\n))
    assert_equal [ %(app/models/example.rb:2: other.where("b = 2")) ],
      offences_in(%(one.where("a = 1") # sql: a reason of some length\nother.where("b = 2")\n))
    assert_equal 1, offences_in(%(x = 1 # sql: this mark belongs to the line it is on\nother.where("b = 2")\n)).grep(/other\.where/).size
  end

  test "a mark with a short reason, or with nothing to excuse, is an offence" do
    assert_equal 1, offences_in(%(one.where("a = 1") # sql: because\n)).grep(/needs a reason/).size
    assert_equal 1, offences_in(%(one.where("a = 1") # sql:\n)).grep(/needs a reason/).size
    assert_equal [ "app/models/example.rb:1: `# sql:` on a line with no SQL string or connection call" ],
      offences_in("one.where(a: 1) # sql: left over from before the conversion\n")
    assert_equal 1, offences_in("# sql: left over, with nothing below it\n\none.where(a: 1)\n").size
  end

  test "a template has no excuse" do
    offences = offences_in(%(<%= Post.where("a = 1").count %> <%# sql: a reason of some length %>\n), path: "app/views/example.html.erb")

    assert_equal 1, offences.size
    assert_match(/move the query to a model/, offences.first)
    assert_empty offences_in(%(<%= form.select :kind, options %>\n<input name="select_all">\n), path: "app/views/example.html.erb")
  end

  test "an excused file and a line that is not SQL are let through, and reported as used" do
    offences, used = self.class.check(
      "app/models/public_site/paths.rb" => %(Page.where(<<~SQL.squish, id)\n  id = ?\nSQL\n),
      "app/queries/jump/search.rb" => %([ group("Pages", rows) ]\nPost.group("posts.id")\n)
    )

    assert_equal [ %(app/queries/jump/search.rb:2: Post.group("posts.id")) ], offences
    assert_equal [ [ :file, "app/models/public_site/paths.rb" ], [ :not_sql, "app/queries/jump/search.rb" ] ], used.uniq
  end
end
