module Admin
  # A page or post's publish state, wherever the header, the tree or the
  # post list shows it (spec §4.2/§5.2): a coloured dot plus its label.
  # `at:` is only meaningful for `"scheduled"` -- the spec's "scheduled with
  # its date on hover" -- and renders as the element's `title`, since a
  # tooltip is the cheapest way to show a full timestamp without permanently
  # widening every status pill in the tree.
  class StatusBadgeComponent < AdminComponent
    STATUSES = %w[draft scheduled live].freeze

    DOT_CLASSES = {
      "draft" => "bg-meta",
      "scheduled" => "bg-warn",
      "live" => "bg-ok"
    }.freeze

    def initialize(status:, at: nil)
      status = status.to_s
      raise ArgumentError, "unknown status #{status.inspect}" unless STATUSES.include?(status)

      @status = status
      @at = at
    end

    def label = status.humanize

    def dot_class = DOT_CLASSES.fetch(status)

    def title
      return nil unless status == "scheduled" && at.present?

      at.strftime("%b %-d, %Y %H:%M")
    end

    private

    attr_reader :status, :at
  end
end
