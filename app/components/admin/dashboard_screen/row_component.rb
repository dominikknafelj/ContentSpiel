module Admin
  module DashboardScreen
    # One record in the "Your drafts" or "Going live next" card (design pass
    # round 2, Task 16): a page or post linked to its editor.
    #
    # * `variant: :draft` -- title, content-type dot (a page says "Page") and
    #   "edited 2h ago" (the record's `updated_at`).
    # * `variant: :going_live` -- a date tile (the month in mono, `warn-ink`;
    #   the day at 18px), the title, "in 5 days" and, when `mine:`, "by you".
    #
    # Everything is read from the record `Dashboard::Feed` already loaded --
    # titles are jsonb columns, a post's type label comes from the in-memory
    # `ContentTypes` registry -- so a row never costs a query of its own (the
    # dashboard's constant-query test pins this).
    class RowComponent < Admin::AdminComponent
      def initialize(record:, variant:, mine: false)
        raise ArgumentError, "unknown variant #{variant.inspect}" unless %i[draft going_live].include?(variant)

        @record = record
        @variant = variant
        @mine = mine
      end

      def going_live? = variant == :going_live

      def mine? = @mine

      def title = record.title.presence || "Untitled"

      def path
        record.is_a?(Page) ? helpers.admin_page_path(record, **url_options) : helpers.admin_post_path(record, **url_options)
      end

      def month = record.published_at.in_time_zone.strftime("%b")

      def day = record.published_at.in_time_zone.day

      # "today", "tomorrow", "in 5 days" by the site's calendar (`Time.zone`);
      # earlier today it is "in 3h" -- an exact moment is the tooltip.
      def going_live_phrase
        at = record.published_at.in_time_zone
        days = (at.to_date - Time.zone.today).to_i
        return "tomorrow" if days == 1
        return "in #{days} days" if days > 1

        hours = ((at - Time.zone.now) / 1.hour).floor
        hours >= 1 ? "in #{hours}h" : "soon"
      end

      private

      attr_reader :record, :variant

      # Keeps the editing language across navigation, like every other
      # admin link -- `admin_url_options` is a controller helper, absent
      # when a component is rendered on its own (component tests).
      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
    end
  end
end
