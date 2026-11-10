module Admin
  module TrashScreen
    # One trashed item on the Trash screen: its title (a 40px thumbnail for
    # an image) and, for a page, what comes back with it ("Includes 2
    # subpages: A, B"); its type as its kind's chip and word
    # (`Admin::Ui::RecordChipComponent`); who trashed it, as their small
    # avatar, their name and "· <time ago>"; the retention tag
    # (`RetentionTagComponent`); and its two actions -- Restore and "Delete
    # now…", both small.
    #
    # Restore is a one-click POST, except for a page that can't go back where
    # it was (`.needs_parent?`: a branch member whose root is gone, or a page
    # whose parent is trashed): then it is a small inline form, "Restore
    # under" a `<select name="parent_id">` of `parent_choices` and a Restore
    # button, since `Trash::Restore` would only refuse the one-click version.
    # "Delete now…" always confirms in its own `Admin::Ui::ConfirmDialogComponent`
    # (one per row, 50 at most per page -- a small `<dialog>` each, rather than
    # a shared one that a script would have to fill); an image something in
    # the trash still uses gets a disabled button instead -- the refusal
    # `Trash::Purge` would give, said up front as visible text under the
    # button (and as its tooltip), not hover-only.
    #
    # Everything beyond the item itself is looked up once for the whole page
    # by `ListComponent` and handed in: nothing here queries.
    class RowComponent < Admin::AdminComponent
      TYPE_KEYS = { Page => "page", Post => "post", Media::Asset => "media", Forms::Form => "form" }.freeze
      # What an item is called on the screen: a form by its name (it has no
      # title), anything else by its title. Read by the controller's flashes
      # too, where no component renders, so the key is a full one.
      def self.title_of(item) = (item.is_a?(Forms::Form) ? item.name : item.title).presence || I18n.t("admin.components.trash_screen.list.untitled")

      # A page restores in place only when it's the root of its own trash
      # branch and its parent is a kept page; a member of another page's
      # branch, or a page whose parent is trashed or gone, needs a new
      # parent (`Trash::Restore#page_problem` refuses the rest). (The list
      # holds branch roots only, so the first case never reaches a row today;
      # it is here because this is the rule, whatever is listed.) Expects
      # `parent` preloaded when called over a whole list.
      def self.needs_parent?(item)
        return false unless item.is_a?(Page)

        item.trash_root_id != item.id || item.parent.nil? || item.parent.trashed?
      end

      # `subpage_sentence` is the "Includes N subpages: …" line (nil for
      # anything but a page with branch members); `purge_subpage_count` is
      # every page under it, a descendant trashed separately included -- what
      # a purge takes (`Trash::Purge#branch_deepest_first`), so the two can
      # differ. `who` is the finished "You" / name / "System" label, and
      # `actor` the same person as the audit log's actor facts, for the avatar;
      # `used_by` the number of items in the trash still using an image (nil
      # when none does); `tab` the tab to come back to after an action.
      def initialize(item:, retention_days:, who:, actor:, subpage_sentence: nil, purge_subpage_count: 0, used_by: nil, parent_choices: nil, tab: nil, url_options: {})
        @item = item
        @retention_days = retention_days
        @who = who
        @actor = actor
        @subpage_sentence = subpage_sentence
        @purge_subpage_count = purge_subpage_count
        @used_by = used_by
        @parent_choices = parent_choices
        @tab = tab
        @url_options = url_options
      end

      attr_reader :who, :actor, :subpage_sentence, :tab

      def type_key = TYPE_KEYS.fetch(item.class)

      def type_label = t(".types.#{type_key}")

      def row_id = "trash-#{type_key}-#{item.id}"

      def purge_dialog_id = "purge-#{type_key}-#{item.id}"

      def title = self.class.title_of(item)

      # Whether "Delete now…" is offered: a form is deleted for good with
      # `trash.empty` alone (`Trash::Purge`: it takes its submissions with
      # it), so a `forms.manage` holder may restore one and nothing more.
      def purgeable? = !item.is_a?(Forms::Form) || can?("trash.empty")

      def image? = item.is_a?(Media::Asset)

      def needs_parent? = self.class.needs_parent?(item)

      def in_use? = @used_by.to_i.positive?

      # Why "Delete now…" is disabled: a bare count, never names (an owner in
      # the trash may be one the viewer can't read).
      def in_use_reason = t(".in_use", count: @used_by)

      def reason_id = "#{row_id}-why"

      def purge_dialog_title = t(".purge.title", title:)

      def purge_dialog_body
        @purge_subpage_count.positive? ? t(".purge.body_with_subpages", count: @purge_subpage_count) : t(".purge.body")
      end

      def restore_path = helpers.admin_restore_trash_item_path(type_key, item, **url_options)

      def purge_path = helpers.admin_trash_item_path(type_key, item, **url_options)

      def parent_select_id = "#{row_id}-parent"

      # A page that needs a new parent while there is none this viewer may
      # create under: the select and Restore are disabled, and `row.no_parent`
      # says why as visible text (their `aria-describedby`), like the disabled
      # "Delete now…" does.
      def no_parent? = needs_parent? && parent_choices.blank?

      def no_parent_id = "#{row_id}-no-parent"

      private

      attr_reader :item, :retention_days, :parent_choices, :url_options
    end
  end
end
