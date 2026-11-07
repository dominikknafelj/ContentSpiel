module Admin
  module DashboardScreen
    # One row of Waiting for you: a record that waits on someone, for an open
    # thread, for changes not on the site yet, or for both
    # (`Dashboard::WaitingForYou::Row`, data with its routes as names).
    #
    # The row presses as one: its title is a link whose `::after` is
    # stretched over the row (`.admin-waiting-row__link`), so a press
    # anywhere on it opens the record (with its notes open when it has a
    # thread). Under the title, the meta line: the kind's marker, the kind's
    # name, who wrote last among its open threads, and when the row last
    # changed.
    #
    # At the end, in order: the open-thread count (the read-only pill, always
    # neutral: it counts everybody's threads, and accent is kept for what is
    # unread and addressed to the viewer), the "Unpublished changes" chip,
    # and the verb. With a `review_route` (the viewer may publish the record)
    # the verb is "Review and publish…", a second link, a small secondary
    # raised over the stretched one, to the editor asked to open Publish
    # changes. Otherwise it is words, "Open thread" or "Open", that describe
    # the title's link (`aria-describedby`), dim at rest and accent while the
    # row is pointed at or focused: a link cannot hold a second link, and a
    # press that opens nothing is never offered.
    #
    # The marker is round in the content type's colour for a post and square
    # in meta for a page and an image: a shape as well as a colour, and the
    # kind's name beside it.
    #
    # Nothing here queries: the row carries its record, its thread and its
    # last author.
    class WaitingRowComponent < Admin::AdminComponent
      # The routes a row may name, checked before `public_send`: a route
      # name handed up from a query is data, and a method chosen by data is
      # called only from this list.
      ROUTES = %i[admin_page_path admin_post_path admin_media_path].freeze
      KINDS = { "Page" => "page", "Post" => "post", "Media::Asset" => "media" }.freeze # i18n-ok: class names keyed to kinds, not copy

      def initialize(row:)
        @row = row
      end

      private

      attr_reader :row

      def thread = row.thread

      def thread? = row.reasons.include?(:thread)

      def unpublished? = row.reasons.include?(:unpublished)

      def review? = row.review_route.present?

      def kind = KINDS.fetch(row.record.class.base_class.name)

      def post? = kind == "post"

      def title = row.record.title.presence || t(".untitled")

      def path = resolve(row.route)

      def review_path = resolve(row.review_route)

      def verb_id = "waiting-row-#{kind}-#{row.record.id}-verb"

      def verb = thread? ? t(".open_thread") : t(".open_record")

      def type_dot = @type_dot ||= Admin::Ui::ContentTypeDotComponent.new(content_type: row.record.content_type)

      def type_name = post? ? type_dot.label : t(".kind.#{kind}")

      def marker_class = post? ? "rounded-full #{type_dot.mark}" : "bg-meta"

      # Nobody to name once the author's id is gone (the foreign key nulls
      # it); a user who is gone but whose id is known reads "a deleted user".
      def author? = thread && (thread.last_author.present? || thread.last_author_id.present?)

      def resolve(route)
        raise ArgumentError, "#{route.name.inspect} is not a route a waiting row may link to" unless ROUTES.include?(route.name)

        helpers.public_send(route.name, *route.args, **route.params, **url_options)
      end

      # `admin_url_options` is a controller helper, absent when a component
      # is rendered on its own (a component test).
      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
    end
  end
end
