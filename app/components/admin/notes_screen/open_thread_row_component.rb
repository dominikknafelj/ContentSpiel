module Admin
  module NotesScreen
    # One record with open threads in the Notes screen's rail: ONE link to the
    # record's notes (its editor with the drawer open, or for an image the
    # Media screen with it chosen), from the row's route NAME with this
    # request's URL options. It holds the record's chip (the sidebar's own,
    # `RecordRow`), its title, how many notes and when the newest was written,
    # and at the end the newest two people who wrote, then "+N" for the others.
    #
    # The link does not prefetch and leaves the notes frame (`_top`), as every
    # link into a record's notes does. The chip and the circles are
    # decoration: the link's name is the title and the count line.
    #
    # Nothing here queries: the row carries its record and its people (a
    # nil among them is a writer who is gone). The
    # circles are the viewer's own when they wrote (the solid fill), and
    # stand 2px apart, side by side: two letters fill most of a 22px circle,
    # so a circle over the one before would cover its second letter.
    class OpenThreadRowComponent < Admin::AdminComponent
      include Admin::NotesScreen::RecordRow

      def initialize(row:)
        @row = row
      end

      private

      attr_reader :row

      def path = helpers.note_route_path(row.route, **url_options)

      def line = t(".line_html", count: row.count, time: render(Admin::Ui::TimeAgoComponent.new(time: row.at)))

      # "by Dana Weiss", "by Dana Weiss and Jonas Berg", or for more than two
      # people "by Dana Weiss, Jonas Berg and 2 more", read after the visible
      # words by a screen reader. A name is text, escaped by the template; a
      # writer who is gone is "a deleted user".
      def writers
        names = row.authors.map { |author| author ? ::PersonName.of(author) : t(".deleted") }
        return t(".by", names: names.first) if names.size == 1

        listed = more? ? t(".and_more", names: names.join(t(".separator")), count: row.author_count - names.size) : t(".two", first: names.first, second: names.last)
        t(".by", names: listed)
      end

      def more? = row.author_count > row.authors.size

      def more_label = Admin::Ui::AvatarComponent.more_label(row.author_count - row.authors.size)

      # An API token has no circle of its own: only a person is "you".
      def viewer
        Current.actor if Current.actor.is_a?(::User)
      end
    end
  end
end
