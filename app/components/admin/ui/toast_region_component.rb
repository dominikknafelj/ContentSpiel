module Admin
  module Ui
    # The one `<div id="toasts">` in CS Studio's layout: the live region every
    # toast lands in, whether it came from the flash of a redirect (rendered
    # here) or from a Turbo Stream (`toast_stream`, which appends to this id).
    # It renders even when empty, precisely so a stream has a target.
    #
    # `flash[:warning]` is a warning toast: something was done and something was
    # not (a bulk action's partial result, which names the failures) -- it never
    # auto-hides, like an error, and keeps its Undo.
    #
    # `flash[:notice]` is a success toast -- an undo toast when `flash[:undo]`
    # (`{ label:, url:, method: }`, string keys after the session round trip)
    # rides along -- and `flash[:alert]` is an error toast.
    #
    # `relay: true` renders only the toasts, with no container: the layout uses
    # that inside `<turbo-frame id="content">` for a frame request, whose
    # response keeps nothing outside the frame, so a flash rendered into the
    # region would be consumed and lost. `admin--toast` moves a toast that sits
    # outside `#toasts` into it.
    #
    # Deliberately NOT `data-turbo-permanent`: Turbo would keep the old region
    # and throw away the new page's, so the flash of every redirect would vanish.
    class ToastRegionComponent < AdminComponent
      def initialize(flash:, relay: false)
        @flash = flash
        @relay = relay
      end

      private

      attr_reader :flash, :relay

      def notice_kind = undo ? :undo : :success

      def notice = flash[:notice]

      def alert = flash[:alert]

      def warning = flash[:warning]

      def undo = flash[:undo].presence&.to_h&.with_indifferent_access
    end
  end
end
