module Admin
  # See `Admin::MediaLibrary::GridComponent`'s own class comment for why
  # this namespace is `MediaLibrary`, not `Media`.
  module MediaLibrary
    # One image in the Media grid (round 3, Task 8, handoff §4.6): the
    # thumbnail, the title, its size in mono and two chips -- `NO ALT` (warn)
    # while the default-language alt is empty and `UNUSED` (meta) while nothing
    # uses it. The tile is a link into the `content` frame that opens the panel
    # (`/media?selected=ID`, the grid's own state kept), so Back returns to the
    # previous selection; the selected one has an accent ring and
    # `aria-current`. Each chip is words, not just a colour.
    #
    # It renders its own `<li id="media-asset-ID">`: the autosave answer
    # replaces exactly that element (`Admin::MediaController#update`), so an
    # alt text typed in the panel takes `NO ALT` off the tile without a reload.
    #
    # `pick: true` is the same tile inside `Media::PickerComponent` (round 3,
    # Task 9): a button, not a link, because the picker is select-then-confirm
    # (D14). A click selects it (`admin--media-select#select`, `aria-pressed`
    # drawing the same accent ring the panel's selected tile has), a double
    # click selects and confirms, Enter on a selected one confirms. Its whole
    # payload for the opener (`media-picker:picked`'s detail) is one JSON action
    # param (not one param per key: Stimulus JSON-parses each param value on its
    # own, so an alt text that reads "42" or "true" would arrive as a number or
    # a boolean). `url` is the thumbnail -- only ever used to *show* the choice
    # in CS Studio; what gets saved is `id`. `alt`/`caption` are the asset's own
    # defaults in the editing language (`locale`), resolved as the public page
    # would (`Media::Asset#alt_text` with no override), so a blank per-use
    # override field can show what will actually be used.
    #
    # `unused:` is the caller's to say, not read here: a grid answers it for a
    # whole page in one query (`GridComponent#used_ids`), which a per-tile
    # `asset.used?` would turn into one query per tile.
    class TileComponent < Admin::AdminComponent
      def self.dom_id(asset) = "media-asset-#{asset.id}"

      CARD = "group block w-full overflow-hidden rounded-cs border bg-surface text-left hover:border-line-strong " \
             "focus:outline-2 focus:outline-accent".freeze

      PICK_CARD = "#{CARD} border-line aria-pressed:border-accent aria-pressed:ring-[3px] aria-pressed:ring-accent-tint".freeze

      PICK_ACTIONS = "click->admin--media-select#select dblclick->admin--media-select#choose keydown->admin--media-select#key".freeze

      def initialize(asset:, url: nil, unused:, selected: false, pick: false, locale: ::Locales.default)
        @asset = asset
        @url = url
        @unused = unused
        @selected = selected
        @pick = pick
        @locale = locale
      end

      def pick? = @pick

      # The picker's tiles keep the id the picker's grid has always had (the
      # Media grid's own `media-asset-ID` is the autosave answer's target and
      # must not appear twice on a page that has both).
      def dom_id = pick? ? "media-picker-asset-#{asset.id}" : self.class.dom_id(asset)

      def pick_payload
        {
          id: asset.id,
          url: thumbnail_url,
          title: asset.title,
          alt: asset.alt_text(override: nil, locale: locale).to_s,
          caption: asset.caption_text(override: nil, locale: locale).to_s
        }.to_json
      end

      def pick_data = { action: PICK_ACTIONS, "asset-id": asset.id, "admin--media-select-asset-param": pick_payload }

      def unused? = @unused

      def selected? = @selected

      # Blank, absent or whitespace in the DEFAULT language (what `Media::Search`
      # calls missing alt): the text every other language falls back to.
      def no_alt? = asset.alt(locale: ::Locales.default).to_s.strip.empty?

      def dimensions = (asset.width && asset.height ? "#{asset.width}×#{asset.height}" : nil)

      def card_class = "#{CARD} #{selected? ? "border-accent ring-[3px] ring-accent-tint" : "border-line"}"

      def thumbnail_url = asset.thumbnail_url

      private

      attr_reader :asset, :url, :locale
    end
  end
end
