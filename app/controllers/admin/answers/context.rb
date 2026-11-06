module Admin
  module Answers
    # What a block responder draws with: the view the components are rendered
    # in, the page whose blocks they are, the language being edited, the link
    # params that keep it (`admin_url_options`), the page's reservations as the
    # request's tab sees them and the signed-in person.
    #
    # `holds` is read once per request and AFTER the action's write, so the
    # controller builds its context only when it answers: a card held by
    # someone else is drawn read-only, with the strip, however it came to be
    # drawn.
    #
    # One stream builder per context, made with it: a Data is frozen once
    # built, so it is made before `super` freezes the instance.
    Context = Data.define(:view, :page, :locale, :url_options, :holds, :viewer) do
      def initialize(view:, **members)
        @turbo_stream = Answers.stream_builder(view)
        super
      end

      attr_reader :turbo_stream

      def render(component) = view.render(component)

      # Markup already rendered (`render`), joined without escaping it again.
      def safe_join(parts) = view.safe_join(parts)
    end
  end
end
