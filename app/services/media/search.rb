# The library search query (media library design spec §6): title, alt (any
# locale's jsonb value) and the original filename, one `:q` bind reused for
# all three ILIKEs -- there is no string interpolation of the search term
# anywhere in the SQL this builds, only the named bind Postgres substitutes
# safely.
#
# Pulled out of `Admin::MediaController` (Task 7) so the MCP `list_media_tool`,
# the ⌘K palette and the Media screen all search the same way without
# duplicating this SQL. `Media::Search.call(scope, query)` narrows any
# `Media::Asset` relation by the query alone; `Media::Search.new(...)` is the
# Media screen's form (the search plus a segment, and the segments' counts).
class Media::Search
  # The library's segments (round 3, Task 8, decision D13). `untranslated`
  # exists only while the site has a target language to be untranslated in.
  FILTERS = %w[all unused missing_alt untranslated mine].freeze

  # The query alone, on any relation: what the MCP `list_media_tool`, the ⌘K
  # palette and `Media::Search.new(...).results` all narrow by.
  def self.call(scope, query) = new(q: query, scope: scope).matching

  # `q` is the search text, `filter` one of `FILTERS` (anything else -- a
  # forged value, `untranslated` on a one-language site -- is `all`), `actor`
  # the viewer, whose own uploads "Mine" means (a token is its user). `scope`
  # is what is searched: kept images, with their variants preloaded, unless a
  # caller says otherwise.
  #
  # Only a String is a query (final fix wave, M8): a forged `?q[]=x` or
  # `?q[a]=x` arrives as an Array/Parameters, which `sanitize_sql_like`
  # can't take -- it's no search at all rather than a 500.
  def initialize(q: nil, filter: nil, actor: nil, scope: Media::Asset.kept.with_variants)
    @scope = scope
    @query = q.is_a?(String) ? q : nil
    @filter = FILTERS.include?(filter) && available?(filter) ? filter : "all"
    @user_id = (actor.is_a?(ApiToken) ? actor.user : actor)&.id
  end

  attr_reader :filter

  # The search AND the chosen segment.
  def results = segment(matching, filter)

  # `{ all:, unused:, missing_alt:, untranslated:, mine: }` in ONE query. They
  # respect the search but not the segment: "Missing alt 3" is what choosing
  # Missing alt would list. Kept images only (the scope), so a trashed image
  # is in no number. `untranslated` is 0 on a one-language site (the segment
  # is hidden there).
  def counts
    # `unscope(:includes)`: the default scope preloads variants, and a `pick`
    # over a relation with `includes` turns into an eager-loading join with a
    # `DISTINCT ... LIMIT 1` subselect -- one row's worth of counts.
    all, unused, missing_alt, untranslated, mine = matching.unscope(:includes, :order).pick(
      Arel.sql("COUNT(*)"),
      Arel.sql("COUNT(*) FILTER (WHERE #{UNUSED_SQL})"),
      Arel.sql("COUNT(*) FILTER (WHERE #{missing_alt_sql})"),
      Arel.sql("COUNT(*) FILTER (WHERE #{untranslated_sql})"),
      Arel.sql("COUNT(*) FILTER (WHERE #{mine_sql})")
    )
    { all: all, unused: unused, missing_alt: missing_alt, untranslated: untranslated, mine: mine }
  end

  # The title/alt/filename match (`#call`'s old body), on the scope.
  def matching
    return @scope if @query.blank?

    like = "%#{Media::Asset.sanitize_sql_like(@query)}%"
    # `jsonb_each_text(media_assets.alt)` unnests the translated `{locale =>
    # text}` hash into rows so ILIKE can test every language's value, not
    # just the one the caller happens to be viewing in -- an `EXISTS`
    # correlated subquery, not a join, so it can't multiply a matching
    # asset's own row for however many locales matched.
    #
    # `file_attachment: :blob` is the same association `Media::Asset
    # ::VARIANT_INCLUDES`/`#with_variants` already preload, joined here (not
    # `includes`d) purely to filter on `active_storage_blobs.filename` --
    # every asset has exactly one `file` attachment (`Media::Asset
    # #file_is_attached`), so the inner join can't drop or duplicate a row
    # the way joining a one-to-many association could.
    @scope.joins(file_attachment: :blob).where(
      "media_assets.title ILIKE :q " \
      "OR EXISTS (SELECT 1 FROM jsonb_each_text(media_assets.alt) AS alt(locale, value) WHERE alt.value ILIKE :q) " \
      "OR active_storage_blobs.filename ILIKE :q",
      q: like
    )
  end

  private

  # No `usages` row at all (`Media::Asset.unused`, as SQL for a FILTER).
  UNUSED_SQL = "NOT EXISTS (SELECT 1 FROM media_usages WHERE media_usages.media_asset_id = media_assets.id)".freeze

  def available?(name) = name != "untranslated" || Translations.target_locales.any?

  # The default-language alt is blank (absent, null or whitespace): an alt
  # written only in German is still "missing" while English is the default.
  def missing_alt_sql
    Media::Asset.sanitize_sql_array([ "COALESCE(btrim(media_assets.alt ->> ?), '') = ''", Locales.default.to_s ])
  end

  # `missing` in ANY target language, from the stored `translation_states`
  # rows; an image with no row reads complete, so it is not untranslated.
  def untranslated_sql
    return "FALSE" unless available?("untranslated")

    Translations::StateIndex.exists_in_any_locale_sql(Media::Asset, states: %w[missing], locales: Translations.target_locales)
  end

  def mine_sql = @user_id ? Media::Asset.sanitize_sql_array([ "media_assets.created_by_id = ?", @user_id ]) : "FALSE"

  def segment(scope, name)
    case name
    when "unused" then scope.where(UNUSED_SQL)
    when "missing_alt" then scope.where(missing_alt_sql)
    when "untranslated" then scope.where(untranslated_sql)
    when "mine" then scope.where(mine_sql)
    else scope
    end
  end
end
