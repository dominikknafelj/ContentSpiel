module Admin
  module DashboardScreen
    # One line of "Recent activity" (design pass round 2, Task 16): an avatar
    # (round with the person's initial; a SQUARE accent one for a change made
    # through an API token), one sentence -- "<name> published “<title>”",
    # the title a link to the record's editor -- a status chip when the
    # record is not Live, and a relative time. A coalesced burst of edits
    # shows the time it last extended, with the whole span as its tooltip.
    #
    # A change through a token names the token's *user* and says "via an API
    # token" -- the token itself is never named (round 3 brings token
    # names) and no part of its value is ever rendered; the row doesn't even
    # carry the token. Everything comes from a `Dashboard::Activity::Row`
    # (record, user and time already loaded), so a row never queries.
    class ActivityRowComponent < Admin::AdminComponent
      def initialize(row:)
        @row = row
      end

      def name = row.actor_name

      def via_token? = row.via_token

      def initial = name.to_s.strip[0].to_s.upcase

      def before = row.sentence_parts[0]

      def record = row.sentence_parts[1]

      def after = row.sentence_parts[2]

      def title
        record.title.presence || "Untitled"
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
        via_token? ? "rounded-cs bg-accent text-on-accent" : "rounded-full bg-sunken text-ink"
      end

      private

      attr_reader :row

      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
    end
  end
end
