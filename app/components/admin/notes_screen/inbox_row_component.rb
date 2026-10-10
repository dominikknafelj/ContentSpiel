module Admin
  module NotesScreen
    # One line of the inbox (notes spec §5, handoff "Inbox row"), on the
    # dashboard's card and in the full list: who did what, the note's first
    # words, where, and when. `Dashboard::NotesForYou::Row` is data; the
    # sentence, the record's kind and the link are made here, the link from
    # the row's route NAME with this request's URL options.
    #
    # The link is the record's editor with its notes open at the thread (for
    # an image, the Media screen with the image chosen). Following it is what
    # marks the row read, by the thread view's own rule; this component adds
    # no other way. The link IS the whole row: negative margins take it to
    # the edges of the item that holds it (see the template), so the row is
    # one target and its accessible name is what it says.
    #
    # Unread is said four ways, never by colour alone: the accent dot (the
    # one use of accent here: unread and addressed to the viewer), the name
    # heavier, the sentence ink instead of dim, and "Unread" for a screen
    # reader. A read row has none of them.
    #
    # Nothing here queries: the row carries its users, record and block.
    class InboxRowComponent < Admin::AdminComponent
      def initialize(row:)
        @row = row
      end

      private

      attr_reader :row

      def path = helpers.note_route_path(row.route, **url_options)

      # A named person, or one who is gone; a reopen names nobody, and so
      # does a note whose author was deleted (the foreign key nulls the
      # column), which gets the sentence without a name.
      def somebody? = row.by.present? || row.by_id.present?

      # One whole sentence per reason and per kind of actor, never glued from
      # a name and a verb: a translator can reorder it.
      def sentence
        return t(".#{row.reason}.nobody") unless somebody?
        return t(".#{row.reason}.deleted") unless row.by

        t(".#{row.reason}.somebody_html", name: tag.strong(::Notes.name_of(row.by), class: row.unread ? "font-semibold" : "font-medium"))
      end

      # "Page · Pricing", and for a note on a block "Page · Pricing · Rich
      # text · Our prices start at…": the block as the list's group heading
      # names it, its type and then its first words, its image's file name or
      # its place on the page (`row.heading`, a `Notes::Heading::Name`).
      def where
        place = t(".where.#{row.kind}", title: row.title || t(".untitled"))
        return place unless row.heading

        t(".where.block", place: place, block: [ helpers.note_subject_label(row.heading, row.kind), helpers.note_subject_detail(row.heading) ].compact.join(" · "))
      end

      # `admin_url_options` is a controller helper, absent when a component
      # is rendered on its own (a component test).
      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
    end
  end
end
