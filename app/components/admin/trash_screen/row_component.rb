module Admin
  module TrashScreen
    # One trashed item on the Trash screen (trash spec §7): its title (a
    # thumbnail for an image), type, who trashed it and when, how long until
    # the retention job (`Trash::PurgeExpiredJob`) deletes it, and its two
    # actions -- Restore and Delete permanently.
    #
    # Restore is a one-click POST, except for a page that can't go back where
    # it was (`.needs_parent?`): then it's a small form with a `<select
    # name="parent_id">` of `parent_choices`, since `Trash::Restore` would
    # only refuse the one-click version. Delete permanently always confirms
    # (`Admin::ConfirmDialogComponent`, never a browser dialog); an image
    # something still uses -- necessarily something in the trash, or it
    # couldn't have been trashed -- gets a disabled button instead, the
    # same refusal `Trash::Purge` would give, said up front.
    class RowComponent < Admin::AdminComponent
      TYPE_KEYS = { Page => "page", Post => "post", Media::Asset => "media" }.freeze
      TYPE_LABELS = { "page" => "Page", "post" => "Post", "media" => "Image" }.freeze

      # A page restores in place only when it's the root of its own trash
      # branch and its parent is a kept page; a member of another page's
      # branch, or a page whose parent is trashed or gone, needs a new
      # parent (`Trash::Restore#page_problem` refuses the rest). Expects
      # `parent` preloaded when called over a whole list.
      def self.needs_parent?(item)
        return false unless item.is_a?(Page)

        item.trash_root_id != item.id || item.parent.nil? || item.parent.trashed?
      end

      def initialize(item:, retention_days:, subpages: [], in_use: false, parent_choices: nil, url_options: {})
        @item = item
        @retention_days = retention_days
        @subpages = subpages
        @in_use = in_use
        @parent_choices = parent_choices
        @url_options = url_options
      end

      def type_key = TYPE_KEYS.fetch(item.class)

      def type_label = TYPE_LABELS.fetch(type_key)

      def row_id = "trash-#{type_key}-#{item.id}"

      def purge_dialog_id = "purge-#{type_key}-#{item.id}"

      def title = item.title.presence || "Untitled"

      def image? = item.is_a?(Media::Asset)

      def needs_parent? = self.class.needs_parent?(item)

      def in_use? = @in_use

      def trashed_by_label
        item.trashed_by ? "Trashed by #{item.trashed_by.email_address}" : "Trashed by someone who has since left"
      end

      # `retention - days since trashed`, never below 0; nil (nothing shown)
      # when retention is 0, which means "never purge automatically".
      def countdown
        return if retention_days.zero?

        days_left = [ retention_days - ((Time.current - item.trashed_at) / 1.day).floor, 0 ].max
        days_left.zero? ? "Deleted permanently today" : "Deleted permanently in #{helpers.pluralize(days_left, "day")}"
      end

      def restore_path = helpers.admin_restore_trash_item_path(type_key, item, **url_options)

      def purge_path = helpers.admin_trash_item_path(type_key, item, **url_options)

      def parent_select_id = "#{row_id}-parent"

      private

      attr_reader :item, :retention_days, :subpages, :parent_choices, :url_options
    end
  end
end
