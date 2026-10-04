module Admin
  # The post editor's tag chip input asks this what to offer while an editor
  # types (`Admin::ChipInputComponent`, design pass round 2): up to `LIMIT`
  # tag names, those that start with the typed text first, then those that
  # merely contain it, each with how many posts use it.
  #
  # Its own controller rather than a `TagsController` action: that one is the
  # Tags module and needs `tags.manage`. Tag names are not secret inside CS
  # Studio, so this is open to whoever has a field that takes one: a user who
  # holds `posts.read` (the post editor's tags), `pages.edit` (a post-list
  # block's tag filter) or `tags.manage` anywhere (`AccessControl.holds?`);
  # anyone else gets the 403. The post counts are only shown to someone who
  # may read posts -- for anyone else a count would be a misleading "0".
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

    before_action -> { forbidden! unless holds_any?(%w[posts.read pages.edit tags.manage]) }

    def index
      render json: rows
    end

    private

    def query = params[:q].to_s.strip.first(MAX_QUERY_LENGTH)

    # `sanitize_sql_like` keeps a typed `%`/`_` literal. The count is a
    # correlated subquery over the readable posts, so the tag list itself
    # stays one query (no per-tag count).
    def counts? = can?("posts.read")

    def count_hint(count) = "#{count} #{'post'.pluralize(count)}"

    def rows
      pattern = Tag.sanitize_sql_like(query.downcase)
      prefix_first = Arel.sql(ActiveRecord::Base.sanitize_sql_array([ "(LOWER(tags.name) LIKE ?) DESC", "#{pattern}%" ]))
      tags = Tag.where("LOWER(tags.name) LIKE ?", "%#{pattern}%").limit(LIMIT)

      # Without the right to read posts there is no count to show (and no need
      # to pay for the subquery): alphabetical within prefix-first.
      return tags.order(prefix_first, Arel.sql("LOWER(tags.name) ASC")).map { |tag| { value: tag.name, label: tag.name } } unless counts?

      counts = admin_scope(Post.all).joins(:post_tags).where("post_tags.tag_id = tags.id").select("COUNT(*)")
      tags.select("tags.name", Arel.sql("(#{counts.to_sql}) AS posts_count"))
        .order(prefix_first, Arel.sql("posts_count DESC"), Arel.sql("LOWER(tags.name) ASC"))
        .map { |tag| { value: tag.name, label: tag.name, hint: count_hint(tag.posts_count) } }
    end
  end
end
