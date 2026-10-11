module Admin
  module EditorScreen
    # "Updated by Dana Weiss · just now" (handoff 10): in a card's header for a
    # few seconds after a colleague's save arrived. Drawn only in the answer to
    # the editor's own fetch (`Admin::EditingController#block` with `mark=1`);
    # `admin--editing--live` takes it away after `Editing::NOTICE`. Not
    # announced (handoff 21): no live region, no role.
    class UpdatedMarkComponent < AdminComponent
      def initialize(change:)
        @change = change
      end

      def render? = @change.present?

      def name = ::PersonName.of(@change.user)

      def at = @change.at
    end
  end
end
