module Admin
  # The Tags module (cs-studio spec §4.1/§5.3): a flat list of every tag with
  # its post count, each row its own autosaving rename form (the same
  # `AutosaveResponses` shape `PagesController`/`ContentBlocksController`
  # use, minus the locale switching neither a tag's name nor its post count
  # has any use for -- a tag has no translated attributes) plus a delete
  # gated behind `ConfirmDialogComponent`. There is no `:show`/`:new`/
  # `:create`: a tag has no editor screen of its own, and new tags are only
  # ever created in passing, through a post's `tag_names` (`Posts::Save`).
  class TagsController < BaseController
    include AutosaveResponses

    # `LOWER(tags.name)`, not the plain column: matches the case-insensitive
    # ordering an editor actually expects from a list of lowercase-stored
    # names, and the same comparison `BlockTypes::PostList` already makes
    # when matching a tag by name. `LEFT JOIN` + `COUNT`, not `tag.posts.
    # count` per row (an N+1 the same size as the list itself), and grouped
    # by `tags.id` alone -- Postgres allows every other `tags.*` column in
    # the `SELECT` list once the `GROUP BY` names the table's primary key
    # (the "functional dependency" rule), so this needs no `MAX()`/`array_
    # agg()` wrapper around the rest of the row.
    def index
      @tags = Tag.left_joins(:post_tags)
        .select("tags.*, COUNT(post_tags.id) AS posts_count")
        .group(:id)
        .order(Arel.sql("LOWER(tags.name)"))
    end

    # Inline rename (spec §5.3): PATCHes on blur/debounce like every other
    # autosave form, and answers the same Turbo Stream shape --
    # `Tags::Rename` (not a bare `tag.update`) is what actually re-syncs the
    # public paths a tag-filtered listing depends on, closing the foundations
    # follow-up "tag rename doesn't resync" this task exists to fix.
    def update
      tag = Tag.find(params[:id])
      result = Tags::Rename.call(tag, name: params.dig(:tag, :name))

      streams = autosave_stream(
        record: result.record,
        result: result,
        status_id: row_status_id(tag),
        error_prefix: row_error_prefix(tag),
        base_updated_at: params[:base_updated_at],
        fields: { name: [ :name ] }
      )

      render turbo_stream: streams, status: (result.ok? ? :ok : :unprocessable_entity)
    end

    # Permanent (spec §7's "No trash" interim state) -- the row's own
    # `ConfirmDialogComponent` already told the editor how many posts would
    # lose the tag before this request was ever sent. `Tags::Destroy` (not a
    # bare `tag.destroy`) is what re-syncs the same tag-filtered listings
    # `update` above relies on `Tags::Rename` for.
    def destroy
      tag = Tag.find(params[:id])
      Tags::Destroy.call(tag)
      render turbo_stream: turbo_stream.remove(ActionView::RecordIdentifier.dom_id(tag))
    end

    private

    def row_status_id(tag) = "tag-#{tag.id}-save-status"

    def row_error_prefix(tag) = "tag-#{tag.id}"
  end
end
