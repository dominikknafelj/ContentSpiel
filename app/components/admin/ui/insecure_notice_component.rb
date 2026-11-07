module Admin
  module Ui
    # "This connection is not encrypted": the one sentence CS Studio shows
    # when it is reached over plain HTTP in production. A password typed on such a page, and the session
    # cookie sent with every request after it, can be read by anyone on the
    # way, and nothing else on the screen says so.
    #
    # It can only show when the site's address is an `http://` one or is not
    # set: with an `https` address plain HTTP is redirected before it reaches
    # the app (`HostSettings.apply` turns on `force_ssl`). The sentence is
    # right for both: `PUBLIC_HOST` set to an https address is the fix.
    #
    # Shared by three layouts, so it lives here: `product` (sign-in and the
    # password reset pages, where a password is typed: shown to everyone),
    # `setup` (the wizard, which takes the first account's password: shown
    # to everyone too) and `admin` (the shell: shown to whoever could do something about it,
    # which the layout decides, not this component). `request.ssl?` is asked,
    # never the address, because it is what the proxy in front said about
    # THIS request. `production:` is handed in so a test can say it; outside
    # production nobody is told, since a development server is plain HTTP on
    # purpose.
    #
    # A warn alert, never danger (docs/reference/design-system.md: the hold
    # strip's notices): nothing has failed, something is unsafe. `role=alert`
    # because it is not read out otherwise and the next thing a person does
    # here is type a password.
    class InsecureNoticeComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "An alert (role=alert) of one sentence, with no focus of its own.",
        motion: :none,
        content_edges: %i[long],
        widths: :container,
        interface: %i[request production],
        limits: [
          "It shows only in production on a request that is not HTTPS, and decides nothing of who sees it in the shell.",
          "It says what is unsafe and offers no action of its own."
        ],
        states: %i[rest],
        keys: %w[body],
        slots: [],
        controller: nil
      )

      BASE_CLASS = "rounded-card border border-warn bg-warn-tint px-3 py-2.5 text-[13px] leading-normal text-warn-ink".freeze

      # `class:` places the notice in its host (a margin) and is added to the
      # component's own classes, never in place of them.
      def initialize(request:, production: Rails.env.production?, **html)
        @request = request
        @production = production
        @html = html
      end

      def render? = @production && !@request.ssl?

      private

      def attributes = @html.merge(id: "insecure-notice", role: "alert", class: [ BASE_CLASS, @html[:class] ].compact.join(" "))
    end
  end
end
