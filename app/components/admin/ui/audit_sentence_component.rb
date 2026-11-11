module Admin
  module Ui
    # One `Audit::Sentence` as markup: the log's rows, the event page's title
    # and the dashboard's "Recent activity" all draw a sentence here, so the
    # wording AND the look agree. The names (the actor, the subject, a strong
    # part) are at weight 500 in the sentence's own colour. The sentence is
    # plain data (the model knows no components); this is where it becomes
    # HTML: the actor named through `Admin::Ui::UserNameComponent` ("You" for the
    # viewer, "You, via <token>" for the viewer's own token, nothing at all for
    # an event with no user, like a failed sign-in), the subject quoted and
    # linked when the sentence carries a route (a route NAME and params,
    # resolved here with this request's URL options), every stored value
    # escaped as the text it is.
    class AuditSentenceComponent < Admin::AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "Inline text with no role: the subject is a link only when the sentence carries a route, one Tab stop reached in reading order and pressed with Enter; every name and part is plain text.",
        motion: :none,
        content_edges: %i[short long missing],
        widths: :fluid,
        interface: %i[sentence],
        limits: [
          "A route name not on ROUTES draws the subject as plain text and calls nothing.",
          "An event with no user draws no actor at all, and every stored value is escaped as the text it is."
        ],
        states: %i[you another_person through_a_token failed_sign_in refused],
        keys: %w[you via_you via_other],
        slots: [],
        controller: nil,
        keyboard: [ "test/system/admin/audit_log_test.rb", "the subject's link in a row's sentence is reached with Tab and pressed with Enter" ]
      )

      # Every route a sentence may name (`Audit::Sentence.route_for`,
      # `Audit::Sentence::Targets#for`). The name reaches `public_send` below,
      # so it is checked against this list rather than trusted for coming from
      # the model: a name that isn't here -- a new target added there and not
      # here, or anything else -- draws the subject as plain text and calls
      # nothing. Symbols only: `"admin_post_path"` is not on the list.
      ROUTES = %i[admin_page_path admin_post_path admin_media_path edit_admin_user_path edit_admin_group_path admin_settings_path].freeze

      def initialize(sentence:)
        @sentence = sentence
      end

      def call
        safe_join([ actor_html, *part_html ].compact)
      end

      private

      attr_reader :sentence

      def actor = sentence.actor

      def actor_html
        return if actor.none

        name = actor.you ? t(".you") : render(Admin::Ui::UserNameComponent.new(user: actor.user, user_id: actor.user_id))
        via = actor.via_label.present? ? t(actor.you ? ".via_you" : ".via_other", label: actor.via_label) : ""
        safe_join([ content_tag(:span, name, class: "font-medium"), via, " " ])
      end

      def part_html
        sentence.parts.map do |part|
          case part.kind
          when :subject then subject_html(part.text)
          when :collection then collection_html(part.text)
          when :strong then content_tag(:span, part.text, class: "font-medium")
          else part.text
          end
        end
      end

      def subject_html(label) = safe_join([ "“", linked(label), "”" ])

      # A counted set ("12 images"): linked like a subject, never quoted.
      def collection_html(label) = linked(label)

      def linked(label)
        route = sentence.subject_route
        if route && ROUTES.include?(route.name)
          link_to(label, helpers.public_send(route.name, *route.args, **route.params, **url_options),
            class: "relative z-(--cs-z-raised) font-medium hover:underline", data: { turbo_frame: "_top" })
        else
          content_tag(:span, label, class: "font-medium")
        end
      end

      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
    end
  end
end
