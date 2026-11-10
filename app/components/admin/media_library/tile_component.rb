module Admin
  # See `Admin::MediaLibrary::GridComponent`'s own class comment for why
  # this namespace is `MediaLibrary`, not `Media`.
  module MediaLibrary
    # One image in the Media grid: the thumbnail, the title, its size as a
    # label and two chips -- "No alt" (warn) while the default-language alt is
    # empty and "Unused" (meta) while nothing uses it. Each chip is words, not
    # just a colour. The tile is a link into the `content` frame that opens
    # the panel (`/media?selected=ID`, the grid's own state kept), so Back
    # returns to the previous selection.
    #
    # Its box is `.admin-tile` (`content-spiel.tailwind.css`): elevation 1 at
    # rest and 2 under the pointer, with no border, and the accent outline 2px
    # out while it is chosen. The stylesheet draws the chosen look from
    # `aria-current` (here) or `aria-pressed` (the picker's), so the state a
    # screen reader hears and the look are one attribute. `CARD` is the one
    # class string of both modes and of an upload's progress tile
    # (`media/upload_tiles.js`, handed it by the view).
    #
    # While the made width loads, the face shows the image's ~24px preview
    # under it, blurred and scaled past the face's clipped edge so the blur has
    # no soft border; hidden from a screen reader, since the thumbnail is the
    # picture. With no made width `LibraryImageComponent` draws the preview
    # itself, and with no preview the face is the sunken ground.
    #
    # It renders its own `<li id="media-asset-ID">`: the autosave answer
    # replaces exactly that element (`Admin::MediaController#update`), so an
    # alt text typed in the panel takes "No alt" off the tile without a reload.
    #
    # `pick: true` is the same tile inside `Admin::Ui::MediaPickerComponent`: a button,
    # not a link, because the picker is select-then-confirm. A click selects
    # it (`admin--media--select#select`, which sets `aria-pressed`), a double
    # click selects and confirms, Enter on a selected one confirms. Its whole
    # payload for the opener (`media-picker:picked`'s detail) is one JSON action
    # param (not one param per key: Stimulus JSON-parses each param value on its
    # own, so an alt text that reads "42" or "true" would arrive as a number or
    # a boolean). `url` is the thumbnail -- only ever shown as the choice in
    # CS Studio; what gets saved is `id`. `alt`/`caption` are the asset's own
    # defaults in the editing language (`locale`), resolved as the public page
    # would (`Media::Asset#alt_text` with no override), so a blank per-use
    # override field can show what will actually be used.
    #
    # `open_notes:` and `notes_unread:` are the caller's to say for the same
    # reason (`GridComponent#note_counts`, `#note_unread`): the image's open
    # notes as the notes pill on the image's top right corner, accent while
    # something there is unread and addressed to the viewer, nothing at zero.
    # Never in the picker, whose grid reads none.
    #
    # `unused:` is the caller's to say, not read here: a grid answers it for a
    # whole page in one query (`GridComponent#used_ids`), which a per-tile
    # `asset.used?` would turn into one query per tile.
    class TileComponent < Admin::AdminComponent
      def self.dom_id(asset) = "media-asset-#{asset.id}"

      CARD = "admin-tile group block w-full overflow-hidden text-left " \
             "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent".freeze

      PICK_CARD = CARD

      # What an upload's progress tile says (`media/upload_tiles.js`), served
      # as `data-messages` by both hosts of the upload queue: the Media
      # screen's upload wrapper and the picker's dialog.
      UPLOAD_MESSAGES = %w[uploading progress failed offline dismiss status_done status_failed]
                        .map { |key| "components.media_library.uploads.#{key}" }.freeze

      PICK_ACTIONS = "click->admin--media--select#select dblclick->admin--media--select#choose keydown->admin--media--select#key".freeze

      def initialize(asset:, url: nil, unused:, selected: false, pick: false, locale: ::Locales.default, open_notes: 0, notes_unread: false)
        @asset = asset
        @url = url
        @unused = unused
        @selected = selected
        @pick = pick
        @locale = locale
        @open_notes = open_notes
        @notes_unread = notes_unread
      end

      def pick? = @pick

      def open_notes = @open_notes.to_i

      def notes_unread? = @notes_unread ? true : false

      # The picker's tiles keep the id the picker's grid has always had (the
      # Media grid's own `media-asset-ID` is the autosave answer's target and
      # must not appear twice on a page that has both).
      def dom_id = pick? ? "media-picker-asset-#{asset.id}" : self.class.dom_id(asset)

      def pick_payload
        {
          id: asset.id,
          url: thumbnail_url,
          width: asset.width, height: asset.height, preview: Media::Asset.preview_url?(thumbnail_url),
          title: asset.title,
          alt: asset.alt_text(override: nil, locale: locale).to_s,
          caption: asset.caption_text(override: nil, locale: locale).to_s
        }.to_json
      end

      def pick_data = { action: PICK_ACTIONS, "asset-id": asset.id, "admin--media--select-asset-param": pick_payload }

      def unused? = @unused

      def selected? = @selected

      # Blank, absent or whitespace in the DEFAULT language (what `Media::Search`
      # calls missing alt): the text every other language falls back to.
      def no_alt? = asset.alt(locale: ::Locales.default).to_s.strip.empty?

      def dimensions = (asset.width && asset.height ? "#{asset.width}×#{asset.height}" : nil)

      def thumbnail_url = asset.thumbnail_url

      # The preview to blur under a made width while it loads; nil while no
      # width is made (the thumbnail is the preview then) or there is none.
      def loading_preview_url = (asset.preview_data_url if asset.made?)

      private

      attr_reader :asset, :url, :locale
    end
  end
end
