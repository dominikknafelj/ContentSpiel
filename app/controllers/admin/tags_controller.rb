module Admin
  # The Tags module: a flat list of every tag with its post count and usage
  # bar, each row its own autosaving rename form (the same
  # `AutosaveResponses` shape `PagesController`/`ContentBlocksController`
  # use, minus the locale switching neither a tag's name nor its post count
  # has any use for -- a tag has no translated attributes) and a Details link
  # that opens the tag's detail in the list's rail (`show`, the `tag-detail`
  # frame): its posts, and the triggers of the list's one Merge dialog and
  # one Delete dialog (`admin--tags--dialogs` fills them from the trigger).
  # There is no `:new`/`:create`: a tag has no editor screen of its own, and
  # new tags are only ever created in passing, through a post's `tag_names`
  # (`Posts::Save`).
  class TagsController < BaseController
    include AutosaveResponses

    # The module's permission is `tags.manage`; `Tags::*` check it again for
    # every write.
    before_action -> { require_permission("tags.manage") }

    # `LOWER(tags.name)`, not the plain column: matches the case-insensitive
    # ordering an editor actually expects from a list of lowercase-stored
    # names, and the same comparison `BlockTypes::PostList` already makes
    # when matching a tag by name.
    #
    # `@readable_counts`, the "Posts" column and its usage bars, is one
    # grouped query for the whole list (never one per row): KEPT posts the
    # VIEWER may read (`AccessControl.scope`, so a trashed post and one out of
    # the viewer's scope are not counted), because that column links to the
    # posts list, which is read-scoped the same way -- the number and the list
    # it opens must agree. It is not computed for a viewer who can't read
    # posts at all (the view then shows no figure and no bar -- for them a
    # count would be a misleading zero, or leak how many posts they can't
    # see; `Admin::TagSuggestionsController` makes the same call).
    def index
      @tags = Tag.by_name.to_a
      @counts_visible = can?("posts.read")
      ids = @tags.map(&:id)
      return @readable_counts = {} unless @counts_visible && ids.any?

      @readable_counts = Tag.posts_counts(admin_scope(Post.all), ids)
    end

    # The tag's detail, for the list's rail and nowhere else: a request that
    # is not the `tag-detail` frame's (no JavaScript, a typed address) goes
    # back to the list, since the detail is a part of the Tags screen and not
    # a page of its own.
    def show
      tag = Tag.find(params[:id])
      unless turbo_frame_request_id == Admin::TagsScreen::DetailComponent::FRAME_ID
        return redirect_to(admin_tags_path(**admin_url_options), status: :see_other)
      end

      render :show, locals: { detail: detail_component(tag) }, layout: false
    end

    # Inline rename: PATCHes on blur/debounce like every other autosave form,
    # and answers the same Turbo Stream shape -- `Tags::Rename` (not a bare
    # `tag.update`) is what re-syncs the public paths a tag-filtered listing
    # depends on. A saved rename also draws the tag's detail again, by the
    # tag's id: when it is the one open in the rail, its heading, "Show all"'s
    # address and the dialogs' triggers then name the new name; when it is
    # not, the stream finds no target and does nothing. The row's Details
    # link and its name's label for a screen reader are drawn again too, so
    # both name the tag as it is called now; the input itself is never
    # replaced, since it is what is being typed in.
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
      if result.ok?
        streams << turbo_stream.replace(detail_id(tag), detail_component(result.record))
        streams << turbo_stream.replace("tag-#{tag.id}-details", partial: "admin/tags/details_link", locals: { tag: result.record })
        streams << turbo_stream.replace("tag-#{tag.id}-name-label", partial: "admin/tags/name_label", locals: { tag: result.record })
      end

      render turbo_stream: streams, status: autosave_status(result)
    end

    # Permanent: there is no trash for a tag, and the shared delete dialog
    # already told the editor how many posts would lose the tag before this
    # request was ever sent. `Tags::Destroy` (not a bare `tag.destroy`) is
    # what re-syncs the same tag-filtered listings `update` above relies on
    # `Tags::Rename` for.
    #
    # The answer removes the row, puts the rail back to its empty line when
    # the rail showed this tag (by the tag's id: otherwise there is no target
    # and nothing changes), draws the list's empty state when no tag is left,
    # and says so in a toast. The dialog it was confirmed in lives outside the
    # list (one for the whole list), so `admin--tags--dialogs` closes it when
    # this submission succeeds. The empty state is drawn by this answer and
    # never by a visit of the screen's address, which Turbo could answer with
    # a prefetch of the list from before the delete.
    #
    # A refusal (a stale tab whose `tags.manage` was taken away) leaves the
    # row in place and answers 403, rather than removing a tag that still
    # exists.
    def destroy
      tag = Tag.find(params[:id])
      result = Tags::Destroy.call(tag)
      return head(Admin::RefusalStatus.for(result)) unless result.ok?

      streams = [
        turbo_stream.remove(ActionView::RecordIdentifier.dom_id(tag)),
        turbo_stream.replace(detail_id(tag), Admin::TagsScreen::EmptyDetailComponent.new)
      ]
      streams << turbo_stream.replace("tags-list", partial: "admin/tags/empty") unless Tag.exists?
      streams << toast_stream(t("admin.tags.toasts.deleted", name: tag.name))
      render turbo_stream: streams
    end

    # Merge into another tag (`Tags::Merge`). The source is the detail's tag
    # (an id that is gone is the ordinary 404, never a 500); the
    # target arrives by NAME, as the picker's suggestions (`tags/suggest`) are
    # names, and a name that matches no tag any more is a plain refusal like the
    # service's own (the same tag, none chosen, a tag deleted meanwhile). Every
    # answer is a 303 back to the list with a toast, so a Turbo form submission
    # renders it as a visit and the merged row is simply gone; a refusal for want
    # of permission is the 403 page, as everywhere else.
    def merge
      source = Tag.find(params[:id])
      name = params[:into].to_s.strip
      # Case-insensitively (`Tag.named`), the comparison every other match on a
      # tag name makes (`index`'s ordering, `BlockTypes::PostList`): names are
      # stored lowercase today, but one stored with a capital (an old row, a
      # write around the model) must still be found by the name the picker shows.
      into = Tag.named(name).order(:id).first if name.present?

      result = Tags::Merge.call(source, into: into)
      return forbidden!(result.errors.first) if result.denied?

      if result.ok?
        flash[:notice] = t("admin.tags.toasts.merged", source: source.name, into: into.name)
      else
        flash[:alert] = name.present? && into.nil? ? Tags::Merge.gone : result.errors.first
      end
      redirect_to admin_tags_path(**admin_url_options), status: :see_other
    end

    private

    def forbidden_status_id = action_name == "update" ? "tag-#{params[:id].to_i}-save-status" : nil

    def row_status_id(tag) = "tag-#{tag.id}-save-status"

    def row_error_prefix(tag) = "tag-#{tag.id}"

    def detail_id(tag) = "tag-detail-#{tag.id}"

    # The detail's posts are the posts list's own (`Posts::List` with the
    # tag's name as its `tag` filter), so the rail's count and "Show all"'s
    # number are the list's All count for that filter, and its rows are the
    # viewer's kept, readable posts. `carriers` is every post carrying the
    # tag, trashed ones too: the number a delete or merge reaches, which the
    # dialogs' sentences say. None of the three is read for a viewer without
    # `posts.read` (see `index`).
    def detail_component(tag)
      posts, count, carriers = [], nil, nil
      if can?("posts.read")
        list = Posts::List.new(admin_scope(Post.all), filters: { "tag" => tag.name }, locale: admin_locale)
        posts = list.rows(limit: Admin::TagsScreen::DetailComponent::DETAIL_POSTS)
        count = list.counts["all"]
        carriers = PostTag.where(tag_id: tag.id).count
      end
      Admin::TagsScreen::DetailComponent.new(tag:, posts:, count:, carriers:, url_options: admin_url_options, locale: admin_locale)
    end
  end
end
