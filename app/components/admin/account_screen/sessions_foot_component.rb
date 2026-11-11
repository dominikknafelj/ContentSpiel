module Admin
  module AccountScreen
    # The Sessions card's foot: how many other sessions the person has and
    # "Sign out everywhere else…", which opens a confirm (not destructive:
    # the person stays signed in here, and the others only sign in again).
    # With no other session it says so and offers nothing. A row's End draws
    # it again with the new count (`Admin::AccountSessionsController`), so
    # the confirm's sentence is drawn here with it.
    #
    # Its own element takes the focus when the last other row's End leaves
    # no button to hand it to (`admin--account--sessions`).
    class SessionsFootComponent < AdminComponent
      ID = "account-sessions-foot".freeze
      DIALOG_ID = "end-other-sessions".freeze

      def initialize(others:, url_options: {})
        @others = others
        @url_options = url_options
      end

      private

      attr_reader :others, :url_options
    end
  end
end
