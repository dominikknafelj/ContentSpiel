module Admin
  module AuditScreen
    # The head of an event page: a coalesced edit with its saves, and a failed sign-in.
    class EventHeaderComponentPreview < ViewComponent::Preview
      def coalesced_edit = header("post.updated", occurrences: 12, subject_type: "Post", subject_id: 5, subject_label: "Welcome to our new site")
      def failed_sign_in = header("session.failed", user_id: nil, ip: "203.0.113.4")

      private

      def header(action, **attributes)
        event = Audit::Event.new({ action:, channel: "admin", user_id: 1, request_id: "7c1e0000a90f", ip: "203.0.113.9",
          occurred_at: Time.zone.local(2026, 10, 2, 16, 5), last_occurred_at: Time.zone.local(2026, 10, 2, 16, 31) }.merge(attributes))
        sentence = Audit::Sentence.build(event, viewer: nil, target: event.subject_label ? Audit::Sentence::Target.new(event.subject_label, nil) : nil)
        render Admin::AuditScreen::EventHeaderComponent.new(event:, sentence:, back_path: "#")
      end
    end
  end
end
