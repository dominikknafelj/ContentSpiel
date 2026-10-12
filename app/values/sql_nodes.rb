# The few SQL constructions Active Record's own syntax can't say, as Arel
# nodes, so a scope that needs one reads like the SQL it produces. The order of
# preference is Active Record, then Arel, then a SQL string (CLAUDE.md, "SQL
# fragments"): a hash condition, a range, `where.not`, `.or` or
# `where(id: relation.select(:id))` comes first; these are for a function, a
# jsonb operator, a LIKE, a row comparison, an EXISTS. What Arel already names
# is used as it is (`attribute.lower`, `.matches`, `.eq`, `.desc`).
#
# Pure functions returning nodes: nothing here touches a connection or patches
# Active Record. A Ruby value handed to one becomes a quoted literal, never
# SQL text. `test/values/sql_nodes_test.rb` pins the SQL of each.
module SqlNodes
  module_function

  # `'value'`: a Ruby value as a quoted literal; a node is passed through.
  def quoted(value) = Arel.arel_node?(value) ? value : Arel::Nodes.build_quoted(value)

  # `NAME(a, b)`: a SQL function over nodes and values.
  def function(name, *arguments) = Arel::Nodes::NamedFunction.new(name, arguments.map { |argument| quoted(argument) })

  # `column ->> 'key'`: one key of a jsonb column as text (NULL when absent).
  def json_text(column, key) = Arel::Nodes::InfixOperation.new("->>", column, quoted(key.to_s))

  # `(column -> 'key') @> '[value]'::jsonb`: whether the jsonb ARRAY at one key
  # of a column holds `value` (NULL, so false, when the key is absent).
  def json_array_contains(column, key, value)
    Arel::Nodes::Grouping.new(Arel::Nodes::InfixOperation.new("->", column, quoted(key.to_s)))
      .then { |array| Arel::Nodes::InfixOperation.new("@>", array, cast([ value ].to_json, "jsonb")) }
  end

  # `COALESCE(a, b)`: the first that is not NULL.
  def coalesce(*values) = function("COALESCE", *values)

  # `column @> CAST('{1,2}' AS integer[])`: an integer array column holds
  # every one of `values` (each forced through Integer, never text).
  def array_contains(column, values)
    Arel::Nodes::InfixOperation.new("@>", column, cast("{#{values.map { |value| Integer(value) }.join(",")}}", "integer[]"))
  end

  # `CAST(value AS type)`; `type` is a constant type name, never user text.
  def cast(value, type) = Arel::Nodes::NamedFunction.new("CAST", [ quoted(value).as(type) ])

  # `COUNT(*) FILTER (WHERE condition)`: one of several counts in one query.
  def count_where(condition) = Arel.star.count.filter(condition)

  # `(a, b)`: a row value, compared as a whole (`row(a, b).lt(row(x, y))`).
  def row(*values) = Arel::Nodes::Grouping.new(values.map { |value| quoted(value) })

  # `EXISTS (SELECT ...)` over a relation, which may refer to the outer table.
  def exists(relation) = relation.arel.exists

  # The LIKE pattern for "contains this text" (`prefix: true`: "starts with
  # it"), the text escaped so a typed `%`, `_` or `\` is only itself. The one
  # place a search escapes: a caller hands over what was typed.
  def like_pattern(text, prefix: false)
    "#{"%" unless prefix}#{ActiveRecord::Base.sanitize_sql_like(text.to_s)}%"
  end

  # `value LIKE 'pattern'`, case-sensitive (Arel's own `matches` is ILIKE on
  # Postgres); the pattern is `like_pattern`'s.
  def like(value, pattern) = value.matches(pattern, nil, true)

  # `EXISTS (SELECT 1 FROM jsonb_each_text(column) AS t WHERE <the block's
  # condition on t.value>)`: whether any VALUE of a jsonb object satisfies it
  # (`column::text` would also test the keys and the JSON punctuation).
  def any_json_value(column)
    entries = Arel::Table.new("t")
    Arel::SelectManager.new(function("jsonb_each_text", column).as("t")).project(1).where(yield(entries[:value])).exists
  end
end
