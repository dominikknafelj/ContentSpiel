module Admin
  # `TrashScreen`, not `Trash`: an `Admin::Trash` module would shadow the
  # top-level `Trash` module (`app/models/trash.rb`, `app/services/trash/*`)
  # for every bare `Trash::` reference lexically nested under `module Admin`
  # -- the same trap `Admin::MediaLibrary`'s own comment describes for
  # `Media`. `test/lib/admin_trash_namespace_test.rb` guards it.
  module TrashScreen
    # The Trash screen's list (trash spec §7): the Empty trash button (for
    # `trash.empty` holders) above one table row per trashed item, newest
    # first, as `Admin::TrashController#index` loaded them. Everything a row
    # needs beyond its own record is looked up here once for the whole page
    # rather than per row:
    # - each page root's branch members (`#subpages_for`), one query, and
    #   how many pages its purge would take (`#descendant_counts`), one;
    # - which images something still uses (`#in_use?`) -- a trashed owner
    #   included, the same `Media::Asset#used?` `Trash::Purge` refuses on;
    # - the restore form's parent choices (`#parent_choices`), only when a
    #   row actually needs a parent.
    class ListComponent < Admin::AdminComponent
      EMPTY_DIALOG_ID = "empty-trash-dialog".freeze

      def initialize(items:, retention_days:, url_options: {})
        @items = items
        @retention_days = retention_days
        @url_options = url_options
      end

      def row_for(item)
        Admin::TrashScreen::RowComponent.new(
          item:,
          retention_days:,
          subpages: subpages_for(item),
          purge_subpage_count: item.is_a?(Page) ? descendant_counts.fetch(item.id, 0) : 0,
          in_use: in_use?(item),
          parent_choices: Admin::TrashScreen::RowComponent.needs_parent?(item) ? parent_choices : nil,
          url_options:
        )
      end

      def may_empty? = can?("trash.empty")

      # Everything `Trash::Empty` would try, not only this page of the list:
      # page branches by root, posts and images.
      def total_count = @total_count ||= Trash.roots.values.sum(&:count)

      private

      attr_reader :items, :retention_days, :url_options

      def pages = items.grep(Page)

      def subpages_for(item)
        return [] unless item.is_a?(Page)

        subpages_by_root.fetch(item.id, [])
      end

      # A branch member shares its root's `trash_root_id`; a separately
      # trashed descendant is its own root (`trash_root_id = id`) and has
      # a row of its own instead.
      def subpages_by_root
        @subpages_by_root ||= Page.where(trash_root_id: pages.map(&:id)).where("pages.id <> pages.trash_root_id")
          .order(:id).group_by(&:trash_root_id)
      end

      # How many pages a purge of each listed page would take with it --
      # every descendant, branch member or trashed separately, the same set
      # `Trash::Purge` destroys -- off the closure table in one query.
      def descendant_counts
        @descendant_counts ||= Page.hierarchy_class.where(ancestor_id: pages.map(&:id)).where("generations > 0").group(:ancestor_id).count
      end

      def in_use?(item)
        item.is_a?(Media::Asset) && used_asset_ids.include?(item.id)
      end

      def used_asset_ids
        @used_asset_ids ||= Media::Usage.where(media_asset_id: items.grep(Media::Asset).map(&:id)).distinct.pluck(:media_asset_id).to_set
      end

      # `[label, id]` pairs of the kept pages the viewer may create pages
      # under (trash spec corrections, "Parent picker"), labelled with the
      # page's own path of titles ("Home / About / Team") so two pages that
      # share a title can be told apart. Every ancestor of a kept page is
      # kept (`Trash::Move` takes a page's whole branch), so the titles are
      # read off one load of the kept pages rather than per candidate.
      def parent_choices
        @parent_choices ||= begin
          candidates = AccessControl.scope(Current.actor, "pages.create", Page.all).pluck(:id)
          kept = Page.kept.select(:id, :parent_id, :title).index_by(&:id)
          candidates.filter_map { |id| kept[id] && [ path_label(kept[id], kept), id ] }.sort_by(&:first)
        end
      end

      def path_label(page, kept)
        chain = []
        while page
          chain.unshift(page.title.presence || "Untitled")
          page = kept[page.parent_id]
        end
        chain.join(" / ")
      end
    end
  end
end
