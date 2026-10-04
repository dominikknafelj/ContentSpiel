module Admin
  module TrashScreen
    # One trashed item on the Trash screen (trash spec §7, handoff §4.9): its
    # title (a thumbnail for an image) and, for a page, what comes back with
    # it ("Includes 2 subpages: A, B"); its type; "<who> · <time ago>"; the
    # retention tag (`RetentionTagComponent`); and its two actions -- Restore
    # and "Delete now…".
    #
    # Restore is a one-click POST, except for a page that can't go back where
    # it was (`.needs_parent?`: a branch member whose root is gone, or a page
    # whose parent is trashed): then it is a small inline form, "Restore
    # under" a `<select name="parent_id">` of `parent_choices` and a Restore
    # button, since `Trash::Restore` would only refuse the one-click version.
    # "Delete now…" always confirms in its own `Admin::ConfirmDialogComponent`
    # (one per row, 50 at most per page -- a small `<dialog>` each, rather than
    # a shared one that a script would have to fill); an image something in
    # the trash still uses gets a disabled button instead -- the refusal
    # `Trash::Purge` would give, said up front as visible text under the
    # button (and as its tooltip), not hover-only.
    #
    # Everything beyond the item itself is looked up once for the whole page
    # by `ListComponent` and handed in: nothing here queries.
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

      # `subpage_sentence` is the "Includes N subpages: …" line (nil for
      # anything but a page with branch members); `purge_subpage_count` is
      # every page under it, a descendant trashed separately included -- what
      # a purge takes (`Trash::Purge#branch_deepest_first`), so the two can
      # differ. `who` is the finished "You" / name / "System" label;
      # `used_by` the number of items in the trash still using an image (nil
      # when none does); `tab` the tab to come back to after an action.
      def initialize(item:, retention_days:, who:, subpage_sentence: nil, purge_subpage_count: 0, used_by: nil, parent_choices: nil, tab: nil, url_options: {})
        @item = item
        @retention_days = retention_days
        @who = who
        @subpage_sentence = subpage_sentence
        @purge_subpage_count = purge_subpage_count
        @used_by = used_by
        @parent_choices = parent_choices
        @tab = tab
        @url_options = url_options
      end

      attr_reader :who, :subpage_sentence, :tab

      def type_key = TYPE_KEYS.fetch(item.class)

      def type_label = TYPE_LABELS.fetch(type_key)

      def row_id = "trash-#{type_key}-#{item.id}"

      def purge_dialog_id = "purge-#{type_key}-#{item.id}"

      def title = item.title.presence || "(untitled)"

      def image? = item.is_a?(Media::Asset)

      def needs_parent? = self.class.needs_parent?(item)

      def in_use? = @used_by.to_i.positive?

      # Why "Delete now…" is disabled: a bare count, never names (an owner in
      # the trash may be one the viewer can't read).
      def in_use_reason = "Still used by #{helpers.pluralize(@used_by, "item")} in the trash"

      def reason_id = "#{row_id}-why"

      def purge_dialog_title = "Delete “#{title}”?"

      def purge_dialog_body
        body = +"It will be deleted for good, with all its translations."
        body << " #{helpers.pluralize(@purge_subpage_count, "subpage")} under it #{@purge_subpage_count == 1 ? "is" : "are"} deleted too." if @purge_subpage_count.positive?
        body << " This can't be undone."
      end

      def restore_path = helpers.admin_restore_trash_item_path(type_key, item, **url_options)

      def purge_path = helpers.admin_trash_item_path(type_key, item, **url_options)

      def parent_select_id = "#{row_id}-parent"

      private

      attr_reader :item, :retention_days, :parent_choices, :url_options
    end
  end
end
