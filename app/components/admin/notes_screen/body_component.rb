module Admin
  module NotesScreen
    # A message's text (decision D8): plain text as typed, line breaks kept,
    # a mention as the user's CURRENT name and a bare URL as a link that
    # opens in another tab. `Notes::Text` splits it; everything here is
    # escaped by ERB, so a note can hold "<b>" and show "<b>".
    class BodyComponent < Admin::AdminComponent
      def initialize(body:, users:)
        @body = body
        @users = users
      end

      private

      attr_reader :users

      def parts = ::Notes::Text.parts(@body)
    end
  end
end
