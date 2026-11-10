module Admin
  # `TrashScreen`, not `Trash`: an `Admin::Trash` module would shadow the
  # top-level `Trash` module (`app/models/trash.rb`, `app/services/trash/*`)
  # for every bare `Trash::` reference lexically nested under `module Admin`
  # -- the same trap `Admin::MediaLibrary`'s own comment describes for
  # `Media`. `test/lib/admin_namespace_shadow_test.rb` guards it.
  module TrashScreen
    # The Trash screen's list: one table row per trashed item, newest first,
    # as `Admin::TrashController#index` loaded them (the Empty trash button is
    # the screen header's, `EmptyTrashComponent`), in one card whose table
    # scrolls sideways inside it with the Item column sticky
    # (`.admin-table-scroll--x`), so the page never scrolls sideways. Everything
    # a row needs beyond its own record is looked up here ONCE for the whole
    # page, in a number of queries that doesn't grow with the rows:
    # - each page root's branch members (`#subpages_by_root`), which of them
    #   the viewer may read (`#readable_member_ids`) and how many pages its
    #   purge would take (`#descendant_counts`);
    # - who trashed each item (`#who_label`, and `#who_actor` for the row's
    #   avatar): the user the row names, and the newest `*.trashed` audit event
    #   of every row (`#recorded_trashings`, one query) for a token's name and
    #   for a user who is gone;
    # - which images something in the trash still uses, and by how many items
    #   (`#used_by_counts`);
    # - the restore form's parent choices (`#parent_choices`), only when a
    #   row actually needs a parent.
    class ListComponent < Admin::AdminComponent
      # The page-number footer (`Admin::Ui::PaginationComponent`), inside the card.
      renders_one :footer

      # How many names the "Includes N subpages: …" line gives before "and N more".
      NAMED_SUBPAGES = 3

      # The audit action each kind's trashing records (`#recorded_trashings`).
      TRASHED_ACTIONS = { "Page" => "page.trashed", "Post" => "post.trashed", "Media::Asset" => "media.trashed", "Forms::Form" => "form.trashed" }.freeze # i18n-ok: class names, matched against an event's subject_type

      # The empty state's words of each tab (`list.empty.<key>`), nil being All.
      EMPTY_STATES = { nil => "all", "pages" => "pages", "posts" => "posts", "images" => "images", "forms" => "forms" }.freeze

      # `tab` is the active tab's key ("pages", ... or nil for All): the empty
      # state's wording, and the tab a restore or delete comes back to.
      # `hidden_items` says the list's kind is in the trash but out of this
      # viewer's reach: the list is empty only FOR THIS VIEWER, none of what it
      # holds being theirs to restore or delete one by one (`list.hidden`).
      # Only a `trash.empty` holder is ever told so: they are the one viewer
      # shown what the whole trash holds (the Empty trash dialog's sentence),
      # and "The trash is empty" beside "Empty trash… deletes 1 page" would
      # contradict it on one screen.
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
          actor: who_actor(item),
          subpage_sentence: subpage_sentence(item),
          purge_subpage_count: item.is_a?(Page) ? descendant_counts.fetch(item.id, 0) : 0,
          used_by: used_by_counts[[ item.class.name, item.id ]],
          parent_choices: Admin::TrashScreen::RowComponent.needs_parent?(item) ? parent_choices : nil,
          tab:,
          url_options:
        )
      end

      def empty_title = t(".#{empty_state}.title")

      def empty_description = t(".#{empty_state}.description")

      private

      attr_reader :items, :retention_days, :tab, :url_options

      def empty_state = @hidden_items ? "hidden" : "empty.#{EMPTY_STATES.fetch(tab)}"

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

        named = members.select { |member| readable_member_ids.include?(member.id) }.first(NAMED_SUBPAGES).map { |m| m.title.presence || t(".untitled") }
        count = members.size
        return t(".subpages.bare", count:) if named.empty?

        names = named.join(t(".name_separator"))
        rest = count - named.size
        rest.positive? ? t(".subpages.named_more", count:, names:, rest:) : t(".subpages.named", count:, names:)
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
      # - else the event's user (`user_id` may name a user who has been
      #   deleted since: "a deleted user");
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
          elsif event&.via_label then Admin::Ui::UserNameComponent::DELETED_USER
          else return Admin::Ui::UserNameComponent::NOBODY
          end
        return label unless event&.via_label

        # "You, via <token>" with the comma, "<name> via <token>" without: the
        # audit log's own two forms (`Admin::AuditScreen::SentenceComponent`).
        who_actor(item).you ? t(".you_via", token: event.via_label) : t(".via", name: label, token: event.via_label)
      end

      # Who trashed the item as the audit log's actor facts, for the row's
      # avatar (`Admin::Ui::ActorAvatarComponent`): read from the same two
      # sources, in the same order, as `#who_label`, so the circle and the
      # name beside it are one person. A token's event with no user stands
      # for a deleted user by the token's id, as `Audit::Sentence` does, and
      # nobody recorded is System (no user, no id).
      def who_actor(item)
        event = trashing_event(item)
        user, user_id =
          if item.trashed_by then [ item.trashed_by, item.trashed_by.id ]
          elsif event&.user_id then [ event.user, event.user_id ]
          elsif event&.via_label then [ nil, event.actor_id ]
          else [ nil, nil ]
          end
        Audit::Sentence::Actor.new(you: you?(user), user:, user_id:, via_label: event&.via_label, none: false)
      end

      # A user who was there: "You", their name, or -- gone since -- "a deleted
      # user" (`Admin::Ui::UserNameComponent`, the one place a user is named).
      def label_for(user)
        return t(".you") if you?(user)

        user ? Admin::Ui::UserNameComponent.new(user:).label : Admin::Ui::UserNameComponent::DELETED_USER
      end

      def you?(user) = user.present? && Current.actor.is_a?(User) && Current.actor.id == user.id

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
            events.includes(:user).newest_per_subject
              .index_by { |event| [ event.subject_type, event.subject_id ] }
          end
      end

      # A branch member shares its root's `trash_root_id`; a separately
      # trashed descendant is its own root (`trash_root_id = id`) and has
      # a row of its own instead.
      def subpages_by_root
        @subpages_by_root ||= Page.where(trash_root_id: pages.map(&:id)).trash_branch_members
          .order(:id).group_by(&:trash_root_id)
      end

      # How many pages a purge of each listed page would take with it --
      # every descendant, branch member or trashed separately, the same set
      # `Trash::Purge` destroys -- off the closure table in one query.
      def descendant_counts
        @descendant_counts ||= begin
          hierarchies = Page.hierarchy_class
          hierarchies.where(ancestor_id: pages.map(&:id)).where(hierarchies.arel_table[:generations].gt(0)).group(:ancestor_id).count
        end
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

      # `[label, id]` pairs of the kept pages the viewer may create pages under,
      # labelled with the page's own path of titles ("Home / About / Team") so
      # two pages that share a title can be told apart. Every ancestor of a kept
      # page is kept (`Trash::Move` takes a page's whole branch), so the titles
      # are read off one load of the kept pages rather than per candidate.
      def parent_choices
        @parent_choices ||= begin
          kept = Page.kept.select(:id, :parent_id, :title).index_by(&:id)
          AccessControl.creatable_parents(Current.actor, kept.values).map { |page| [ path_label(page, kept), page.id ] }.sort_by(&:first)
        end
      end

      def path_label(page, kept)
        chain = []
        while page
          chain.unshift(page.title.presence || t(".untitled"))
          page = kept[page.parent_id]
        end
        chain.join(t(".path_separator"))
      end
    end
  end
end
