module Admin
  module UsersScreen
    # The Groups field of the user editor and of the invite dialog: a tile per
    # group in a grid. THE TILE IS THE LABEL -- a real `<label>` around a real
    # checkbox, the name and the description -- so a click anywhere on it
    # ticks it, and the name `user[group_ids][]` and the values are what the
    # form always posted. Its look is `.admin-tile`'s (content-spiel.tailwind.css):
    # the checkbox is the label's own child, so `.admin-tile:has(> input:checked)`
    # draws a ticked tile's selected outline with no script.
    #
    # A GROUP THE VIEWER CAN'T ASSIGN (`assignable_ids` doesn't hold it) is a
    # `data-locked` tile, sunken with no shadow and meta words, with a disabled
    # box and "You can't grant this group.". A disabled box posts nothing, so
    # when it is ticked -- the user holds the group -- a hidden input carries
    # the membership: the form submitted exactly as rendered then changes
    # nothing about it, and `Users::Save` still decides every added or removed
    # group on the request itself (it ignores an unchanged one). Such a tile is
    # shown unticked too, for a group the user doesn't hold: it can't be ticked
    # from here.
    #
    # The list starts with the blank sentinel `user[group_ids][]=""`, so that
    # unticking every tile still submits `group_ids` (an empty list, not "leave
    # alone"). On the editor (`frame: true`) the tiles stand in the Groups
    # card, with "Manage groups →" at its head's end for a `groups.manage`
    # holder; in a dialog (`frame: false`) there is no card, only the heading
    # and the tiles, since a dialog is a surface of its own.
    class GroupCardsComponent < AdminComponent
      HEADING_ID = "user-groups-title".freeze

      def initialize(groups:, selected_ids:, assignable_ids:, manage_groups: false, url_options: {}, frame: true)
        @groups = groups
        @selected_ids = selected_ids.to_set
        @assignable_ids = assignable_ids.to_set
        @manage_groups = manage_groups
        @url_options = url_options
        @frame = frame
      end

      private

      attr_reader :groups, :selected_ids, :assignable_ids, :manage_groups, :url_options, :frame

      def locked?(group) = !assignable_ids.include?(group.id)
      def checked?(group) = selected_ids.include?(group.id)
      def input_id(group) = "user_group_ids_#{group.id}"

      def tile_class(group)
        [ "admin-tile grid grid-cols-[minmax(0,1fr)_1rem] items-start gap-2.5 px-3 py-2.5", locked?(group) ? "cursor-not-allowed" : "cursor-pointer text-ink" ].join(" ")
      end

      def manage_link
        link_to t(".manage"), helpers.admin_groups_path(**url_options), data: { turbo_frame: "content" },
          class: Admin::Ui::ButtonComponent.classes(:tertiary, size: :small)
      end
    end
  end
end
