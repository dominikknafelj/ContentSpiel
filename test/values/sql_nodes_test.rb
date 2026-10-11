require "test_helper"

# `SqlNodes` builds the constructions Active Record has no syntax for; each is
# pinned here by the SQL it produces, so a call site can be read as that SQL.
class SqlNodesTest < ActiveSupport::TestCase
  setup do
    @pages = Page.arel_table
    @events = Audit::Event.arel_table
  end

  test "quoted turns a value into a literal and leaves a node alone" do
    assert_equal "'it''s'", sql(SqlNodes.quoted("it's"))
    assert_equal "NULL", sql(SqlNodes.quoted(nil))
    assert_equal %("pages"."id"), sql(SqlNodes.quoted(@pages[:id]))
  end

  test "function calls a SQL function over nodes and quoted values" do
    assert_equal %(jsonb_path_exists("pages"."title", '$.*')), sql(SqlNodes.function("jsonb_path_exists", @pages[:title], "$.*"))
  end

  test "json_text reads one key of a jsonb column, the key quoted" do
    assert_equal %("pages"."title" ->> 'de'), sql(SqlNodes.json_text(@pages[:title], :de))
    assert_equal %("pages"."title" ->> 'd''e'), sql(SqlNodes.json_text(@pages[:title], "d'e"))
    assert_equal %("pages"."title" ->> 'de' ILIKE '%x%'), sql(SqlNodes.json_text(@pages[:title], "de").matches("%x%"))
  end

  test "json_array_contains asks whether a jsonb array at one key holds a value" do
    assert_equal %(("audit_events"."metadata" -> 'deleted_block_ids') @> CAST('[7]' AS jsonb)), sql(SqlNodes.json_array_contains(@events[:metadata], :deleted_block_ids, 7))
  end

  test "coalesce takes nodes and values" do
    assert_equal %(COALESCE(LOWER("pages"."content_type"), '')), sql(SqlNodes.coalesce(@pages[:content_type].lower, ""))
  end

  test "cast names the type" do
    assert_equal %(CAST("pages"."title" AS text)), sql(SqlNodes.cast(@pages[:title], "text"))
    assert_equal "CAST('{}' AS jsonb)", sql(SqlNodes.cast("{}", "jsonb"))
  end

  test "count_where is a filtered count" do
    assert_equal %(COUNT(*) FILTER (WHERE "pages"."published_at" IS NULL)), sql(SqlNodes.count_where(@pages[:published_at].eq(nil)))
  end

  test "row is a row value, and two of them compare as a whole" do
    moment = Time.utc(2026, 10, 7, 12, 30, 15)
    older = SqlNodes.row(@events[:last_occurred_at], @events[:id]).lt(SqlNodes.row(moment, 42))

    assert_equal %(("audit_events"."last_occurred_at", "audit_events"."id") < ('2026-10-07 12:30:15', 42)), sql(older)
  end

  test "exists wraps a relation, which may refer to the outer table" do
    blocks = ContentBlock.where(ContentBlock.arel_table[:owner_id].eq(@pages[:id])).select(:id)

    assert_equal %(EXISTS (SELECT "content_blocks"."id" FROM "content_blocks" WHERE "content_blocks"."owner_id" = "pages"."id")),
      sql(SqlNodes.exists(blocks))
  end

  test "like_pattern escapes the wildcards and the escape character, once" do
    assert_equal "%50\\%\\_o\\\\ff%", SqlNodes.like_pattern("50%_o\\ff")
    assert_equal "50\\%%", SqlNodes.like_pattern("50%", prefix: true)
    assert_equal "%%", SqlNodes.like_pattern(nil)
    assert_equal "%it's%", SqlNodes.like_pattern("it's"), "a quote is the literal's business, not the pattern's"
  end

  test "like is case-sensitive, where matches is ILIKE" do
    assert_equal %(LOWER("pages"."content_type") LIKE 'bl\\%%'), sql(SqlNodes.like(@pages[:content_type].lower, SqlNodes.like_pattern("bl%", prefix: true)))
  end

  test "any_json_value tests the values of a jsonb object, not its keys" do
    node = SqlNodes.any_json_value(@pages[:title]) { |value| value.matches("%x%") }

    assert_equal %(EXISTS (SELECT 1 FROM jsonb_each_text("pages"."title") AS t WHERE "t"."value" ILIKE '%x%')), sql(node)
  end

  private

  # An attribute has no `to_sql` of its own; the connection's visitor renders any node.
  def sql(node) = ActiveRecord::Base.connection.visitor.compile(node)
end
