module Admin
  module Ui
    # `Admin::Ui::ActorAvatarComponent`: the mark beside an audit sentence, one
    # example per kind of actor, and a user in the small slot.
    class ActorAvatarComponentPreview < ViewComponent::Preview
      Actor = Audit::Sentence::Actor

      def user = render(Admin::Ui::ActorAvatarComponent.new(actor: actor(user: ada, user_id: 1)))

      def own = render(Admin::Ui::ActorAvatarComponent.new(actor: actor(you: true, user: ada, user_id: 1)))

      def deleted_user = render(Admin::Ui::ActorAvatarComponent.new(actor: actor(user_id: 42)))

      def system = render(Admin::Ui::ActorAvatarComponent.new(actor: actor))

      def nobody = render(Admin::Ui::ActorAvatarComponent.new(actor: actor(none: true)))

      def small = render(Admin::Ui::ActorAvatarComponent.new(actor: actor(user: ada, user_id: 1), size: :sm))

      private

      def ada = User.new(name: "Ada Lovelace", email_address: "ada@example.com")

      def actor(you: false, user: nil, user_id: nil, none: false) = Actor.new(you:, user:, user_id:, via_label: nil, none:)
    end
  end
end
