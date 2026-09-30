module Admin
  # The Media module (media library design spec §6, Task 7): the grid
  # (search, filters, pagination), one image's detail panel, and its own
  # multi-file upload -- every write still goes through `Media::Upload`/
  # `Save`/`Trash::Move` (`Admin::BaseController`'s own "every write goes
  # through a service" rule), this controller only ever translates params
  # and renders their `Result`.
  #
  # `media.upload` is what gates *opening* the module at all (design spec
  # §6: "in the sidebar for anyone with media.upload") -- browsing the
  # whole library needs no scoping the way Pages/Posts do (there is no
  # per-asset "read" permission), so `index`/`show`/`create` share one
  # `require_permission`. Editing and deleting are gated per §5.1 instead,
  # inside `Media::Save`/`Trash::Move`/`Trash::Purge` themselves (`Media::Ownership`:
  # `media.manage`, or the asset's own uploader) -- a denial from either
  # comes back as an ordinary 403/422, exactly like every other module's
  # write.
  class MediaController < BaseController
    include AutosaveResponses

    # "About 48 per page" (design spec §6). Same plain limit/offset shape
    # as `Admin::AuditEventsController` -- fetching one extra row is how
    # `@has_next` is known without a separate `COUNT(*)`.
    PER_PAGE = 48

    before_action -> { require_permission("media.upload") }, only: %i[index show create]
    before_action :set_asset, only: %i[show update destroy]

    # The grid (design spec §6): search (title, alt in any locale,
    # filename) and the all/unused/mine filters, newest first.
    # `Media::Asset.with_variants` is what keeps this a constant number of
    # queries whether the page holds 10 assets or 60 -- see that scope's
    # own comment; every grid render (this action, and every filtered
    # re-render of it) must load through it, never a bare `Media::Asset
    # .all`, or `Admin::MediaLibrary::GridComponent#thumbnail_url`'s own `#srcset`
    # call turns straight back into the N+1 the scope exists to prevent.
    #
    # `picker=1` (Task 8) is the same listing for `Media::PickerComponent`'s
    # Library tab: the grid, search and pagination, rendered on their own
    # inside the picker's `<turbo-frame>` (`admin/media/picker`, no layout)
    # with pick buttons instead of detail links. Deliberately this endpoint
    # rather than a second one: one search, one set of filters, one
    # constant-query load (`filtered_assets`), and the same `media.upload`
    # gate -- the picker's only permission is "may browse and choose".
    def index
      @assets = filtered_assets.order(id: :desc).limit(PER_PAGE + 1).offset(offset).to_a
      @has_next = @assets.size > PER_PAGE
      @assets = @assets.first(PER_PAGE)
      @offset = offset

      render :picker, layout: false if params[:picker].present?
    end

    def show
    end

    # The grid's own multi-file upload (design spec §6, global
    # constraints): one request per file -- `admin--media-upload` calls
    # this once per selected/dropped file, never a batch -- so a refused
    # or oversized file never blocks its siblings and gets its own inline
    # error rather than one dialog for a whole batch. JSON either way,
    # same shape `Admin::MediaAssetsController#create` already answers
    # with (that controller's own JSON contract is the Tiptap editor's,
    # this one the grid's own JS controller's -- two different callers,
    # deliberately not merged into one endpoint, per that resource's own
    # routing comment).
    def create
      result = Media::Upload.call(file: params[:file])

      if result.ok?
        render json: { id: result.record.id, title: result.record.title }, status: :created
      else
        render json: { errors: result.errors }, status: result.denied? ? :forbidden : :unprocessable_entity
      end
    end

    # The detail panel's own autosave endpoint (design spec §6): `title`
    # (untranslated) plus `alt`/`caption` for whichever locale is being
    # edited, through `Media::Save` -- which itself falls back to 403 for
    # anyone but `media.manage` or this asset's own uploader (`Media
    # ::Ownership`). The view only ever renders an editable form for
    # someone `Admin::MediaLibrary::DetailComponent#editable?` already agrees can
    # save -- a denial here is therefore only ever a stale tab (rights
    # taken away, or someone else's upload) resending a form it should no
    # longer be able to submit, exactly the same "forged/stale PATCH" case
    # every other autosave endpoint already answers as a plain 403 stream.
    def update
      asset_params = params.fetch(:media_asset, ActionController::Parameters.new).permit(:title, :alt, :caption)
      translated = asset_params.slice(:alt, :caption).to_h

      result = Media::Save.call(@asset, attributes: { title: asset_params[:title] }, translations: { admin_locale => translated })

      streams = autosave_stream(
        record: result.record,
        result: result,
        status_id: "media-save-status",
        error_prefix: "media",
        base_updated_at: params[:base_updated_at],
        fields: { title: [ :title ], alt: [ :alt ], caption: [ :caption ] }
      )

      render turbo_stream: streams, status: autosave_status(result)
    end

    # Moves the image to the trash (`Trash::Move`, trash spec §4.1); the
    # permanent delete is `Trash::Purge`, reachable only from the trash.
    # `Trash::Move` itself is what refuses this while a *kept* page or post
    # still uses the image, which `Admin::MediaLibrary::DetailComponent`
    # already disables the button for ahead of time; this is only ever hit
    # for real through a forged request, a race, or an actor whose rights
    # just changed, and any of those come back as the ordinary redirect-
    # with-alert every other module's own `destroy` already gives.
    # Interim: the "Deleted" notice stays until the Trash UI task.
    def destroy
      result = Trash::Move.call(@asset)

      if result.ok?
        redirect_to admin_media_path(**admin_url_options), status: :see_other, notice: "Deleted"
      else
        forbidden_or(result) { redirect_to admin_medium_path(@asset, **admin_url_options), status: :see_other, alert: result.errors.to_sentence }
      end
    end

    private

    def forbidden_status_id = action_name == "update" ? "media-save-status" : nil

    # No `admin_scope` here (`Admin::BaseController`'s own comment on it):
    # a library image has no owner-scoped "read" permission the way a
    # page/post does -- `media.upload` alone (checked above, for every
    # action this is `before_action`ed on) is what CS Studio's whole
    # library-browsing story ever gates on. `with_variants` here (not just
    # on the grid's own `filtered_assets`) is what lets `Admin::MediaLibrary
    # ::DetailComponent`'s own preview/thumbnail read `#srcset` without an
    # extra query either.
    def set_asset
      # `.kept`: a trashed image is 404 here, like a trashed page or post
      # (trash spec §5.1, "not found, not forbidden") -- it can't be
      # viewed, edited or deleted from the library, only from the Trash.
      @asset = Media::Asset.kept.with_variants.find(params[:id])
    end

    def offset
      raw = params[:offset].to_i
      raw.positive? ? raw : 0
    end

    def filtered_assets
      scope = Media::Asset.kept.with_variants
      scope = scope.unused if params[:filter] == "unused"
      scope = scope.where(created_by_id: Current.user&.id) if params[:filter] == "mine"
      # Title, alt (any locale) and filename (global constraints: "search
      # matches title, alt (any locale's jsonb values -- use a safe jsonb
      # text search, bind params only) and filename") -- `Media::Search`
      # (Task 9), shared with the MCP `list_media_tool` rather than
      # duplicated here; see that class's own comment for the query itself.
      scope = Media::Search.call(scope, params[:q]) if params[:q].present?
      scope
    end
  end
end
