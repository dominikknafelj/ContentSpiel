module Admin
  # The Tags module (cs-studio spec §4.1/§5.3): a flat list of every tag with
  # its post count, each row its own autosaving rename form (the same
  # `AutosaveResponses` shape `PagesController`/`ContentBlocksController`
  # use, minus the locale switching neither a tag's name nor its post count
  # has any use for -- a tag has no translated attributes) plus a row menu
  # (⋯) that opens the list's one Merge dialog and one Delete dialog
  # (`admin--tag-dialogs` fills them from the row). There is no `:show`/`:new`/
  # `:create`: a tag has no editor screen of its own, and new tags are only
  # ever created in passing, through a post's `tag_names` (`Posts::Save`).
  class TagsController < BaseController
    include AutosaveResponses

    # The module is `tags.manage` (access-control design spec §3.4);
    # `Tags::*` check it again for every write.
    before_action -> { require_permission("tags.manage") }

    # `LOWER(tags.name)`, not the plain column: matches the case-insensitive
    # ordering an editor actually expects from a list of lowercase-stored
    # names, and the same comparison `BlockTypes::PostList` already makes
    # when matching a tag by name.
    #
    # Two numbers per tag, each one grouped query for the whole list (never
    # one per row):
    # - `@readable_counts`, the "Posts" column: KEPT posts the VIEWER may read
    #   (`AccessControl.scope`, so a trashed post and one out of the viewer's
    #   scope are not counted), because that column links to the posts list,
    #   which is read-scoped the same way -- the number and the list it opens
    #   must agree.
    # - `@carrier_counts`, the dialogs' "N posts": every post carrying the tag,
    #   trashed ones too, because a delete or a merge reaches all of them and
    #   `tag.merged` records exactly that number. Neither count is computed for
    #   a viewer who can't read posts at all (the views then show no figure --
    #   for them a count would be a misleading zero, or leak how many posts
    #   they can't see; `Admin::TagSuggestionsController` makes the same call).
    def index
      @tags = Tag.order(Arel.sql("LOWER(tags.name)")).to_a  # i18n-ok: SQL
      @counts_visible = can?("posts.read")
      ids = @tags.map(&:id)
      return @readable_counts = @carrier_counts = {} unless @counts_visible && ids.any?

      @readable_counts = admin_scope(Post.all).joins(:post_tags).where(post_tags: { tag_id: ids }).group("post_tags.tag_id").count
      @carrier_counts = PostTag.where(tag_id: ids).group(:tag_id).count
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

      render turbo_stream: streams, status: autosave_status(result)
    end

    # Permanent (spec §7's "No trash" interim state) -- the shared delete
    # dialog already told the editor how many posts would lose the tag before
    # this request was ever sent. `Tags::Destroy` (not a bare `tag.destroy`) is
    # what re-syncs the same tag-filtered listings `update` above relies on
    # `Tags::Rename` for.
    #
    # The answer removes the row and says so in a toast; the dialog it was
    # confirmed in lives outside the row now (one for the whole list), so
    # `admin--tag-dialogs` closes it when this submission succeeds.
    #
    # A refusal (a stale tab whose `tags.manage` was taken away) leaves the
    # row in place and answers 403, rather than removing a tag that still
    # exists.
    def destroy
      tag = Tag.find(params[:id])
      result = Tags::Destroy.call(tag)
      return head(result.denied? ? :forbidden : :unprocessable_entity) unless result.ok?

      render turbo_stream: [
        turbo_stream.remove(ActionView::RecordIdentifier.dom_id(tag)),
        toast_stream(t("admin.tags.toasts.deleted", name: tag.name))
      ]
    end

    # Merge into another tag (`Tags::Merge`). The source is the row's tag
    # (an id that no longer exists is the ordinary 404, never a 500); the
    # target arrives by NAME, as the picker's suggestions (`tags/suggest`) are
    # names, and a name that matches no tag any more is a plain refusal like the
    # service's own (the same tag, none chosen, a tag deleted meanwhile). Every
    # answer is a 303 back to the list with a toast, so a Turbo form submission
    # renders it as a visit and the merged row is simply gone; a refusal for want
    # of permission is the 403 page, as everywhere else.
    def merge
      source = Tag.find(params[:id])
      name = params[:into].to_s.strip.downcase
      # By `LOWER(name)`, the comparison every other match on a tag name makes
      # (`index`'s ordering, `BlockTypes::PostList`): names are stored
      # lowercase today, but one stored with a capital (an old row, a write
      # around the model) must still be found by the name the picker shows.
      into = Tag.where("LOWER(name) = ?", name).order(:id).first if name.present?  # i18n-ok: SQL

      result = Tags::Merge.call(source, into: into)
      return forbidden!(result.errors.first) if result.denied?

      if result.ok?
        flash[:notice] = t("admin.tags.toasts.merged", source: source.name, into: into.name)
      else
        flash[:alert] = name.present? && into.nil? ? Tags::Merge::GONE : result.errors.first
      end
      redirect_to admin_tags_path(**admin_url_options), status: :see_other
    end

    private

    def forbidden_status_id = action_name == "update" ? "tag-#{params[:id].to_i}-save-status" : nil

    def row_status_id(tag) = "tag-#{tag.id}-save-status"

    def row_error_prefix(tag) = "tag-#{tag.id}"
  end
end
