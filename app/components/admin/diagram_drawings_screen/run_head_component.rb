module Admin
  module DiagramDrawingsScreen
    # The Draw diagrams screen's head: "Draw diagrams", the lead and the
    # count, and at the right the area's one primary, "Draw all", which wraps
    # under the heading below 640px. With nothing to draw there is no count
    # and no button.
    #
    # "Draw all" and "Stop" are ONE button (`start`, its press
    # `admin--diagram--draw-all#toggle`): the script changes its label and
    # its variant, so the focus never moves on its own. Under it the reason a
    # disabled "Draw all" gives in words, "Drawing needs HTTPS.", drawn hidden
    # (an `insecure` target, beside the notice above the list) with an id
    # the script makes the button's description when it shows it: a hidden
    # element named by `aria-describedby` still gives its words, so the
    # server names none. Only the script knows whether this browser can draw
    # (a proxy may end TLS).
    #
    # Under the head, the parts a run writes, drawn empty or hidden: the
    # progress line (`progress`: its words and a bar, which is `aria-hidden`,
    # the words carrying it), the polite live region (`status`, which speaks
    # at the start, at each row that doesn't draw or is skipped, and at the
    # end, never per drawn row) and the summary's slot (`summary`).
    class RunHeadComponent < Admin::AdminComponent
      CONTROLLER = RowComponent::CONTROLLER

      def initialize(count:)
        @count = count
      end

      attr_reader :count

      def runnable? = count.positive?

      def reason_id = "draw-diagrams-insecure-reason"

      def target(name) = { "#{CONTROLLER}-target": name }

      def scope = "admin.diagram_drawings.index"

      def words(key, **options) = t("#{scope}.#{key}", **options)
    end
  end
end
