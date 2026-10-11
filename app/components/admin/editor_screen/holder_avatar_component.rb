module Admin
  module EditorScreen
    # Who is changing a block, on its tile in a section (live-editing handoff
    # 4): a 20px avatar in the place of the add-note hover slot, before the
    # notes marker, with the shared tooltip "Dana Weiss is editing this block".
    # A slot component (`editor.block.markers`, registered first). On a card it
    # draws nothing, the hold strip says it there; and there is no "Take over"
    # on a tile.
    #
    # A reader sees it too (handoff 26): it explains why the content may
    # change. The viewer's own hold in THIS tab is no news to them and draws
    # nothing; their hold in another tab draws their own avatar (`bg-ink
    # text-paper`, handoff 18).
    #
    # WHERE THE HOLD COMES FROM. The host hands it: the editors have read the
    # page's holds once for the screen (`Editing::Holds`) and pass them to the
    # slot as `holds:`, like any other context. The component asks them and
    # nothing else, so it costs no statement, reads no `Current` (whose tab a
    # hold is "mine" in is the holds' own knowledge) and has no loader. A host
    # that hands no holds draws no avatar.
    #
    # Decoration with its own words: the avatar is hidden from a screen
    # reader, the `sr-only` text is what it hears. Nothing here is a live
    # region; the announcement of a take-over is the panel's (`HoldStripComponent`).
    class HolderAvatarComponent < AdminComponent
      def initialize(record:, viewer:, placement: nil, holds: nil, **)
        @block = record
        @viewer = viewer
        @placement = placement
        @holds = holds
      end

      def render? = @placement == :tile && hold&.user.present?

      def own? = @viewer.present? && hold.user_id == @viewer.id

      def name = ::PersonName.of(hold.user)

      def words = own? ? t(".own_tab") : t(".held", name: name)

      private

      # The row that makes the block read-only for this viewer: someone
      # else's, or the viewer's own in another tab (`Editing::Holds#other`).
      def hold = @hold ||= @holds&.other(@block)
    end
  end
end
