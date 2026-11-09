module Admin
  module Ui
    # The count of open notes as a bubble: on a row of a list, on a media tile
    # and on Waiting for you's row. It knows no feature: the caller hands it
    # the count, whether any of it is new for the viewer, and the words that
    # name it (the feature's own strings stay with the feature).
    #
    # Read is the people tint with the outline glyph and the count; unread is
    # the accent fill with the filled glyph and "3 new", so the state differs in
    # shape and in words, not only in colour. The look is `.admin-notes-marker`
    # in content-spiel.tailwind.css, shared with the block's own marker button
    # (`Admin::NotesScreen::MarkerComponent`), which a script fills.
    #
    # With an `href` it is a link (it opens the record's notes); without one
    # it is an image the row's own link or title is the way in beside, or,
    # with `aria_hidden`, hidden because the row's one link already reads its
    # `label` (it keeps `id` and the label for that link to name itself by).
    # `data` is the caller's own hooks on the root.
    class NoteMarkerComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "A link named by its label when it has an address, otherwise an image named by its label or hidden where its row's link reads it; unread is said in words, not only by its fill.",
        motion: :none,
        content_edges: %i[short long],
        widths: :fluid,
        interface: %i[count label unread href size on_image aria_hidden id data],
        limits: [
          "It knows no feature: the count, unread and the label are its caller's.",
          "It draws nothing at a count of 0."
        ],
        states: %i[read unread small on_image link hover focus],
        keys: %w[unread],
        slots: [],
        controller: nil,
        keyboard: [ "test/system/admin/notes_markers_test.rb", "the notes bubble's keyboard: a posts row's bubble is one Tab stop that opens the post's notes, and the tree's and a tile's take none" ]
      )

      SIZES = %i[row small].freeze

      def initialize(count:, label:, unread: false, href: nil, size: :row, on_image: false, aria_hidden: false, id: nil, data: {})
        raise ArgumentError, "unknown note marker size #{size.inspect}" unless SIZES.include?(size)

        @count = count.to_i
        @label = label
        @unread = unread ? true : false
        @href = href
        @size = size
        @on_image = on_image
        @aria_hidden = aria_hidden
        @id = id
        @data = data
      end

      def render? = @count.positive?

      private

      attr_reader :count, :label, :unread, :href, :id

      def classes
        [ "admin-notes-marker",
          ("no-underline" if href),
          ("admin-notes-marker--readonly" unless href),
          ("admin-notes-marker--small" if @size == :small),
          ("admin-notes-marker--on-image" if @on_image) ].compact.join(" ")
      end

      # A link into a record's notes is never prefetched: a hover must not
      # open a thread's delivery.
      def data = { has_notes: true, unread: (true if unread), **(href ? { turbo_prefetch: false } : {}), **@data }

      def glyph = helpers.render("admin/shared/icon", name: unread ? :message_square_filled : :message_square, size: "size-3")

      def number = unread ? t(".unread", count:) : count.to_s
    end
  end
end
