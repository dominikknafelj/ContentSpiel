module Admin
  module UsersScreen
    # The user editor's Groups field (round 3 Task 12, handoff §4.9 and §10 B28):
    # a card per group in a two-column grid, instead of a row of checkboxes. The
    # CARD IS THE LABEL -- a real `<label>` around a real checkbox, the name and the
    # description -- so a click anywhere on it ticks it, the name `user[group_ids][]`
    # and the values are what the form always posted, and a ticked card is tinted
    # (`has-[:checked]`, so it follows the box with no script).
    #
    # A GROUP THE VIEWER CAN'T ASSIGN (`assignable_ids` doesn't hold it) is a
    # sunken card with a greyed, disabled box and "You can't grant this group.".
    # A disabled box posts nothing, so when it is ticked -- the user holds the
    # group -- a hidden input carries the membership: the form submitted exactly
    # as rendered then changes nothing about it (Review Focus 3), and
    # `Users::Save` still decides every added or removed group on the request
    # itself (it ignores an unchanged one). Such a card is shown unticked too, for
    # a group the user doesn't hold: it can't be ticked from here.
    #
    # The list starts with the blank sentinel `user[group_ids][]=""`, so that
    # unticking every card still submits `group_ids` (an empty list, not "leave
    # alone"). "Manage groups →" is for a `groups.manage` holder.
    class GroupCardsComponent < AdminComponent
      def initialize(groups:, selected_ids:, assignable_ids:, manage_groups: false, url_options: {})
        @groups = groups
        @selected_ids = selected_ids.to_set
        @assignable_ids = assignable_ids.to_set
        @manage_groups = manage_groups
        @url_options = url_options
      end

      private

      attr_reader :groups, :selected_ids, :assignable_ids, :manage_groups, :url_options

      def locked?(group) = !assignable_ids.include?(group.id)
      def checked?(group) = selected_ids.include?(group.id)
      def input_id(group) = "user_group_ids_#{group.id}"

      CARD = "grid-cols-[minmax(0,1fr)_1rem] items-start gap-2.5 rounded-cs border px-3.5 py-3 text-ink".freeze
      OPEN_CARD = "#{CARD} cursor-pointer border-line bg-surface has-[:checked]:border-accent has-[:checked]:bg-accent-tint".freeze
      LOCKED_CARD = "#{CARD} cursor-not-allowed border-line bg-sunken".freeze

      def card_class(group) = locked?(group) ? LOCKED_CARD : OPEN_CARD
    end
  end
end
