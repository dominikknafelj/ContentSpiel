module Admin
  # `TrashScreen`, not `Trash`: an `Admin::Trash` module would shadow the
  # top-level `Trash` module (`app/models/trash.rb`, `app/services/trash/*`)
  # for every bare `Trash::` reference lexically nested under `module Admin`
  # -- the same trap `Admin::MediaLibrary`'s own comment describes for
  # `Media`. `test/lib/admin_trash_namespace_test.rb` guards it.
  module TrashScreen
    # The Trash screen's list (trash spec §7): one table row per trashed item,
    # newest first, as `Admin::TrashController#index` loaded them (the Empty
    # trash button is the screen header's, `EmptyTrashComponent`). Everything
    # a row needs beyond its own record is looked up here ONCE for the whole
    # page, in a number of queries that doesn't grow with the rows:
    # - each page root's branch members (`#subpages_by_root`), which of them
    #   the viewer may read (`#readable_member_ids`) and how many pages its
    #   purge would take (`#descendant_counts`);
    # - who trashed each item (`#who_label`): the user the row names, else
    #   the newest `*.trashed` audit event of every row that names none
    #   (`#recorded_trashers`, one query);
    # - which images something in the trash still uses, and by how many items
    #   (`#used_by_counts`);
    # - the restore form's parent choices (`#parent_choices`), only when a
    #   row actually needs a parent.
    class ListComponent < Admin::AdminComponent
      # The page-number footer (`Admin::PaginationComponent`), inside the card.
      renders_one :footer

      # How many names the "Includes N subpages: …" line gives before "and N more".
      NAMED_SUBPAGES = 3

      # What a trash row's `trashed_by` is looked up by when it names nobody
      # any more: the audit action each kind records.
      TRASHED_ACTIONS = { "Page" => "page.trashed", "Post" => "post.trashed", "Media::Asset" => "media.trashed" }.freeze

      EMPTY_STATES = {
        nil => [ "The trash is empty", "Deleted pages, posts and images show up here until they're deleted for good." ],
        "pages" => [ "No pages in the trash", "Deleted pages show up here until they're deleted for good." ],
        "posts" => [ "No posts in the trash", "Deleted posts show up here until they're deleted for good." ],
        "images" => [ "No images in the trash", "Deleted images show up here until they're deleted for good." ]
      }.freeze

      # `tab` is the active tab's key ("pages", ... or nil for All): the empty
      # state's wording, and the tab a restore or delete comes back to.
      def initialize(items:, retention_days:, tab: nil, url_options: {})
        @items = items
        @retention_days = retention_days
        @tab = tab
        @url_options = url_options
      end

      def row_for(item)
        Admin::TrashScreen::RowComponent.new(
          item:,
          retention_days:,
          who: who_label(item),
          subpage_sentence: subpage_sentence(item),
          purge_subpage_count: item.is_a?(Page) ? descendant_counts.fetch(item.id, 0) : 0,
          used_by: used_by_counts[[ item.class.name, item.id ]],
          parent_choices: Admin::TrashScreen::RowComponent.needs_parent?(item) ? parent_choices : nil,
          tab:,
          url_options:
        )
      end

      def empty_title = EMPTY_STATES.fetch(tab).first

      def empty_description = EMPTY_STATES.fetch(tab).last

      private

      attr_reader :items, :retention_days, :tab, :url_options

      def pages = items.grep(Page)

      # "Includes 4 subpages: A, B, C and 1 more" -- the branch members a
      # restore brings back. The COUNT is every member (what Restore will
      # really affect, readable or not); the NAMES are only members the
      # viewer may read, the rest folding into "and N more" ("not found, not
      # forbidden": an unreadable page's title is not theirs to learn). With
      # none readable it is the bare count.
      def subpage_sentence(item)
        return unless item.is_a?(Page)

        members = subpages_by_root.fetch(item.id, [])
        return if members.empty?

        named = members.select { |member| readable_member_ids.include?(member.id) }.first(NAMED_SUBPAGES).map { |m| m.title.presence || "(untitled)" }
        sentence = "Includes #{helpers.pluralize(members.size, "subpage")}"
        return sentence if named.empty?

        rest = members.size - named.size
        "#{sentence}: #{named.join(", ")}#{" and #{rest} more" if rest.positive?}"
      end

      # The members the viewer may read, in one query over all of them
      # (read scope, trash included: members are trashed themselves).
      def readable_member_ids
        @readable_member_ids ||= begin
          ids = subpages_by_root.values.flatten.map(&:id)
          ids.empty? ? Set.new : AccessControl.scope(Current.actor, "pages.read", Page.where(id: ids), trashed: true).pluck(:id).to_set
        end
      end

      # "You", the user's name, the name from the item's newest `*.trashed`
      # audit event when `trashed_by` is gone (a deleted user, or a record the
      # FK nullified), else "System". A branch member trashed with its root
      # has no event of its own and a `trashed_by` set by the move, so only a
      # standalone member whose user is gone falls through to "System".
      def who_label(item)
        return label_for(item.trashed_by, item.trashed_by_id) if item.trashed_by

        event = recorded_trashers[[ item.class.name, item.id ]]
        return "System" unless event&.user_id || event&.actor_type == "ApiToken"

        label = label_for(event.user, event.user_id || event.actor_id)
        event.via_label ? "#{label} via #{event.via_label}" : label
      end

      def label_for(user, user_id)
        return "You" if user && Current.actor.is_a?(User) && Current.actor.id == user.id

        Admin::UserNameComponent.new(user:, user_id:).label
      end

      # The newest `*.trashed` event of every listed item that names no
      # trasher, in ONE query (DISTINCT ON per subject), however many rows.
      def recorded_trashers
        @recorded_trashers ||= begin
          unnamed = items.select { |item| item.trashed_by.nil? }.group_by { |item| item.class.name }
          if unnamed.empty?
            {}
          else
            events = unnamed.map { |type, list| Audit::Event.where(subject_type: type, subject_id: list.map(&:id), action: TRASHED_ACTIONS.fetch(type)) }.reduce(:or)
            events.includes(:user).select("DISTINCT ON (audit_events.subject_type, audit_events.subject_id) audit_events.*")
              .order(Arel.sql("audit_events.subject_type, audit_events.subject_id, audit_events.occurred_at DESC, audit_events.id DESC"))
              .index_by { |event| [ event.subject_type, event.subject_id ] }
          end
        end
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

      # For each listed image something still uses: how many ITEMS use it (a
      # page or post counts once however many ways it uses the image, a block
      # counts as the page or post it sits on) -- the same any-usage rule
      # `Trash::Purge` refuses on (`Media::Asset#used?`, trashed owners
      # included). A bare count: no owner is named, the viewer may not read
      # them. Two queries for the page.
      def used_by_counts
        @used_by_counts ||= begin
          ids = items.grep(Media::Asset).map(&:id)
          rows = ids.empty? ? [] : Media::Usage.where(media_asset_id: ids).distinct.pluck(:media_asset_id, :owner_type, :owner_id)
          block_ids = rows.filter_map { |_, type, id| id if type == "ContentBlock" }
          places = block_ids.empty? ? {} : ContentBlock.where(id: block_ids).pluck(:id, :owner_type, :owner_id).to_h { |id, type, owner| [ id, [ type, owner ] ] }
          rows.group_by(&:first).to_h do |asset_id, list|
            owners = list.map { |_, type, id| type == "ContentBlock" ? places.fetch(id, [ type, id ]) : [ type, id ] }.uniq
            [ [ "Media::Asset", asset_id ], owners.size ]
          end
        end
      end

      # `[label, id]` pairs of the kept pages the viewer may create pages
      # under (trash spec corrections, "Parent picker"), labelled with the
      # page's own path of titles ("Home / About / Team") so two pages that
      # share a title can be told apart. Every ancestor of a kept page is
      # kept (`Trash::Move` takes a page's whole branch), so the titles are
      # read off one load of the kept pages rather than per candidate.
      def parent_choices
        @parent_choices ||= begin
          kept = Page.kept.select(:id, :parent_id, :title).index_by(&:id)
          AccessControl.creatable_parents(Current.actor, kept.values).map { |page| [ path_label(page, kept), page.id ] }.sort_by(&:first)
        end
      end

      def path_label(page, kept)
        chain = []
        while page
          chain.unshift(page.title.presence || "(untitled)")
          page = kept[page.parent_id]
        end
        chain.join(" / ")
      end
    end
  end
end
