module Admin
  # The post editor's tag chip input asks this what to offer while an editor
  # types (`Admin::ChipInputComponent`, design pass round 2): up to `LIMIT`
  # tag names, those that start with the typed text first, then those that
  # merely contain it, each with how many posts use it.
  #
  # Its own controller rather than a `TagsController` action: that one is the
  # Tags module and needs `tags.manage`, while whoever can edit a post's tags
  # needs only to *read* posts (`posts.read`) to be offered the names.
  #
  # The counts are over kept posts the viewer may read
  # (`AccessControl.scope` hides trashed ones and ones out of scope, "not
  # found, not forbidden"), but a tag is never hidden by its count: a tag
  # exists independently of its posts, so one only trashed posts use still
  # shows, as "0 posts" -- picking it re-attaches an existing name rather than
  # creating a near-duplicate.
  class TagSuggestionsController < BaseController
    LIMIT = 8
    # Longer than any tag name worth matching; keeps a pasted paragraph from
    # becoming a huge ILIKE pattern.
    MAX_QUERY_LENGTH = 100

    before_action -> { require_permission("posts.read") }

    def index
      render json: rows
    end

    private

    def query = params[:q].to_s.strip.first(MAX_QUERY_LENGTH)

    # `sanitize_sql_like` keeps a typed `%`/`_` literal. The count is a
    # correlated subquery over the readable posts, so the tag list itself
    # stays one query (no per-tag count).
    def rows
      counts = admin_scope(Post.all).joins(:post_tags).where("post_tags.tag_id = tags.id").select("COUNT(*)")
      pattern = Tag.sanitize_sql_like(query.downcase)

      Tag.where("LOWER(tags.name) LIKE ?", "%#{pattern}%")
        .select("tags.name", Arel.sql("(#{counts.to_sql}) AS posts_count"))
        .order(Arel.sql(ActiveRecord::Base.sanitize_sql_array([ "(LOWER(tags.name) LIKE ?) DESC", "#{pattern}%" ])), Arel.sql("posts_count DESC"), Arel.sql("LOWER(tags.name) ASC"))
        .limit(LIMIT)
        .map { |tag| { value: tag.name, label: tag.name, hint: "#{tag.posts_count} #{'post'.pluralize(tag.posts_count)}" } }
    end
  end
end
