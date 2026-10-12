module Trash
  # Moves a page (with its whole branch), a post or a library image to the
  # trash (trash spec §4.1). Nothing is deleted: the rows stay, flagged
  # `trashed_at`, so `Trash::Restore` is a column update. Saving the flag is
  # what frees the URLs -- `PublicSite::Paths` computes no path for a
  # trashed record, so the model callbacks delete its `public_paths` rows,
  # redirects included, and re-derive every post a trashed listing page gave
  # a URL (`PublicSite::Paths.refresh`, the hosted posts). Tags, blocks, relations and
  # `media_usages` rows all stay as they are, so a restore needs to rebuild
  # nothing but URLs.
  #
  # A branch is flagged with `update_all` first and the root saved last, so
  # the root's single `sync_subtree` pass sees every descendant already
  # trashed -- saving each page would re-walk the subtree once per page.
  # Every *kept* descendant must go: `PublicSite::Paths.canonical_page`
  # only asks whether a listing page itself is trashed, never its
  # ancestors, so a kept page left under a trashed one would keep handing
  # out post URLs. A descendant already in the trash keeps its own
  # `trashed_at`/`trash_root_id` -- it was trashed on its own, earlier, and
  # restoring this branch shouldn't bring it back with it.
  #
  # An image is refused while any *kept* page or post still uses it
  # (`Media::Asset#used_by_kept_owner?`). Rich-text image rendering doesn't
  # look at an asset's trash state, which is only safe because of this
  # refusal: the only owners left pointing at a trashed image are
  # themselves in the trash.
  #
  # One `<kind>.trashed` event per call, subject the item actually picked;
  # a page's event lists the descendants that came along in
  # `metadata["descendant_ids"]`, which `Trash::Restore` and the audit log
  # can read back without re-deriving the branch.
  class Move < ApplicationService
    include ItemPermissions

    def initialize(record, actor: Current.actor)
      @record = record
      @actor = actor
    end

    def call
      refused = item_refusal(@record) { |key| authorize!(key, @record) }
      return denied(refused, @record) if refused
      return failure(@record, [ "It's already in the trash" ]) if @record.trashed?
      return failure(@record, [ "The homepage can't be moved to the trash" ]) if page? && @record.root?
      return failure(@record, [ @record.in_use_message(kept_only: true, actor:) ]) if @record.is_a?(Media::Asset) && @record.used_by_kept_owner?

      # A savepoint of its own (`requires_new`), like every other writing
      # service: inside a caller's joinable transaction, a plain nested
      # block wouldn't roll back when the root's `save!` raises -- the
      # rescue below swallows the exception before the outer transaction
      # sees it -- leaving the descendants' `update_all` in place under a
      # kept root.
      @record.class.transaction(requires_new: true) do
        descendant_ids = page? ? trash_descendants : []
        @record.assign_attributes(trashed_at: now, trashed_by: actor_user, **(page? ? { trash_root_id: @record.id } : {}))
        # Without validations: setting the trash flags can't make a valid
        # record invalid, and one that has gone invalid since its last save
        # (a plugin's content type unregistered, a stricter rich-text
        # schema, a slug reserved by a later ADMIN_PATH change, an image
        # whose file is gone) must still be clearable -- the permanent
        # delete this replaced never validated either. Callbacks still run,
        # so the URL sync above happens as usual. `Trash::Restore` keeps
        # full validation: what comes back to the live site must be valid.
        @record.save!(validate: false)
        record_event("#{event_prefix}.trashed", subject: @record, metadata: descendant_ids.any? ? { descendant_ids: } : {})
      end

      success(@record)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved
      # A callback halting the save (`RecordNotSaved`) or raising on a
      # record it saves in turn (`RecordInvalid`). The savepoint has rolled back the descendants' `update_all` along
      # with the event; only the in-memory flag is left to undo, so the
      # record the caller holds still reads as kept.
      @record.restore_attributes(%w[trashed_at trashed_by_id trash_root_id].select { |name| @record.has_attribute?(name) })
      @record.association(:trashed_by).reset
      failure(@record)
    end

    private

    def page? = @record.is_a?(Page)

    # One timestamp for the whole move, so a branch reads as trashed
    # together.
    def now = @now ||= Time.current

    def trash_descendants
      ids = @record.descendants.kept.pluck(:id)
      Page.where(id: ids).update_all(trashed_at: now, trashed_by_id: actor_user&.id, trash_root_id: @record.id, updated_at: now)
      bump_public_version_for(ids)
      ids
    end

    # The members were flagged around the callbacks, so their own
    # `after_commit` never runs: a live one among them moves the public
    # content version here (the root's save bumps for the root itself).
    def bump_public_version_for(ids)
      PublicSite.bump_version! if ids.any? && Page.where(id: ids).published.exists?
    end

    def event_prefix = { Page => "page", Post => "post", Media::Asset => "media" }.fetch(@record.class)
  end
end
