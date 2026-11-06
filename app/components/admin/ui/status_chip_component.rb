module Admin
  module Ui
    # A page or post's publish state, wherever the header, the editors, the tree
    # or the lists show it: a chip with its word, and a dot or ring for Live and
    # Draft. `at:` is only meaningful for `"scheduled"`
    # and renders as the element's `title`, since a tooltip is the cheapest way
    # to show a full timestamp without widening every chip.
    #
    # `hide_live:` is for the places where nearly everything is live (the posts
    # list, the tree, the dashboard rows): a chip there would be noise, so Live
    # renders nothing and only the exceptions -- draft, scheduled -- stand out.
    # The editors' headers leave it off, because there the state is the point.
    class StatusChipComponent < AdminComponent
      STATUSES = %w[draft scheduled live].freeze

      BASE_CLASS = "admin-status-chip inline-flex shrink-0 items-center gap-1.5 rounded-cs px-2 py-0.5 text-xs".freeze

      # Each state is a shape as well as a colour, and every one says its word:
      # Live is the solid green chip, Draft an outline with a ring, Scheduled
      # the amber block. The fills are `bg-live` and `bg-scheduled`, drawn here
      # and nowhere else (`AdminDesignRulesTest`).
      CLASSES = {
        "live" => "bg-live font-semibold text-on-live",
        "draft" => "border border-field-line bg-transparent text-dim",
        "scheduled" => "bg-scheduled text-on-scheduled"
      }.freeze

      def initialize(status:, at: nil, hide_live: false)
        status = status.to_s
        raise ArgumentError, "unknown status #{status.inspect}" unless STATUSES.include?(status)

        @status = status
        @at = at
        @hide_live = hide_live
      end

      def render? = !(hide_live && status == "live")

      def label = t(".labels.#{status}")

      def chip_class = class_names(BASE_CLASS, CLASSES.fetch(status))

      # A decoration for the eye: "●" for Live (a round dot in the chip's own
      # ink) and the ring "○" for Draft. Scheduled needs none.
      def glyph? = status != "scheduled"

      def glyph = status == "live" ? "" : "○"

      def glyph_class = status == "live" ? "size-1.5 rounded-full bg-on-live" : "leading-none"

      def title
        return nil unless status == "scheduled" && at.present?

        I18n.l(at, format: :"admin.datetime")
      end

      private

      attr_reader :status, :at, :hide_live
    end
  end
end
