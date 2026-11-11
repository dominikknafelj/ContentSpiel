module Admin
  module AccountScreen
    # Your account's Sessions card: every live session of the person, the one
    # they are reading in first ("This session", no End), then the others by
    # when they were last seen. A row says the device in a person's words
    # (`SessionDevice`), and under it the address, how recently it was active
    # and how the person signed in.
    #
    # Each other row's End ends that session at once, no confirm: it is one
    # of the person's own, and its answer (`Admin::AccountSessionsController`)
    # takes the row away and draws the foot again
    # (`Admin::AccountScreen::SessionsFootComponent`), where the bulk ending
    # is offered behind a confirm.
    #
    # The card stands outside both of the screen's forms and its forms hold
    # no field: nothing in it is counted by a save bar, and leaving the
    # screen never asks about it. `admin--account--sessions` hands the focus
    # on when an End's row goes.
    class SessionsCardComponent < AdminComponent
      # The card's section, the anchor its answers come back to is its
      # heading (`#sessions`).
      ID = "account-sessions".freeze
      HEADING_ID = "sessions".freeze

      # `sessions` are the person's live ones, `current` the one this request
      # is made in; a `class` is appended to the card's.
      def initialize(sessions:, current:, url_options: {}, class: nil)
        @sessions = sessions
        @current = current
        @url_options = url_options
        @class = binding.local_variable_get(:class)
      end

      private

      attr_reader :current, :url_options

      def rows = [ *@sessions.select { |session| current?(session) }, *others ]

      def others = @sessions.reject { |session| current?(session) }.sort_by(&:last_seen_at).reverse

      def current?(session) = session.id == current&.id

      def device(session)
        key, values = SessionDevice.new(session.user_agent).key_and_values
        t(".#{key}", **values)
      end

      def details(session)
        active = current?(session) ? t(".active_now") : t(".active_html", time: render(Admin::Ui::TimeAgoComponent.new(time: session.last_seen_at)))
        safe_join([ session.ip_address.presence, active, t(".signed_in_with.#{session.authenticated_with}") ].compact, " · ")
      end

      def card_class = [ "scroll-mt-6", @class ].compact.join(" ")

      def row_id(session) = "session-#{session.id}"
    end
  end
end
