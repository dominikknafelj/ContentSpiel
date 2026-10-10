module Admin
  module AuditScreen
    # One `Audit::Sentence` as markup (design pass round 3, Task 15): the log's
    # rows, the event page's title and the dashboard's "Recent activity" all
    # draw a sentence here, so the wording AND the look agree. The sentence is
    # plain data (the model knows no components); this is where it becomes
    # HTML: the actor named through `Admin::Ui::UserNameComponent` ("You" for the
    # viewer, "You, via <token>" for the viewer's own token, nothing at all for
    # an event with no user, like a failed sign-in), the subject quoted and
    # linked when the sentence carries a route (a route NAME and params,
    # resolved here with this request's URL options), every stored value
    # escaped as the text it is.
    class SentenceComponent < Admin::AdminComponent
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

        name = actor.you ? "You" : render(Admin::Ui::UserNameComponent.new(user: actor.user, user_id: actor.user_id))
        via = actor.via_label.present? ? (actor.you ? ", via #{actor.via_label}" : " via #{actor.via_label}") : ""
        safe_join([ content_tag(:span, name, class: "font-semibold"), via, " " ])
      end

      def part_html
        sentence.parts.map do |part|
          case part.kind
          when :subject then subject_html(part.text)
          when :strong then content_tag(:span, part.text, class: "font-semibold")
          else part.text
          end
        end
      end

      def subject_html(label)
        route = sentence.subject_route
        inner = if route && ROUTES.include?(route.name)
          link_to(label, helpers.public_send(route.name, *route.args, **route.params, **url_options),
            class: "relative z-10 font-semibold hover:underline", data: { turbo_frame: "_top" })
        else
          content_tag(:span, label, class: "font-semibold")
        end
        safe_join([ "“", inner, "”" ])
      end

      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
    end
  end
end
