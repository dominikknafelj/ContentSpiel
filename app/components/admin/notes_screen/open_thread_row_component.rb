module Admin
  module NotesScreen
    # One record with open threads (notes spec §5, handoff "Open threads
    # row"): the whole row is one link to the record with its notes open;
    # its title, then "type · last author · time" -- what kind of record it
    # is, who wrote last among its open threads and when -- and how many
    # threads are open in the notes pill.
    #
    # The pill is `.admin-notes-marker` as a list draws it (read-only, with
    # its number) and always NEUTRAL: it counts everybody's open threads, and
    # accent is kept for what is unread and addressed to the viewer -- which
    # is the card beside this one.
    #
    # The type is led by a 6px marker: round, in the content type's category
    # colour, for a post (`Admin::ContentTypeDotComponent`'s own colour for
    # the type, as the posts list and the mind graph's legend draw it), and
    # square in meta for a page and an image. Never the only cue: the type's
    # name stands beside it.
    #
    # Nothing here queries: the row carries its record and its last author.
    class OpenThreadRowComponent < Admin::AdminComponent
      def initialize(row:)
        @row = row
      end

      private

      attr_reader :row

      def path = helpers.note_route_path(row.route, **url_options)

      def post? = row.kind == "post"

      def type_dot = @type_dot ||= Admin::ContentTypeDotComponent.new(content_type: row.record.content_type)

      def type_name = post? ? type_dot.label : t(".kind.#{row.kind}")

      def marker_class = post? ? "rounded-full #{type_dot.mark}" : "bg-meta"

      # Nobody to name once the author's id is gone (the foreign key nulls
      # it); a user who is gone but whose id is known reads "a deleted user".
      def author? = row.last_author.present? || row.last_author_id.present?

      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
    end
  end
end
