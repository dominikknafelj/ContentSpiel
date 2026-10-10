module Admin
  module Ui
    # A short text shown under its host while the host is hovered or holds the
    # focus (presence handoff 7 and 12: "never a `title`", which a keyboard
    # does not reach and a touch never shows). CSS alone: no script, nothing
    # to connect, nothing a Turbo snapshot could keep open.
    #
    # THE HOST is the element this is rendered INSIDE. It carries `HOST`
    # (`group/tip relative`), is focusable where a keyboard should reach the
    # text (`tabindex="0"` on something that is not a link or a button), and
    # says the same text as its `aria-label`: the bubble itself is hidden from
    # a screen reader, so nothing is read twice.
    #
    # The look is the one tooltip CS Studio had, the mind graph's (a surface
    # with a line and the menu shadow, 14px ink). `align` is the host's edge
    # the bubble hangs from: `:right` for a host near the right edge of its
    # screen, where a centred bubble would leave the window.
    #
    # Not built: a delay, and Escape to dismiss it without moving the focus.
    class TooltipComponent < Admin::AdminComponent
      HOST = "group/tip relative".freeze
      ALIGN = { right: "right-0", left: "left-0" }.freeze

      def initialize(text:, align: :right)
        raise ArgumentError, "unknown tooltip alignment #{align.inspect}" unless ALIGN.key?(align)

        @text = text
        @align = align
      end

      def call
        tag.span(@text, aria: { hidden: true }, data: { tooltip: true },
          class: "pointer-events-none absolute top-full z-30 mt-1 hidden w-max max-w-xs break-words rounded-cs border border-line bg-surface px-2 py-1 " \
                 "text-sm text-ink shadow-menu group-hover/tip:block group-focus/tip:block #{ALIGN.fetch(@align)}")
      end
    end
  end
end
