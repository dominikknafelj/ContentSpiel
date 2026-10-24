# The library search query (media library design spec §6): title, alt (any
# locale's jsonb value) and the original filename, one pattern for all three
# ILIKEs. Every condition here is an Arel node (`SqlNodes`), so the search
# term and the viewer's id reach the query as quoted values and there is no
# SQL text to interpolate anything into.
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
    # `COUNT(*), COUNT(*) FILTER (WHERE <segment>), ...`: the segments' own
    # conditions, the ones `#segment` narrows by.
    all, unused, missing_alt, untranslated, mine = matching.unscope(:includes, :order).pick(
      Arel.star.count, *%w[unused missing_alt untranslated mine].map { |name| SqlNodes.count_where(condition(name)) }
    )
    { all: all, unused: unused, missing_alt: missing_alt, untranslated: untranslated, mine: mine }
  end

  # Whether the library holds a kept image at all, search and segment aside
  # (the Media screen draws its drop zone only while this is false). Without
  # search text the `counts` already hold the answer; under a search they are
  # the search's, and a search that finds nothing would read as an empty
  # library, so that path asks the scope itself, one `SELECT 1 ... LIMIT 1`
  # (`unscope(:includes)`: the default scope preloads variants). The scope is
  # kept images only, so a library whose images are all in the trash is empty.
  def any_images?(counts:)
    return counts[:all].positive? if @query.blank?

    @scope.unscope(:includes).exists?
  end

  # The title/alt/filename match (`#call`'s old body), on the scope.
  def matching
    return @scope if @query.blank?

    pattern = SqlNodes.like_pattern(@query)
    # `jsonb_each_text(media_assets.alt)` (`SqlNodes.any_json_value`) unnests
    # the translated `{locale => text}` hash into rows so ILIKE can test every
    # language's value, not just the one the caller happens to be viewing in
    # -- an `EXISTS` correlated subquery, not a join, so it can't multiply a
    # matching asset's own row for however many locales matched.
    #
    # `file_attachment: :blob` is the same association `Media::Asset
    # ::VARIANT_INCLUDES`/`#with_variants` already preload, joined here (not
    # `includes`d) purely to filter on `active_storage_blobs.filename` --
    # every asset has exactly one `file` attachment (`Media::Asset
    # #file_is_attached`), so the inner join can't drop or duplicate a row
    # the way joining a one-to-many association could.
    @scope.joins(file_attachment: :blob).where(
      assets[:title].matches(pattern)
        .or(SqlNodes.any_json_value(assets[:alt]) { |value| value.matches(pattern) })
        .or(ActiveStorage::Blob.arel_table[:filename].matches(pattern))
    )
  end

  private

  def assets = Media::Asset.arel_table

  def available?(name) = name != "untranslated" || Translations.target_locales.any?

  # A segment's condition on `media_assets`, one definition for the list
  # (`#segment`) and for its number (`#counts`).
  def condition(name)
    case name
    when "unused" then unused
    when "missing_alt" then missing_alt
    when "untranslated" then untranslated
    when "mine" then mine
    end
  end

  # No `usages` row at all (what `Media::Asset.unused` lists, as a condition a
  # FILTER can take): `NOT EXISTS (SELECT 1 FROM media_usages WHERE
  # media_usages.media_asset_id = media_assets.id)`.
  def unused
    SqlNodes.exists(Media::Usage.where(Media::Usage.arel_table[:media_asset_id].eq(assets[:id])).select(1)).not
  end

  # The default-language alt is blank (absent, null or whitespace): an alt
  # written only in German is still "missing" while English is the default.
  # `COALESCE(alt ->> 'en', '') !~ '\S'`.
  #
  # "Whitespace" as Ruby's `String#strip` means it, because that is what the
  # tile's NO ALT chip and the panel's warning use (`TileComponent#no_alt?`,
  # `PanelComponent#alt_warn?`): `!~ '\S'` is "holds no non-whitespace
  # character". Postgres's one-argument `btrim` removes spaces only, so an alt
  # of a newline or a tab wore the chip without being listed here.
  def missing_alt
    SqlNodes.coalesce(SqlNodes.json_text(assets[:alt], Locales.default), "").does_not_match_regexp("\\S")
  end

  # `missing` in ANY target language, from the stored `translation_states`
  # rows; an image with no row reads complete, so it is not untranslated.
  def untranslated
    return Arel::Nodes::False.new unless available?("untranslated")

    Translations::StateIndex.exists_in_any_locale_sql(Media::Asset, states: %w[missing], locales: Translations.target_locales)
  end

  # The viewer's own uploads; nobody's when there is no viewer.
  def mine = @user_id ? assets[:created_by_id].eq(@user_id) : Arel::Nodes::False.new

  def segment(scope, name) = name == "all" ? scope : scope.where(condition(name))
end
