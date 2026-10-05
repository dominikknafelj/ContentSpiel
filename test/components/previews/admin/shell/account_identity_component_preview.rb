module Admin
  module Shell
    class AccountIdentityComponentPreview < ViewComponent::Preview
      # The sidebar's "who is signed in" lines.
      def default
        render Admin::Shell::AccountIdentityComponent.new(user: User.order(:id).first || User.new(email_address: "you@example.com", name: "You"))
      end
    end
  end
end
