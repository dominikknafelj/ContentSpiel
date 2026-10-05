module Admin
  module AuditScreen
    # Events under Today / Yesterday / dated headers.
    class DayListComponentPreview < ViewComponent::Preview
      def days
        now = Time.current
        entries = [ now, now - 3.hours, now - 1.day, now - 5.days ].each_with_index.map do |at, index|
          event = Audit::Event.new(id: index + 1, action: "post.updated", channel: "admin", user_id: 1, subject_label: "Welcome to our new site", occurred_at: at, last_occurred_at: at)
          [ event, Audit::Sentence.build(event, viewer: nil, target: nil) ]
        end
        render Admin::AuditScreen::DayListComponent.new(entries:, event_path: ->(_event) { "#" })
      end
    end
  end
end
