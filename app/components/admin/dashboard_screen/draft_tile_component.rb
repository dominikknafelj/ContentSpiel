module Admin
  module DashboardScreen
    # One of the viewer's drafts in "Pick up where you left off", as a tile
    # (`rounded-tile bg-surface shadow-1`, raised to `shadow-2` under the
    # pointer): the record's kind (a post's content-type dot with its name,
    # or "Page"), its title, a post's excerpt clamped to two lines, when it
    # was last edited, and the verb "Continue".
    #
    # The tile presses as one: its title is a link whose `::after` is
    # stretched over the tile (`.admin-draft-tile__link`), so a press on the
    # excerpt opens the draft too. "Continue" is words, not a second link:
    # it describes the title's link and is read only as that (`OneLink`),
    # and, like every closing verb of a row, it is dim at rest and accent
    # only while the tile is pointed at or focused, because accent at rest
    # means "unread and addressed to you".
    #
    # The excerpt is the record's plain text, escaped like any other string.
    # Everything is read from the record `Dashboard::Feed#drafts` loaded (the
    # title and excerpt are jsonb columns, a type's label comes from the
    # in-memory `ContentTypes` registry), so a tile costs no statement.
    class DraftTileComponent < Admin::AdminComponent
      include OneLink

      def initialize(record:)
        @record = record
      end

      private

      attr_reader :record

      def post? = record.is_a?(Post)

      def title = record.title.presence || t(".untitled")

      def excerpt = (record.excerpt.presence if post?)

      def path = post? ? helpers.admin_post_path(record, **url_options) : helpers.admin_page_path(record, **url_options)

      def verb_id = "draft-tile-#{record.model_name.singular}-#{record.id}-verb"

      # `admin_url_options` is a controller helper, absent when a component
      # is rendered on its own (a component test).
      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
    end
  end
end
