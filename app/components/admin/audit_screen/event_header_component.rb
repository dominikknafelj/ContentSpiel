module Admin
  module AuditScreen
    # The head of an audit event's page (design pass round 3, Task 15): a
    # breadcrumb back to the log (the filters kept), the sentence as the title
    # ("You edited “Welcome to our new site”", the subject linked only when the
    # viewer may open it), and a meta grid -- WHEN ("Fri 2 Oct 2026, 16:05–16:31
    # · 12 saves", `occurrences` is the saves a coalesced row stands for), WHO,
    # CHANNEL, ACTION (mono, warn ink for a security key), OBJECT and REQUEST --
    # plus the IP, in mono as before. A blank value reads "—". Every value is
    # escaped text.
    class EventHeaderComponent < Admin::AdminComponent
      def initialize(event:, sentence:, back_path:)
        @event = event
        @sentence = sentence
        @back_path = back_path
      end

      attr_reader :event, :sentence, :back_path

      def when_text = TimeSpan.long(event)

      def action_class = sentence.security ? "text-warn-ink" : "text-ink"

      # `nil` for an event nobody made (a failed sign-in): no invented person.
      def who
        actor = sentence.actor
        return if actor.none

        name = Admin::UserNameComponent.new(user: actor.user, user_id: actor.user_id).label
        actor.via_label.present? ? "#{name} via #{actor.via_label}" : name
      end

      def object
        return if event.subject_type.blank?

        type = Audit::Filter::SUBJECT_TYPES[Audit::Event::LEGACY_POLYMORPHIC_TYPES.fetch(event.subject_type, event.subject_type)] || event.subject_type
        [ "#{type} ##{event.subject_id}", event.subject_label.presence ].compact.join(" · ")
      end

      def cells
        [
          [ "When", when_text, false ],
          [ "Who", who || "—", false ],
          [ "Action", event.action, true ],
          [ "Object", object || "—", false ],
          [ "Request", event.request_id.presence || "—", true ],
          [ "IP", event.ip.presence || "—", true ]
        ]
      end
    end
  end
end
