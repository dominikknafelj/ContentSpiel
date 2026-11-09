module Admin
  module NotesScreen
    # One record with open threads in the Notes screen's rail: ONE link to the
    # record's notes (its editor with the drawer open, or for an image the
    # Media screen with it chosen), from the row's route NAME with this
    # request's URL options. It holds the record's chip (the sidebar's own,
    # `StudioModules`, read through the inbox row's table so the two cannot
    # differ), its title, how many notes and when the newest was written, and
    # at the end the newest two people who wrote, then "+N" for the others.
    #
    # The link does not prefetch and leaves the notes frame (`_top`), as every
    # link into a record's notes does. The chip and the circles are
    # decoration: the link's name is the title and the count line.
    #
    # Nothing here queries: the row carries its record and its people. The
    # circles are the viewer's own when they wrote (the solid fill), and
    # overlap by 6px with a ring in the colour of what the rail stands on
    # (`--admin-avatar-ground`).
    class OpenThreadRowComponent < Admin::AdminComponent
      def initialize(row:)
        @row = row
      end

      private

      attr_reader :row

      def path = helpers.note_route_path(row.route, **url_options)

      def chip
        entry = StudioModules.find(Admin::NotesScreen::InboxRowComponent::MODULES.fetch(row.kind))
        render Admin::Ui::IconChipComponent.new(icon: entry.icon, family: entry.family, size: :xsmall)
      end

      def line = t(".line_html", count: row.count, time: render(Admin::Ui::TimeAgoComponent.new(time: row.at)))

      def more? = row.author_count > row.authors.size

      def more_label = Admin::Ui::AvatarComponent.more_label(row.author_count - row.authors.size)

      # An API token has no circle of its own: only a person is "you".
      def viewer
        Current.actor if Current.actor.is_a?(::User)
      end

      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
    end
  end
end
