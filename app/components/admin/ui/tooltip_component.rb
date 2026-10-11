module Admin
  module Ui
    # A short text shown under its host while the pointer is on it or the
    # keyboard's focus is (presence handoff 7, 12 and 18: "never a `title`",
    # which a keyboard does not reach and a touch never shows). CS Studio's
    # icon buttons still use `title`; they move here in a sweep of their own.
    #
    # THE HOST is the element this is rendered INSIDE. It carries `HOST`
    # (`relative`: the bubble is placed against it) and `host_data` (the
    # controller and its actions); where a keyboard should reach the text it
    # is focusable and says the same words as its `aria-label`, because the
    # bubble is hidden from a screen reader -- nothing is read twice.
    #
    # THE LOOK (handoff 18) is the inverted toast's: ink with paper text, 12px
    # sans at 1.4, 4px by 8px, at most 240px wide, no shadow, no arrow; 6px
    # below the host and centred on it. Everything that moves is the script's
    # (`admin--ui--tooltip`): the 300ms wait on hover and none on focus, the
    # edge it lines up with when centred would cross the window's, Escape,
    # and going when its host is pressed.
    class TooltipComponent < Admin::AdminComponent
      HOST = "relative".freeze
      ACTIONS = %w[mouseenter->admin--ui--tooltip#enter mouseleave->admin--ui--tooltip#leave focusin->admin--ui--tooltip#focus
                   focusout->admin--ui--tooltip#leave pointerdown->admin--ui--tooltip#dismiss].join(" ").freeze

      # The host's `data`: merged into whatever else the host carries.
      def self.host_data = { controller: "admin--ui--tooltip", action: ACTIONS }

      def initialize(text:)
        @text = text
      end

      def call
        tag.span(@text, hidden: true, aria: { hidden: true }, data: { tooltip: true, "admin--ui--tooltip-target": "bubble" },
          class: "pointer-events-none absolute left-1/2 top-full z-30 mt-1.5 w-max max-w-60 -translate-x-1/2 whitespace-normal break-words rounded-cs bg-ink px-2 py-1 " \
                 "text-left font-cs text-xs leading-[1.4] font-normal normal-case tracking-normal text-paper " \
                 "data-[align=left]:left-0 data-[align=left]:translate-x-0 data-[align=right]:left-auto data-[align=right]:right-0 data-[align=right]:translate-x-0")
      end
    end
  end
end
