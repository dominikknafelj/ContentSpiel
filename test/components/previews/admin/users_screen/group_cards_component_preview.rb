module Admin
  module UsersScreen
    # `Admin::UsersScreen::GroupCardsComponent`: ticked cards are tinted; a group the viewer
    # can't grant is sunken with a greyed box ("You can't grant this group.").
    class GroupCardsComponentPreview < ViewComponent::Preview
      def default
        groups = AccessControl::Group.order(:name).to_a
        render Admin::UsersScreen::GroupCardsComponent.new(groups: groups, selected_ids: groups.first(2).map(&:id), assignable_ids: groups.map(&:id), manage_groups: true)
      end

      def with_a_locked_group
        groups = AccessControl::Group.order(:name).to_a
        render Admin::UsersScreen::GroupCardsComponent.new(groups: groups, selected_ids: groups.first(2).map(&:id), assignable_ids: groups.drop(1).map(&:id))
      end
    end
  end
end
