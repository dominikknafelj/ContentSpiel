module Admin
  module AuditScreen
    # The head of an audit event's page: a breadcrumb back to the log (the
    # filters kept), the sentence as the title ("You edited “Welcome to our new
    # site”", the subject linked only when the viewer may open it), and one
    # facts card -- WHEN ("Fri 2 Oct 2026, 16:05–16:31 · 12 saves",
    # `occurrences` is the saves a coalesced row stands for), WHO, ACTION (the
    # key in mono, after a warn "Security" state chip for a security event),
    # OBJECT, REQUEST and the IP in mono, then CHANNEL. A blank value reads
    # "—". Every value is escaped text.
    class EventHeaderComponent < Admin::AdminComponent
      def initialize(event:, sentence:, back_path:)
        @event = event
        @sentence = sentence
        @back_path = back_path
      end

      attr_reader :event, :sentence, :back_path

      def when_text = TimeSpan.long(event)

      # `nil` for an event nobody made (a failed sign-in): no invented person.
      def who
        actor = sentence.actor
        return if actor.none

        name = Admin::Ui::UserNameComponent.new(user: actor.user, user_id: actor.user_id).label
        actor.via_label.present? ? t(".via", name:, token: actor.via_label) : name
      end

      def object
        return if event.subject_type.blank?

        type = Audit::Filter::SUBJECT_TYPES[Audit::Event::LEGACY_POLYMORPHIC_TYPES.fetch(event.subject_type, event.subject_type)] || event.subject_type
        [ "#{type} ##{event.subject_id}", event.subject_label.presence ].compact.join(" · ")
      end

      # `[key, value, mono]` per cell; the key names its label under `cells`.
      def cells
        [
          [ :when, when_text, false ],
          [ :who, who || "—", false ],
          [ :action, event.action, true ],
          [ :object, object || "—", false ],
          [ :request, event.request_id.presence || "—", true ],
          [ :ip, event.ip.presence || "—", true ]
        ]
      end
    end
  end
end
