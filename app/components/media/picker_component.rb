module Media
  # The one media picker (media library design spec §6, Task 8): a modal
  # `<dialog>` with a **Library** tab (search and pick from the library)
  # and an **Upload** tab (a new file, straight into the library), which
  # hands back one asset id. Every place that sets a library image goes
  # through it -- a page's hero (`Admin::Columns::MediaColumnComponent`),
  # an image block's image (the same column), and the rich-text editor's
  # Image button (`admin--rich-text`).
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
  # The Library tab is `Admin::MediaController#index` itself (`picker=1`),
  # loaded into a `<turbo-frame>` each time the picker opens -- the same
  # search, filters, pagination and constant-query grid the Media module
  # uses, with pick buttons for cards. The Upload tab posts to
  # `Admin::MediaAssetsController#create` (`Media::Upload`), and shows its
  # errors inline. No browser dialogs anywhere; Escape (the native
  # `<dialog>` cancel) and Cancel both close it and return focus.
  class PickerComponent < Admin::AdminComponent
    DIALOG_ID = "media-picker".freeze

    def initialize(url_options: {})
      @url_options = url_options
    end

    def render? = can?("media.upload")

    def library_url = helpers.admin_media_path(picker: 1, **url_options)

    def upload_url = helpers.admin_media_assets_path

    def accept = Media::Asset::ALLOWED_CONTENT_TYPES.join(",")

    def part_id(suffix) = "#{DIALOG_ID}-#{suffix}"

    private

    attr_reader :url_options
  end
end
