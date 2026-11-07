module Admin
  module DashboardScreen
    # One record in "Pick up where you left off" (the viewer's drafts) or
    # "Publishing on its own" (what is scheduled): a page or post linked to
    # its editor.
    #
    # * `variant: :draft` -- the title, the content-type dot (a page says
    #   "Page") and "edited 2h ago" (the record's `updated_at`).
    # * `variant: :going_live` -- the scheduled date block
    #   (`Admin::Ui::ScheduledDateComponent`, hidden from a screen reader),
    #   the title, "in 5 days" in a `<time>` whose tooltip is the exact
    #   moment, and, when `mine:`, "by you".
    #
    # Everything is read from the record `Dashboard::Feed` already loaded:
    # titles are jsonb columns and a post's type label comes from the
    # in-memory `ContentTypes` registry, so a row never costs a query of its
    # own (the dashboard's constant-query test pins this).
    class RowComponent < Admin::AdminComponent
      def initialize(record:, variant:, mine: false)
        raise ArgumentError, "unknown variant #{variant.inspect}" unless %i[draft going_live].include?(variant)

        @record = record
        @variant = variant
        @mine = mine
      end

      def going_live? = variant == :going_live

      def mine? = @mine

      def title = record.title.presence || t(".untitled")

      def path
        record.is_a?(Page) ? helpers.admin_page_path(record, **url_options) : helpers.admin_post_path(record, **url_options)
      end

      def exact_time = I18n.l(record.published_at.in_time_zone, format: :"admin.datetime")

      # By the site's calendar (`Time.zone`), not by 24-hour spans: "in 5 days",
      # "tomorrow" for the next calendar day, and for later today "in 3h" (or
      # "soon" within the hour). The exact moment is the tooltip.
      def going_live_phrase
        at = record.published_at.in_time_zone
        days = (at.to_date - Time.zone.today).to_i
        return t(".tomorrow") if days == 1
        return t(".in_days", count: days) if days > 1

        hours = ((at - Time.zone.now) / 1.hour).floor
        hours >= 1 ? t(".in_hours", hours:) : t(".soon")
      end

      private

      attr_reader :record, :variant

      # Keeps the editing language across navigation, like every other admin
      # link. `admin_url_options` is a controller helper, absent when a
      # component is rendered on its own (component tests).
      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
    end
  end
end
