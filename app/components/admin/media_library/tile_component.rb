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
    # `unused:` is the caller's to say, not read here: a grid answers it for a
    # whole page in one query (`GridComponent#used_ids`), which a per-tile
    # `asset.used?` would turn into one query per tile.
    class TileComponent < Admin::AdminComponent
      def self.dom_id(asset) = "media-asset-#{asset.id}"

      CARD = "group block w-full overflow-hidden rounded-cs border bg-surface text-left hover:border-line-strong " \
             "focus:outline-2 focus:outline-accent".freeze

      def initialize(asset:, url:, unused:, selected: false)
        @asset = asset
        @url = url
        @unused = unused
        @selected = selected
      end

      def dom_id = self.class.dom_id(asset)

      def unused? = @unused

      def selected? = @selected

      # Blank, absent or whitespace in the DEFAULT language (what `Media::Search`
      # calls missing alt): the text every other language falls back to.
      def no_alt? = asset.alt(locale: ::Locales.default).to_s.strip.empty?

      def dimensions = (asset.width && asset.height ? "#{asset.width}×#{asset.height}" : nil)

      def card_class = "#{CARD} #{selected? ? "border-accent ring-[3px] ring-accent-tint" : "border-line"}"

      def thumbnail_url = asset.thumbnail_url

      private

      attr_reader :asset, :url
    end
  end
end
