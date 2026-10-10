module Media
  # The one media picker (media library design spec §6, Task 8; round 3, Task 9):
  # a modal `<dialog>` that is the Media screen's own grid in miniature -- the
  # toolbar (an instant search and the segments), selectable tiles, a header
  # **Upload** and a footer "1 selected · Cancel · **Use image**" -- and hands
  # back one asset id. Every place that sets a library image goes through it: a
  # page's hero (`Admin::Columns::MediaColumnComponent`), an image block's image
  # (the same column), and the rich-text editor's Image button
  # (`admin--rich-text--editor`).
  #
  # Rendered once per CS Studio page, by the admin layout, outside the
  # `#content` frame and outside every form -- not once per field: one
  # dialog (one set of ids) however many image fields and editors a page
  # has, and nothing typed into its search box or file input can ever
  # bubble an `input` event into an autosaving form it happens to sit in.
  # Only for someone with `media.upload`, the permission that covers
  # browsing, uploading and choosing (design spec §5.1) -- without it no
  # field offers Choose and the editor has no Image button, so nothing
  # would open it anyway.
  #
  # How a field talks to it (`admin--media-picker`'s own comment): the
  # opener dispatches `media-picker:open` on `window` with itself as
  # `detail.opener`; the picker answers with `media-picker:picked`
  # (`{ id, url, title, alt, caption }`) dispatched *on that opener*,
  # bubbling, after it has closed and handed focus back.
  #
  # The grid is `Admin::MediaController#index` itself (`picker=1`), loaded into
  # a `<turbo-frame id="media-picker-grid">` each time the picker opens -- the
  # same search, segments with counts, pagination and constant-query tiles the
  # Media module uses -- and navigated inside the frame, so searching never
  # leaves the dialog. Choosing is select-then-use (D14): a click selects a
  # tile, **Use image** confirms, a double click does both (`admin--media-select`,
  # on this same element). Uploads (`Admin::MediaAssetsController#create`,
  # `Media::Upload`) show as progress tiles at the start of the grid; the first
  # one to finish is selected, and a refused one keeps its tile with the
  # server's reason and Dismiss (`media/upload_tiles.js`). No browser dialogs
  # anywhere; Escape clears a typed search first and a second one closes the
  # dialog, the ×, Cancel and a press that both begins and ends on the backdrop
  # close it too, and focus goes back to the opener.
  #
  # It hangs from a fixed top edge (`.admin-media-picker`), not centred: its
  # height changes while open (the grid arrives, search results, progress tiles)
  # and a centred dialog moved everything under the pointer.
  class PickerComponent < Admin::AdminComponent
    DIALOG_ID = "media-picker".freeze

    # The picker's wiring, one place (all on the dialog element):
    # - `media-picker:open@window` / `close`: the opener contract above;
    # - `cancel`: native Escape, which a typed search turns into "clear it";
    # - `keydown`: the same Escape, caught earlier where the browser lets us;
    # - `turbo:frame-load`: after the grid arrives or navigates, live upload tiles
    #   go back in and the selection is drawn again;
    # - the select controller's `chosen`, and the picker's own `reset`/`uploaded`
    #   telling it to forget or to select a finished upload.
    ACTIONS = [
      "media-picker:open@window->admin--media-picker#open",
      "close->admin--media-picker#closed",
      "cancel->admin--media-picker#cancel",
      "keydown->admin--media-picker#keydown",
      "turbo:frame-load->admin--media-picker#gridLoaded",
      "turbo:frame-load->admin--media-select#reapply",
      "admin--media-picker:reset->admin--media-select#reset",
      "admin--media-picker:uploaded->admin--media-select#selectUploaded",
      "admin--media-select:chosen->admin--media-picker#chosen"
    ].join(" ").freeze

    def initialize(url_options: {})
      @url_options = url_options
    end

    def render? = can?("media.upload")

    def grid_url = helpers.admin_media_path(picker: 1, **url_options)

    def upload_url = helpers.admin_media_assets_path

    def accept = Media::Asset::ALLOWED_CONTENT_TYPES.join(",")

    def part_id(suffix) = "#{DIALOG_ID}-#{suffix}"

    private

    attr_reader :url_options
  end
end
