module Admin
  module EditorScreen
    # What a card's header says for a few seconds after someone else's change
    # arrived, or after this tab took the block over:
    # "Updated by Dana Weiss · 2 min ago" with the colleague's circle (no "here" ring: the author of a save need not be present) before
    # it, or "Taken over by you · just now" with no circle, since nobody else
    # is named.
    #
    # The first is drawn only in the answer to the editor's own fetch
    # (`Admin::EditingController#block` with `mark=1`); the second is a
    # template of the live region that `editing/marks.js` clones into the
    # card. `editing/marks.js` takes either away after `Editing::NOTICE`.
    # Not announced: no live region, no role.
    class UpdatedMarkComponent < AdminComponent
      def initialize(change: nil, taken_over: false)
        @change = change
        @taken_over = taken_over
      end

      def render? = @taken_over || @change.present?

      def taken_over? = @taken_over

      def name = ::PersonName.of(@change.user)

      def initials = ::PersonName.initials(name)

      def at = @change.at
    end
  end
end
