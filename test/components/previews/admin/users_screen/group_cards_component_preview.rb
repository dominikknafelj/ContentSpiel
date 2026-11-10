module Admin
  module UsersScreen
    # `Admin::UsersScreen::GroupCardsComponent`: the Groups card of tiles, a
    # ticked one outlined; a group the viewer can't grant is a sunken tile
    # with a disabled box ("You can't grant this group."); in a dialog, the
    # tiles with no card.
    class GroupCardsComponentPreview < ViewComponent::Preview
      def default
        groups = AccessControl::Group.order(:name).to_a
        render Admin::UsersScreen::GroupCardsComponent.new(groups: groups, selected_ids: groups.first(2).map(&:id), assignable_ids: groups.map(&:id), manage_groups: true)
      end

      def with_a_locked_group
        groups = AccessControl::Group.order(:name).to_a
        render Admin::UsersScreen::GroupCardsComponent.new(groups: groups, selected_ids: groups.first(2).map(&:id), assignable_ids: groups.drop(1).map(&:id))
      end

      def in_a_dialog
        groups = AccessControl::Group.order(:name).to_a
        render Admin::UsersScreen::GroupCardsComponent.new(groups: groups, selected_ids: groups.first(1).map(&:id), assignable_ids: groups.map(&:id), frame: false)
      end
    end
  end
end
