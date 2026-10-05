module Admin
  module AuditScreen
    # A row of the audit log: a plain one, a coalesced span, an MCP change and a
    # security key (warn ink).
    class RowComponentPreview < ViewComponent::Preview
      def plain = row("post.published")
      def coalesced_span = row("post.updated", last_occurred_at: Time.zone.local(2026, 10, 2, 16, 31))
      def via_mcp = row("post.created", channel: "mcp", actor_type: "ApiToken", actor_id: 1, actor_label: "claude-desktop")
      def security_key = row("session.failed", user_id: nil)

      private

      def row(action, **attributes)
        event = Audit::Event.new({ id: 1, action:, channel: "admin", user_id: 1, subject_label: "Welcome to our new site",
          occurred_at: Time.zone.local(2026, 10, 2, 16, 5), last_occurred_at: Time.zone.local(2026, 10, 2, 16, 5) }.merge(attributes))
        sentence = Audit::Sentence.build(event, viewer: nil, target: Audit::Sentence::Target.new("Welcome to our new site", nil))
        render_with_template(template: "admin/audit_screen/row_component_preview/list", locals: { event:, sentence: })
      end
    end
  end
end
