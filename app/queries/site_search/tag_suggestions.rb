module SiteSearch
  # The tags a suggestion offers (search 2 spec §4.3), ContentSpiel's own
  # whatever the backend: a tag's name and which live posts carry it are
  # the site's own tables, read alike for every engine, so the backend
  # contract does not carry them.
  #
  # A tag whose name begins with the prefix (`Tag.name_starting`, the
  # prefix a bind) and that a post a visitor of `language` sees at `now`
  # carries IN ITS COPY IN FORCE: the newest copy whose time has come of a
  # post that is kept and published, with a current address in the
  # language under a listing page no page above which is unpublished (the
  # rule `Postgres::Visible` applies to a post's entry). So a tag only a
  # draft, a scheduled post, a trashed post or an unpublished change
  # carries is never offered. Tag names are not translated: "in the
  # visitor's language" is carried by a post live in it. A suggestion names
  # the tag's current name and finds its posts by id, even where a copy
  # still holds an old name.
  #
  # ONE STATEMENT: the tags, with `EXISTS` over the copies, whose
  # `tag_ids @> ARRAY[tags.id]` `index_published_versions_on_tag_ids` serves.
  class TagSuggestions
    def initialize(text:, language:, now:, limit:)
      @text = text
      @language = language.to_s
      @now = now
      @limit = limit
    end

    def tags = Tag.name_starting(@text).where(carried).by_name.limit(@limit).to_a # public: rows (a tag's current name is the tag's row; which posts carry it is read from their copies)

    private

    def carried
      versions = Publishing::Version.arel_table
      newest = Publishing::Version.unscoped.where(record_type: "Post").in_force(@now).group(:record_id).select(versions[:id].maximum)
      copies = Publishing::Version.unscoped.where(id: newest)
        .where(SqlNodes.array_contains_column(versions[:tag_ids], Tag.arel_table[:id])) # public: rows (the tag ids the copy in force carries, against the tag being offered)
        .where(record_id: Post.kept.where(published_at: ..@now).select(:id)) # public: rows (the trash and the publication time are the rows')
        .where(SqlNodes.exists(addressed(versions[:record_id])))
      SqlNodes.exists(copies.select(:id))
    end

    # A current address of the post in the language, under a listing page
    # with no page above it, or itself, unpublished.
    def addressed(post_id)
      paths = PublicPath.arel_table
      hierarchy = PageHierarchy.arel_table
      hidden = PageHierarchy.where(hierarchy[:descendant_id].eq(paths[:listed_on_id]))
        .where.not(ancestor_id: Page.where(published_at: ..@now).select(:id)).select(:ancestor_id) # public: rows (whether a page is visible is its tree and publish state)
      PublicPath.where(record_type: Post.polymorphic_name, locale: @language, current: true).where(paths[:record_id].eq(post_id))
        .where.not(listed_on_id: nil).where(SqlNodes.exists(hidden).not).select(:id)
    end
  end
end
