module Trash
  # Brings a trashed page (with the pages trashed together with it), post or
  # image back (trash spec §4.2). Clearing `trashed_at` and saving is what
  # rebuilds URLs: `PublicSite::Paths` computes a path again, and the model
  # callbacks write it (a page resyncs its subtree and the posts its listing
  # blocks give URLs to).
  #
  # A branch comes back the way `Trash::Move` sent it: the page's own
  # descendants that went to the trash in the same move (same
  # `trash_root_id` as the page) are unflagged with `update_all` first and
  # the page saved last, so its single `sync_subtree` pass already sees them
  # kept. That's the same set whether the page is the branch root or a
  # subpage coming back alone under a new parent -- a subpage takes its own
  # subpages along, never leaving them trashed under a kept page (which
  # would also keep handing out listed posts' URLs, see `Trash::Move`). A
  # descendant that went to the trash on its own, earlier, has its own
  # `trash_root_id` and stays where it is -- it wasn't part of what this
  # restore is undoing.
  #
  # Slugs were freed while the record was in the trash, so each locale's slug
  # is checked against kept records first and moved to the first free `-2`,
  # `-3`, ... suffix when taken (`#slug_changes` reports them). Only the
  # record itself needs this: a branch member's siblings are all inside the
  # branch, which nobody could add pages to while it was in the trash.
  #
  # Images the record still references that went to the trash after it come
  # back too (`#restored_assets`) -- a restored page must never point at a
  # trashed image (trash spec corrections, "Images in the trash"). Rich-text
  # image rendering doesn't look at an asset's trash state, so this is what
  # keeps a restored body from rendering one.
  #
  # A page trashed as part of someone else's branch comes back only with its
  # root, or on its own under a new `parent:` -- which needs what
  # `Pages::Move` needs: `pages.move` on the page and `pages.create` under the
  # target. Everything is assigned before one save (parent, position and the
  # cleared flags together), so `Page::TreeRanking#place_among_siblings`
  # never runs while the page still reads as trashed.
  class Restore < ApplicationService
    include ItemPermissions

    attr_reader :slug_changes, :restored_assets

    def initialize(record, parent: nil, actor: Current.actor)
      @record, @parent, @actor = record, parent, actor
      @slug_changes = []
      @restored_assets = []
    end

    def call
      refused = item_refusal(@record) { |key| authorize!(key, @record) }
      return denied(refused, @record) if refused
      return failure(@record, [ "It isn't in the trash" ]) unless @record.trashed?
      if page?
        problem = page_problem
        return problem if problem
      end

      # A savepoint of its own (`requires_new`), for the same reason as
      # `Trash::Move`: the rescue below would otherwise swallow the exception
      # before a caller's outer transaction saw it, leaving the branch
      # members' `update_all` in place under a still-trashed root.
      @record.class.transaction(requires_new: true) do
        branch_ids = page? ? restore_branch_members : []
        page? && @parent ? move_under_new_parent : keep_rank
        free_slugs
        @record.assign_attributes(trashed_at: nil, trashed_by: nil, **(page? ? { trash_root_id: nil } : {}))
        @record.save!
        restore_referenced_assets(branch_ids)
        record_event("#{event_prefix}.restored", subject: @record, metadata: event_metadata(branch_ids))
        # Each image that came along gets its own event too, so an image's
        # history in the audit log shows it leaving the trash, not only its
        # owner's.
        @restored_assets.each do |asset|
          record_event("media.restored", subject: asset.reload, metadata: { restored_with: "#{@record.class.name}##{@record.id}" })
        end
      end

      success(@record)
    rescue ActiveRecord::RecordInvalid
      # The savepoint has rolled back the branch members, the assets and the
      # event; what's left is the in-memory record, put back to how the
      # caller handed it over (still trashed, old parent, old slugs).
      @record.restore_attributes
      @record.association(:trashed_by).reset
      @record.association(:parent).reset if page?
      @slug_changes = []
      @restored_assets = []
      failure(@record)
    end

    private

    def page? = @record.is_a?(Page)

    def page_problem
      if @parent
        return denied("pages.move", @record) unless authorize!("pages.move", @record)
        return denied("pages.create", @record) unless may_create_under_target?
        # The more specific answer first: a trashed page's subpages are
        # (usually) trashed with it, so checking the trash first would hide
        # why picking one of them can never work.
        return failure(@record, [ "A page can't be restored under itself or one of its own subpages" ]) if @parent.self_and_ancestors.include?(@record)
        return failure(@record, [ "Choose a page that isn't in the trash" ]) if @parent.trashed?
      elsif @record.parent_id.nil? || !Page.exists?(@record.parent_id)
        return failure(@record, [ "Its parent page no longer exists: choose a new parent" ])
      elsif @record.trash_root_id != @record.id
        root = Page.find_by(id: @record.trash_root_id)
        return failure(@record, [ "Restore #{branch_root_name(root)} to bring this page back, or choose a new parent" ])
      elsif @record.parent.trashed?
        return failure(@record, [ "Its parent page is in the trash: restore that first, or choose a new parent" ])
      end
      nil
    end

    # Same check-then-put-back as `Pages::Move#may_create_under_target?`:
    # `pages.create` reads the branch from the assigned `parent`.
    def may_create_under_target?
      original = @record.parent
      @record.parent = @parent
      authorize!("pages.create", @record)
    ensure
      @record.parent = original
    end

    def restore_branch_members
      ids = @record.descendants.where(trash_root_id: @record.trash_root_id).pluck(:id)
      Page.where(id: ids).update_all(trashed_at: nil, trashed_by_id: nil, trash_root_id: nil, updated_at: Time.current)
      ids
    end

    # Rejoins last among its new, kept siblings: the "rank" `Page::
    # TreeRanking` reads off `position` counts kept siblings only, so their
    # count is one past the end.
    def move_under_new_parent
      @record.parent = @parent
      @record.position = Page.kept.where(parent_id: @parent.id).count
    end

    # Restored in place: back at the rank it had. Trashing never renumbers
    # siblings, so the kept ones may have been re-ranked 0..n-1 around the
    # gap since, leaving this page's stored number tied with one of theirs;
    # forcing a "change" makes `place_among_siblings` treat the old number
    # as a requested rank and write the siblings out densely again.
    def keep_rank
      @record.position_will_change! if page?
    end

    # Taken slugs move to the first free suffix, per locale; an image has no
    # slug at all.
    def free_slugs
      return unless @record.respond_to?(:slug_taken?)

      Locales.enabled.each do |locale|
        accessor = Mobility.normalize_locale_accessor(:slug, locale)
        original = @record.public_send(accessor)
        next if original.blank? || !@record.slug_taken?(locale, original)

        candidate = (2..).lazy.map { |n| "#{original}-#{n}" }.find { |slug| !@record.slug_taken?(locale, slug) }
        @record.public_send("#{accessor}=", candidate)
        @slug_changes << { record: @record, locale: locale.to_s, from: original, to: candidate }
      end
    end

    # Every trashed library image the restored owners still use, read off
    # `media_usages` (heroes, image blocks and rich-text image nodes alike).
    def restore_referenced_assets(branch_ids)
      ids = owners_for_assets(branch_ids).flat_map do |type, owner_ids|
        Media::Usage.where(owner_type: type, owner_id: owner_ids).pluck(:media_asset_id)
      end.uniq
      @restored_assets = Media::Asset.trashed.where(id: ids).order(:id).to_a
      Media::Asset.where(id: @restored_assets.map(&:id)).update_all(trashed_at: nil, trashed_by_id: nil, updated_at: Time.current)
    end

    def owners_for_assets(branch_ids)
      case @record
      when Page
        page_ids = [ @record.id, *branch_ids ]
        { "Page" => page_ids, "ContentBlock" => ContentBlock.where(owner_type: "Page", owner_id: page_ids).pluck(:id) }
      when Post
        { "Post" => [ @record.id ], "ContentBlock" => ContentBlock.where(owner: @record).pluck(:id) }
      else {}
      end
    end

    def event_prefix = { Page => "page", Post => "post", Media::Asset => "media" }.fetch(@record.class)

    # `restored_page_ids` mirrors `page.trashed`'s `descendant_ids`: the
    # branch members that came back with the page (empty, so dropped, for a
    # post, an image or a page restored alone).
    def event_metadata(branch_ids)
      {
        restored_page_ids: branch_ids,
        slug_changes: @slug_changes.map { |change| change.except(:record).merge(record: "#{change[:record].class.name}##{change[:record].id}") },
        restored_asset_ids: @restored_assets.map(&:id)
      }.compact_blank
    end
  end
end
