module Admin
  module DashboardScreen
    # One line of "Recent activity" (design pass round 2, Task 16): an avatar
    # (round with the person's initial, a token's change included), one
    # sentence -- "<name> published “<title>”", the title a link to the record's editor -- a status chip when the
    # record is not Live, and a relative time. A coalesced burst of edits
    # shows the time it last extended, with the whole span as its tooltip.
    #
    # A change through a token names the token's *user*, with the user's own
    # round avatar, and says "via <token name>" beside an MCP chip. The name
    # is the one recorded on the event (`Row#via_label`), escaped like any
    # text; no part of the token's value is ever rendered, and the row doesn't
    # even carry the token. Everything comes from a `Dashboard::Activity::Row`
    # (record, user and time already loaded), so a row never queries.
    class ActivityRowComponent < Admin::AdminComponent
      def initialize(row:)
        @row = row
      end

      def name = row.actor_name

      def via_label = row.via_label

      def via_token? = row.via_label.present?

      def channel = row.event.channel

      def initial = name.to_s.strip[0].to_s.upcase

      def before = row.sentence_parts[0]

      def record = row.sentence_parts[1]

      def after = row.sentence_parts[2]

      def title
        record.title.presence || "(untitled)"
      end

      # Pages and posts have a publish state; an image has none.
      def status? = !record.is_a?(Media::Asset)

      def span_title
        return unless row.span_end

        "#{row.at.in_time_zone.strftime("%-d %b %Y, %H:%M")} – #{row.span_end.in_time_zone.strftime("%H:%M")}"
      end

      def shown_at = row.span_end || row.at

      def path
        case record
        when Page then helpers.admin_page_path(record, **url_options)
        when Post then helpers.admin_post_path(record, **url_options)
        else helpers.admin_medium_path(record, **url_options)
        end
      end

      def avatar_class
        "rounded-full bg-sunken text-ink"
      end

      private

      attr_reader :row

      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
    end
  end
end
