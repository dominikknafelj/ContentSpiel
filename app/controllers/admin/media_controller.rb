module Admin
  # The Media module (media library design spec §6, Task 7; round 3 Task 8): the
  # grid (search, segments with counts, pagination) with one image's side panel
  # beside it (`/media?selected=ID`), and its own
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
    include MediaUploadResponses

    # "About 48 per page" (design spec §6), by page number (`Pagination`,
    # design pass spec §4): `@pagination.total` is a `COUNT(*)` over the same
    # `Media::Search#results` the page is loaded from.
    PER_PAGE = 48

    before_action -> { require_permission("media.upload") }, only: %i[index show create]
    # `update` and `destroy` are gated too, BEFORE the asset is looked up
    # (final fix wave, S-M7): left to the services alone, a user with no media
    # right at all got the 404 for an id that names nothing and the service's
    # 403 for one that exists -- which tells them which ids exist. The gate is
    # "holds a right that could ever let these through", so it changes nothing
    # for anyone the services would allow: `media.manage` (any image), or
    # `media.upload` (the uploader's own -- `Media::Ownership`). Whether THIS
    # image is theirs to change is still the service's answer.
    before_action -> { forbidden! unless holds_any?(%w[media.upload media.manage]) }, only: %i[update destroy]
    before_action :set_asset, only: %i[show update destroy]

    # The grid (design spec §6, round 3 Task 8): search (title, alt in any
    # locale, filename) and the segments All / Unused / Missing alt /
    # Untranslated / Mine, newest first, 48 tiles a page, each segment with its
    # count (`Media::Search#counts`: respects the search, not the segment).
    # `Media::Asset.with_variants` is what keeps this a constant number of
    # queries whether the page holds 10 assets or 60 -- see that scope's
    # own comment; every grid render (this action, and every filtered
    # re-render of it) must load through it, never a bare `Media::Asset
    # .all`, or `Admin::MediaLibrary::GridComponent#thumbnail_url`'s own `#srcset`
    # call turns straight back into the N+1 the scope exists to prevent
    # (`Media::Search`'s default scope is exactly that).
    #
    # `selected=ID` opens that image's panel beside the grid (handoff §4.6; the
    # detail page is gone). The panel shows whatever the id names, whether or
    # not the grid's segment would list it -- fixing an alt text must not make
    # the panel you are typing in vanish. An id that is missing, trashed or not a
    # number is the same 404 as `GET /media/:id` ("not found, not forbidden",
    # and a trashed image only ever opens from the Trash); it is NOT "the grid
    # without a panel", which would hide that a link has gone stale.
    #
    # `picker=1` is the same listing for `Media::PickerComponent` (round 3,
    # Task 9): the toolbar, the grid and the pagination, rendered on their own
    # inside the picker's `<turbo-frame id="media-picker-grid">`
    # (`admin/media/picker`, no layout) with select buttons instead of panel
    # links. Deliberately this endpoint rather than a second one: one search,
    # one set of segments and counts, one constant-query load (`Media::Search`,
    # kept images only), and the same `media.upload` gate -- the picker's only
    # permission is "may browse and choose". It has no panel.
    def index
      @search = Media::Search.new(q: params[:q], filter: params[:filter], actor: Current.actor)
      scope = @search.results
      @pagination = Pagination.new(page: params[:page], per_page: PER_PAGE, total: scope.count)
      @assets = scope.order(id: :desc).limit(PER_PAGE).offset(@pagination.offset).to_a

      @counts = @search.counts
      return render :picker, layout: false if params[:picker].present?

      @selected = selected_asset
      @link_params = list_query
    end

    # The old detail page's URL: every link that ever pointed at it (an email, a
    # bookmark, an Undo) lands on the panel. It still resolves the asset first,
    # so a trashed or missing id is the 404 it always was, not a redirect to a
    # grid with nothing selected.
    def show
      redirect_to admin_media_path(selected: @asset.id, **admin_url_options), status: :see_other
    end

    # The grid's own multi-file upload (design spec §6, global
    # constraints): one request per file -- `admin--media-upload` calls
    # this once per selected/dropped file, one at a time, never a batch -- so a
    # refused or oversized file never blocks its siblings and keeps its own
    # progress tile with the reason rather than one dialog for a whole batch.
    # JSON either way: the finished tile and the new counts on success
    # (`Admin::MediaUploadResponses`), `{ errors }` otherwise. Same shape as
    # `Admin::MediaAssetsController#create`, which answers the picker with pick
    # tiles (two different callers, deliberately not merged into one endpoint,
    # per that resource's own routing comment).
    def create
      result = Media::Upload.call(file: params[:file])

      if result.ok?
        render json: upload_json(result.record, picker: false), status: :created
      else
        render json: { errors: result.errors }, status: result.denied? ? :forbidden : :unprocessable_entity
      end
    end

    # The detail panel's own autosave endpoint (design spec §6): `title`
    # (untranslated) plus `alt`/`caption` for whichever locale is being
    # edited, through `Media::Save` -- which itself falls back to 403 for
    # anyone but `media.manage` or this asset's own uploader (`Media
    # ::Ownership`). The view only ever renders an editable form for
    # someone `Admin::MediaLibrary::PanelComponent#editable?` already agrees can
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

      streams.concat(grid_streams(result.record)) if result.ok?

      render turbo_stream: streams, status: autosave_status(result)
    end

    # Moves the image to the trash (`Trash::Move`, trash spec §4.1); the
    # permanent delete is `Trash::Purge`, reachable only from the trash.
    # `Trash::Move` itself is what refuses this while a *kept* page or post
    # still uses the image, which `Admin::MediaLibrary::PanelComponent`
    # already disables the button for ahead of time; this is only ever hit
    # for real through a forged request, a race, or an actor whose rights
    # just changed, and any of those come back as the ordinary redirect-
    # with-alert every other module's own `destroy` already gives. The Undo
    # link's own URL carries `from: "undo"` (`Admin::TrashController
    # #restore`) so restoring lands the actor back on this image's detail
    # panel, not the Trash screen.
    #
    # Both redirects keep the grid's own state (`list_query`: the search, the
    # segment and the page, which ride on the panel's delete form URL like on
    # its autosave form's), so trashing the fifth unused image on page 3 of a
    # search goes back to that list rather than to the top of the library.
    def destroy
      result = Trash::Move.call(@asset)

      if result.ok?
        flash[:undo] = { "label" => "Undo", "url" => admin_restore_trash_item_path("media", @asset, from: "undo", **admin_url_options) }
        redirect_to admin_media_path(**list_query, **admin_url_options), status: :see_other, notice: "Moved “#{@asset.title}” to the trash"
      else
        forbidden_or(result) { redirect_to admin_media_path(**list_query, selected: @asset.id, **admin_url_options), status: :see_other, alert: result.errors.to_sentence }
      end
    end

    private

    def forbidden_status_id = action_name == "update" ? "media-save-status" : nil

    # No `admin_scope` here (`Admin::BaseController`'s own comment on it):
    # a library image has no owner-scoped "read" permission the way a
    # page/post does -- `media.upload` alone (checked above, for every
    # action this is `before_action`ed on) is what CS Studio's whole
    # library-browsing story ever gates on. `with_variants` here (not just
    # on the grid's own `Media::Search` scope) is what lets `Admin::MediaLibrary
    # ::PanelComponent`'s own preview/thumbnail read `#srcset` without an
    # extra query either.
    def set_asset
      # `.kept`: a trashed image is 404 here, like a trashed page or post
      # (trash spec §5.1, "not found, not forbidden") -- it can't be
      # viewed, edited or deleted from the library, only from the Trash.
      @asset = Media::Asset.kept.with_variants.find(params[:id])
    end

    # The panel's image for `?selected=`, loaded like `set_asset` (kept, with
    # variants). Blank is no selection; anything but a String (`selected[]=1`)
    # names nothing, so it is the 404 too rather than a `find` over an array.
    def selected_asset
      raw = params[:selected]
      return nil if raw.blank?

      # The not-found page's way on is the library itself, as it was listed
      # (decision D12: the search and the segment kept, the page dropped with
      # the image it may have belonged to).
      @not_found_back = { label: "Back to Media", url: admin_media_path(**list_query.except(:page), **admin_url_options) }
      raise ActiveRecord::RecordNotFound, "Couldn't find Media::Asset" unless raw.is_a?(String)

      Media::Asset.kept.with_variants.find(raw)
    end

    # The grid's own state, kept by every link out of the panel and by the
    # panel form's own URL (symbol keys, strings only, never `locale`, which
    # `admin_url_options` carries).
    def list_query
      request.query_parameters.slice("q", "filter", "page").select { |_, value| value.is_a?(String) }.symbolize_keys
    end

    # What an autosave in the panel changes on the screen behind it, answered
    # with the save itself so nothing reloads under the typing editor: the
    # image's own tile (its title and `NO ALT` chip; a no-op when the tile is
    # not on this page), the segment counts (an alt text typed here moves
    # "Missing alt"), and the panel's own heading. The counts are for the same
    # search the grid is showing (`q` rides on the form's URL).
    #
    # The tile is drawn again whole, so it is told its open notes again too
    # (the grid's two reads, for this one image): without them the chip would
    # go, and its accent with it, on the first keystroke in the panel. The
    # image is the one `set_asset` found, kept and behind `media.upload`.
    def grid_streams(asset)
      counts = media_counts
      tile = Admin::MediaLibrary::TileComponent.new(
        asset: asset, selected: true, unused: !asset.used?,
        url: admin_media_path(**list_query, **admin_url_options, selected: asset.id),
        open_notes: Notes::Counts.by_container("Media::Asset", [ asset.id ]).fetch(asset.id, 0),
        notes_unread: Notes::Counts.unread_among("Media::Asset", [ asset.id ], Current.user).include?(asset.id)
      )
      [
        turbo_stream.replace(Admin::MediaLibrary::TileComponent.dom_id(asset), tile),
        turbo_stream.update("media-panel-title", asset.title),
        *counts.map { |key, count| turbo_stream.update(Admin::MediaLibrary::ToolbarComponent.count_id(key), count.to_s) }
      ]
    end
  end
end
