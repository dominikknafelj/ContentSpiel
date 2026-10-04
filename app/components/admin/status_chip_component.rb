module Admin
  # A page or post's publish state, wherever the header, the editors, the tree
  # or the lists show it (design pass spec §4): an outlined chip with a
  # coloured dot plus its label. `at:` is only meaningful for `"scheduled"`
  # and renders as the element's `title`, since a tooltip is the cheapest way
  # to show a full timestamp without widening every chip.
  #
  # `hide_live:` is for the places where nearly everything is live (the posts
  # list, the tree, the dashboard rows): a chip there would be noise, so Live
  # renders nothing and only the exceptions -- draft, scheduled -- stand out.
  # The editors' headers leave it off, because there the state is the point.
  class StatusChipComponent < AdminComponent
    STATUSES = %w[draft scheduled live].freeze

    DOT_CLASSES = {
      "draft" => "bg-meta",
      "scheduled" => "bg-warn",
      "live" => "bg-ok"
    }.freeze

    def initialize(status:, at: nil, hide_live: false)
      status = status.to_s
      raise ArgumentError, "unknown status #{status.inspect}" unless STATUSES.include?(status)

      @status = status
      @at = at
      @hide_live = hide_live
    end

    def render? = !(hide_live && status == "live")

    def label = status.humanize

    def dot_class = DOT_CLASSES.fetch(status)

    def title
      return nil unless status == "scheduled" && at.present?

      at.strftime("%-d %b %Y, %H:%M")
    end

    private

    attr_reader :status, :at, :hide_live
  end
end
