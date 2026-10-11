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
    # WHERE THE HOLD COMES FROM. The editors have read the page's holds once
    # (`Editing::Holds`) and hand them through as the slot's `holds:`; the
    # component asks them, and `loader` then answers nothing, so the slot
    # costs no statement. Only a host that has no holds lets the loader read
    # them (one statement for every block, one for the users), and then
    # `data` is the `Editing::Reservation`.
    #
    # Decoration with its own words: the avatar is hidden from a screen
    # reader, the `sr-only` text is what it hears. Nothing here is a live
    # region; the announcement of a take-over is the panel's (`HoldStripComponent`).
    class HolderAvatarComponent < AdminComponent
      # `{ block id => Editing::Reservation }`, live rows only; or `{}` when
      # the host handed its `holds:` through.
      def self.loader
        lambda do |blocks, viewer:, holds: nil|
          next {} if holds || !viewer.is_a?(::User) || blocks.none?

          ::Editing::Reservation.live.where(subject_type: "ContentBlock", subject_id: blocks.map(&:id)).includes(:user).index_by(&:subject_id)
        end
      end

      def initialize(record:, viewer:, data: nil, placement: nil, holds: nil, **)
        @block = record
        @viewer = viewer
        @data = data
        @placement = placement
        @holds = holds
      end

      def render? = @placement == :tile && hold&.user.present?

      def own? = @viewer.present? && hold.user_id == @viewer.id

      def name = ::PersonName.of(hold.user)

      def words = own? ? t(".own_tab") : t(".held", name: name)

      private

      def hold = @hold ||= @holds ? @holds.other(@block) : (@data unless mine?)

      # The viewer's hold in this very tab. The tab is the request's: a tile
      # is drawn for the tab that asked for it.
      def mine? = @data.present? && @viewer.present? && @data.user_id == @viewer.id && Current.editing_tab.present? && @data.tab == Current.editing_tab
    end
  end
end
