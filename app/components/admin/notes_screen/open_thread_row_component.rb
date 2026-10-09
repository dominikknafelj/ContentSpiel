module Admin
  module NotesScreen
    # One record with open threads (notes spec §5, handoff "Open threads
    # row"): its title as a link to the record with its notes open, what kind
    # of record it is and when a note was last written on it, and how many
    # threads are open in the notes pill.
    #
    # The pill is `.admin-notes-marker` as a list draws it (read-only, with
    # its number) and always NEUTRAL: it counts everybody's open threads, and
    # accent is kept for what is unread and addressed to the viewer -- which
    # is the card beside this one.
    #
    # A post is marked with its content type's dot and name, as everywhere a
    # post is listed; a page and an image by the word.
    class OpenThreadRowComponent < Admin::AdminComponent
      def initialize(row:)
        @row = row
      end

      private

      attr_reader :row

      def path = helpers.public_send(row.route.name, *row.route.args, **row.route.params, **url_options)

      def post? = row.kind == "post"

      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
    end
  end
end
