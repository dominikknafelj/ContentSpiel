module Admin
  module NotesScreen
    # A message's text (decision D8): plain text as typed, line breaks kept,
    # a mention as the user's CURRENT name and a bare URL as a link that
    # opens in another tab. `Notes::Text` splits it; everything here is
    # escaped by ERB, so a note can hold "<b>" and show "<b>".
    #
    # THE LOOK (the handoff's decision 5). Accent in a note's text is the
    # system's colour for a link, as everywhere; "unread for you" is said by
    # markers only (dots, pills, badges), never by a word in the text. So a
    # link is accent and underlined (3px offset), and a mention is a small
    # chip instead: ink at weight 500 on the sunken surface for anybody else,
    # and accent on the accent tint when it is the VIEWER who is mentioned --
    # the one mention a reader looks for. `viewer_id` is handed in (the
    # message component has the viewer); nothing here reads `Current`, and a
    # render without one draws every mention as somebody else's.
    class BodyComponent < Admin::AdminComponent
      LINK_CLASS = "text-accent underline underline-offset-[3px] hover:text-accent-hover".freeze
      MENTION_CLASS = "rounded-cs px-0.5 font-medium".freeze
      MENTION_OTHER_CLASS = "bg-sunken text-ink".freeze
      MENTION_VIEWER_CLASS = "bg-accent-tint text-accent".freeze

      def initialize(body:, users:, viewer_id: nil)
        @body = body
        @users = users
        @viewer_id = viewer_id
      end

      private

      attr_reader :users

      def parts = ::Notes::Text.parts(@body)

      def viewer?(user_id) = @viewer_id.present? && user_id == @viewer_id

      def mention_class(user_id) = "#{MENTION_CLASS} #{viewer?(user_id) ? MENTION_VIEWER_CLASS : MENTION_OTHER_CLASS}"

      # `data-note-mention` is on every mention; its value says whose.
      def mention_kind(user_id) = viewer?(user_id) ? "viewer" : "other"
    end
  end
end
