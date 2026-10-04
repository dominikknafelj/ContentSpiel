module Admin
  module AuditScreen
    # One audit sentence: the viewer's own, another person's, through a token,
    # a failed sign-in (no actor) and a refused permission.
    class SentenceComponentPreview < ViewComponent::Preview
      def you = render(sentence("post.published", user_id: 1))
      def another_person = render(sentence("post.published", user_id: 2))
      def through_a_token = render(sentence("post.created", user_id: 2, actor_type: "ApiToken", actor_id: 1, actor_label: "claude-desktop"))
      def failed_sign_in = render(sentence("session.failed", user_id: nil))
      def refused = render(sentence("access.denied", user_id: 2, metadata: { "permission" => "settings.manage" }))

      private

      def sentence(action, **attributes)
        event = Audit::Event.new({ action:, channel: "admin", subject_label: "Welcome to our new site", occurred_at: Time.current, last_occurred_at: Time.current }.merge(attributes))
        render_sentence = Audit::Sentence.build(event, viewer: User.new(id: 1), target: Audit::Sentence::Target.new("Welcome to our new site", nil))
        Admin::AuditScreen::SentenceComponent.new(sentence: render_sentence)
      end
    end
  end
end
