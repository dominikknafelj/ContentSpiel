module Admin
  module GroupsScreen
    # `Admin::GroupsScreen::ListComponent`: built-in and custom rows, counts
    # grey at zero, the whole row one link.
    class ListComponentPreview < ViewComponent::Preview
      def default
        group = AccessControl::Group.create!(name: "Branch editors #{SecureRandom.hex(3)}", description: "Edit and publish pages under Services.")
        groups = AccessControl::Group.order(:name).to_a
        render Admin::GroupsScreen::ListComponent.new(groups: groups, member_counts: { group.id => 2 }, token_counts: { group.id => 1 })
      end
    end
  end
end
