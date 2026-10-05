module Admin
  # `TrashScreen`, not `Trash`: an `Admin::Trash` module would shadow the
  # top-level `Trash` module (`app/models/trash.rb`, `app/services/trash/*`)
  # for every bare `Trash::` reference lexically nested under `module Admin`
  # -- the same trap `Admin::MediaLibrary`'s own comment describes for
  # `Media`. `test/lib/admin_namespace_shadow_test.rb` guards it.
  module TrashScreen
    # The Trash screen's list (trash spec §7): one table row per trashed item,
    # newest first, as `Admin::TrashController#index` loaded them (the Empty
    # trash button is the screen header's, `EmptyTrashComponent`). Everything
    # a row needs beyond its own record is looked up here ONCE for the whole
    # page, in a number of queries that doesn't grow with the rows:
    # - each page root's branch members (`#subpages_by_root`), which of them
    #   the viewer may read (`#readable_member_ids`) and how many pages its
    #   purge would take (`#descendant_counts`);
    # - who trashed each item (`#who_label`): the user the row names, and the
    #   newest `*.trashed` audit event of every row (`#recorded_trashings`,
    #   one query) for a token's name and for a user who is gone;
    # - which images something in the trash still uses, and by how many items
    #   (`#used_by_counts`);
    # - the restore form's parent choices (`#parent_choices`), only when a
    #   row actually needs a parent.
    class ListComponent < Admin::AdminComponent
      # The page-number footer (`Admin::PaginationComponent`), inside the card.
      renders_one :footer

      YOU = "You".freeze

      # How many names the "Includes N subpages: …" line gives before "and N more".
      NAMED_SUBPAGES = 3

      # The audit action each kind's trashing records (`#recorded_trashings`).
      TRASHED_ACTIONS = { "Page" => "page.trashed", "Post" => "post.trashed", "Media::Asset" => "media.trashed" }.freeze

      EMPTY_STATES = {
        nil => [ "The trash is empty", "Deleted pages, posts and images show up here until they're deleted for good." ],
        "pages" => [ "No pages in the trash", "Deleted pages show up here until they're deleted for good." ],
        "posts" => [ "No posts in the trash", "Deleted posts show up here until they're deleted for good." ],
        "images" => [ "No images in the trash", "Deleted images show up here until they're deleted for good." ]
      }.freeze

      # The empty state of a list that is empty only FOR THIS VIEWER: the
      # trash (or this tab's kind) holds items, none of which they may restore
      # or delete one by one. Only a `trash.empty` holder is ever told so --
      # they are the one viewer who is shown what the whole trash holds (the
      # Empty trash dialog's sentence), and "The trash is empty" beside "Empty
      # trash… deletes 1 page" was a contradiction on one screen.
      HIDDEN_ITEMS = [ "Nothing here you can restore.", "The trash holds items you can't restore or delete one by one. Empty trash deletes them." ].freeze

      # `tab` is the active tab's key ("pages", ... or nil for All): the empty
      # state's wording, and the tab a restore or delete comes back to.
      # `hidden_items` says the list's kind is in the trash but out of this
      # viewer's reach (see `HIDDEN_ITEMS`).
      def initialize(items:, retention_days:, tab: nil, hidden_items: false, url_options: {})
        @items = items
        @retention_days = retention_days
        @tab = tab
        @hidden_items = hidden_items
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

      def empty_title = empty_state.first

      def empty_description = empty_state.last

      private

      attr_reader :items, :retention_days, :tab, :url_options

      def empty_state = @hidden_items ? HIDDEN_ITEMS : EMPTY_STATES.fetch(tab)

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

      # Who trashed the item: "You", the user's name, "a deleted user" or
      # "System" -- then " via <token name>" when an API token did it ("You,
      # via <token name>" for the viewer's own token).
      #
      # Two sources. `trashed_by` is the row's own answer (the acting user, or
      # the token's user). The item's `*.trashed` audit event (`#trashing_
      # event`) is read for EVERY listed row, because only it knows two things
      # the row doesn't: that a token did it, and under which name (`Audit::
      # Event#via_label`, the name written when the event was recorded, so it
      # outlives the token) -- and who it was once `trashed_by` is gone (the FK
      # nullifies it when the user is deleted).
      #
      # - a row that names its user: that user;
      # - else the event's user (`user_id` may name a user who no longer
      #   exists: "a deleted user");
      # - else, for a token's event with no user at all, "a deleted user" too
      #   (a token always acts for a user; the log reads the same,
      #   `Audit::Sentence`). The token's id is never passed off as a user id;
      # - else "System": a trusted nil actor (the retention job never trashes,
      #   but a console or system move does), or no event of this trashing --
      #   a branch member trashed with its root has none of its own.
      def who_label(item)
        event = trashing_event(item)
        label =
          if item.trashed_by then label_for(item.trashed_by)
          elsif event&.user_id then label_for(event.user)
          elsif event&.via_label then Admin::UserNameComponent::DELETED_USER
          else return Admin::UserNameComponent::NOBODY
          end
        return label unless event&.via_label

        # "You, via <token>" with the comma, "<name> via <token>" without: the
        # audit log's own two forms (`Admin::AuditScreen::SentenceComponent`).
        "#{label}#{"," if label == YOU} via #{event.via_label}"
      end

      # A user who was there: "You", their name, or -- gone since -- "a deleted
      # user" (`Admin::UserNameComponent`, the one place a user is named).
      def label_for(user)
        return YOU if user && Current.actor.is_a?(User) && Current.actor.id == user.id

        user ? Admin::UserNameComponent.new(user:).label : Admin::UserNameComponent::DELETED_USER
      end

      # The `*.trashed` event of THIS trashing, or nil. `recorded_trashings`
      # holds each item's newest one; an event from before the item's current
      # `trashed_at` belongs to an earlier trip to the trash (trashed, restored,
      # trashed again by a path that recorded nothing for this item) and would
      # name the wrong person. `Trash::Move` stamps `trashed_at` and records
      # its event in one transaction, the event after the stamp; the second of
      # slack only absorbs clock rounding between the two columns.
      def trashing_event(item)
        event = recorded_trashings[[ item.class.name, item.id ]]
        event if event && event.occurred_at >= item.trashed_at - 1.second
      end

      # The newest `*.trashed` event of every listed item, in ONE query
      # (DISTINCT ON per subject), however many rows.
      def recorded_trashings
        @recorded_trashings ||=
          if items.empty?
            {}
          else
            events = items.group_by { |item| item.class.name }
              .map { |type, list| Audit::Event.where(subject_type: type, subject_id: list.map(&:id), action: TRASHED_ACTIONS.fetch(type)) }.reduce(:or)
            events.includes(:user).select("DISTINCT ON (audit_events.subject_type, audit_events.subject_id) audit_events.*")
              .order(Arel.sql("audit_events.subject_type, audit_events.subject_id, audit_events.occurred_at DESC, audit_events.id DESC"))
              .index_by { |event| [ event.subject_type, event.subject_id ] }
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
