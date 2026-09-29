# The library search query (media library design spec §6): title, alt (any
# locale's jsonb value) and the original filename, one `:q` bind reused for
# all three ILIKEs -- there is no string interpolation of the search term
# anywhere in the SQL this builds, only the named bind Postgres substitutes
# safely.
#
# Pulled out of `Admin::MediaController#search` (Task 7) so the MCP
# `list_media_tool` (Task 9) can search the same way without duplicating
# this SQL -- both callers hand it a `Media::Asset` relation (already
# scoped/filtered however they like) and get the same relation narrowed by
# `query`.
class Media::Search
  def self.call(scope, query) = new(scope, query).call

  # Only a String is a query (final fix wave, M8): a forged `?q[]=x` or
  # `?q[a]=x` arrives as an Array/Parameters, which `sanitize_sql_like`
  # can't take -- it's no search at all rather than a 500.
  def initialize(scope, query)
    @scope = scope
    @query = query.is_a?(String) ? query : nil
  end

  def call
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
end
