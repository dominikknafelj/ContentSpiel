module Admin
  module Ui
    # A way in that leaves this site: the single sign-on provider's start, a
    # gem's sign-in method (`SignIn::Methods`), the owner path's "Sign in with
    # %{provider} instead", and the invitation page's "Continue with
    # %{provider}". One `ButtonComponent` in a POST form of its own, carrying
    # the form's token, and sent WITHOUT TURBO (`data-turbo="false"`): the
    # answer is a redirect to a whole page on another site (the provider's
    # authorization address), which Turbo's fetch could not follow.
    #
    # `variant:` is one of three looks:
    #
    # - `:secondary` (the default), full width: a way in beside the panel's
    #   one primary, the provider's and a gem's alike (the Design System card
    #   drew no gem's button, so it takes the provider's look);
    # - `:primary`, full width: the provider's button where it is the panel's
    #   one way in (SSO_REQUIRED);
    # - `:tertiary`, the small underlined text button at its own width: a way
    #   back to the provider from a page that offers another (the owner path).
    class WayInButtonComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "A native submit button in a form of its own, named by its label, pressed with Enter or Space.",
        motion: :reduced,
        content_edges: %i[long short],
        widths: :from_container,
        interface: %i[label url variant],
        limits: [
          "It only posts to its address with the form's token: what the address answers (a redirect off the site) is the caller's.",
          "It is drawn in three looks, and any other variant is refused.",
          "Its motion is the button's own, which holds still under reduced motion."
        ],
        states: %i[secondary primary tertiary],
        keys: [],
        slots: [],
        controller: nil,
        keyboard: [ "test/system/admin/sso_sign_in_test.rb", "the provider's way in is the Tab stop after Sign in, and Enter there goes to the provider" ]
      )

      # The button's variant, size and width for each look.
      LOOKS = {
        secondary: { variant: :secondary, size: :regular, class: "w-full" },
        primary: { variant: :primary, size: :regular, class: "w-full" },
        tertiary: { variant: :tertiary, size: :small, class: nil }
      }.freeze

      def initialize(label:, url:, variant: :secondary)
        raise ArgumentError, "unknown way-in variant #{variant.inspect}" unless LOOKS.key?(variant)

        @label = label
        @url = url
        @look = LOOKS.fetch(variant)
      end

      def call
        form_with(url: @url, method: :post, data: { turbo: false }) do
          render ButtonComponent.new(label: @label, type: "submit", variant: @look[:variant], size: @look[:size], class: @look[:class])
        end
      end
    end
  end
end
