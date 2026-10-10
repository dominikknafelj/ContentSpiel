module Trash
  # Deletes a trashed item for good (trash spec §4.3) -- the permanent
  # delete that `Pages::Destroy`/`Posts::Destroy`/`Media::Destroy` used to
  # be, now only reachable from the trash. Allowed by the item's own delete
  # right (`ItemPermissions`) or by `trash.empty` (trash spec corrections,
  # "`trash.empty` includes single purges"), which is how `Trash::Empty` and
  # the retention job reach it.
  #
  # A page takes its whole subtree, deepest first; every page in it must be
  # trashed. A descendant trashed separately, earlier, goes too -- its
  # parent is going. A kept one would mean someone restored it under this
  # page's branch, which `Trash::Restore` can't do -- so this is a guard,
  # not a flow. `Page#ensure_no_children` (`before_destroy, prepend: true`)
  # still runs on each destroy and passes because children go first. The
  # homepage never gets here: it can't be moved to the trash. A page that
  # went to the trash as part of another page's branch can't be purged on
  # its own while that branch is still there (`#pending_branch_root`).
  #
  # A post has no descendants; its `has_many ... dependent: :destroy`
  # associations (`post_tags`, `post_relations`, `inverse_post_relations`)
  # clean up after it.
  #
  # An image goes only once *no* usage row points at it, a trashed owner's
  # included -- `Media::Asset#used?`, not `#used_by_kept_owner?` -- with a
  # message saying where it's used (`Media::Asset#in_use_message`), so the
  # editor can purge (or restore and edit) that owner first. The index can
  # be behind -- a reference written outside the services, or a save racing
  # this purge between the check and the `DELETE`: the FKs on `pages`/
  # `content_blocks` still refuse the row, and that
  # `ActiveRecord::InvalidForeignKey` becomes an ordinary failure here,
  # never a 500. (A rich-text `image` node has no FK -- a document that
  # still names a deleted asset renders without it, and `Media::UsageIndex`
  # skips the dead reference.) The file itself is purged only after the
  # delete commits: `has_one_attached`'s default `dependent: :purge_later`
  # enqueues the purge from an `after_destroy_commit`, so a rolled-back
  # delete (the FK case) keeps its file, and storage isn't touched inside
  # the transaction.
  #
  # `<kind>.purged` is recorded *before* the destroy, in its transaction:
  # its snapshot is the record's last state (a post's tags and relations
  # included, which are gone once the destroy has run), and a refused
  # destroy rolls the event back with it. A branch purge records one
  # `page.purged` per page it destroys: the root's lists the rest in
  # `metadata["descendant_ids"]` (mirroring `page.trashed`), and each
  # descendant's names the root in `metadata["purged_with"]`.
  #
  # The notes on what is purged go with it (notes spec D12): `Notes::Remove`
  # is called once, for the page with its branch and all their blocks, for
  # the post or for the image, in this transaction. For a page it runs
  # BEFORE anything is destroyed, under the branch's row locks
  # (`#purge_branch` says why); for a post and an image it runs AFTER the
  # destroy, whose own lock on the row is the one that matters
  # (`#remove_notes`). A trashed record keeps its notes; only this removes
  # them.
  class Purge < ApplicationService
    include ItemPermissions

    def initialize(record, actor: Current.actor)
      @record, @actor = record, actor
    end

    def call
      refused = item_refusal(@record) { |key| authorize!(key, @record) }
      # `trash.empty` is an admin-area key: no subject, so a nil record.
      return denied(refused, @record) if refused && !authorize!("trash.empty", nil)
      return failure(@record, [ "Only items in the trash can be deleted permanently" ]) unless @record.trashed?
      if (root = pending_branch_root)
        return failure(@record, [ "Delete #{branch_root_name(root)} permanently to remove this page" ])
      end

      # A savepoint of its own (`requires_new`), like every writing service:
      # `Trash::Empty` runs one purge after another, and an item that can't
      # go (the FK case below, rescued outside the block) must roll back
      # alone without poisoning the rest of the run.
      purged = @record.class.transaction(requires_new: true) do
        branch = branch_deepest_first if @record.is_a?(Page)
        descendant_ids = branch.to_a.map(&:id) - [ @record.id ]
        record_event("#{event_prefix}.purged", subject: @record, metadata: descendant_ids.any? ? { descendant_ids: } : {})
        case @record
        when Page then purge_branch(branch)
        when Post then purge_post
        when Media::Asset then purge_asset
        end
      end

      # A destroy halted by a callback may add no error of its own --
      # `Result.failure`'s generic fallback would then say "could not be
      # saved", which is the wrong verb here.
      return failure(@record, @record.errors.full_messages.presence || [ "This #{noun} couldn't be deleted" ]) unless purged

      success(@record)
    rescue ActiveRecord::InvalidForeignKey
      failure(@record, [ @record.is_a?(Media::Asset) ? @record.in_use_message(actor:) : "Something still refers to this #{noun}" ])
    end

    private

    # A page trashed as part of another page's branch goes only with that
    # branch: purging it alone would leave the root's later restore
    # (`Trash::Restore`, which brings back exactly the pages sharing its
    # `trash_root_id`) quietly incomplete. Only while that root is itself
    # still in the trash -- once it's been purged (the id no longer
    # resolves) or restored, a leftover member is nobody's pending restore
    # and may go on its own. A subpage trashed on its own, earlier, is its
    # own root (`trash_root_id == id`) and is never refused here.
    def pending_branch_root
      return unless @record.is_a?(Page) && @record.trash_root_id && @record.trash_root_id != @record.id

      root = Page.find_by(id: @record.trash_root_id)
      root if root&.trashed?
    end

    def purge_branch(pages)
      if pages.any? { |page| !page.trashed? }
        @record.errors.add(:base, "A page under it isn't in the trash")
        raise ActiveRecord::Rollback
      end

      # Every page of the branch, locked in id order before anything of it
      # is deleted. The order of locks for a page's blocks is the page's
      # row, then block rows (`ContentBlocks::Save#call`): a block save or
      # delete holds its page and waits for the block. A page's destroy
      # goes the other way -- its blocks' rows first (`dependent: :destroy`),
      # its own row last -- so a save still arriving for a block of a
      # trashed page (an editor tab left open) and this purge could each
      # hold what the other waited for, until Postgres ended one with
      # `ActiveRecord::Deadlocked`. Id order, whatever order the pages are
      # then destroyed in (deepest first, below), so two purges, or a purge
      # and a tag merge (`Tags::Merge#repoint_blocks`), take THESE rows the
      # same way round. A known gap is left: a page's destroy also renumbers
      # its siblings (closure_tree's `_ct_reorder_siblings`), which updates
      # page rows that are not in this branch and so not in this id-ordered
      # lock -- two purges of sibling pages, or a purge and a merge that
      # holds one of those siblings, can still deadlock there. A page
      # already gone is not found, and skipped as before.
      Page.where(id: pages.map(&:id)).order(:id).lock.pluck(:id)

      # The threads on these pages and their blocks (notes spec D12):
      # polymorphic like the usage rows below, so removed by hand, once for
      # the branch, under the locks just taken. Before any page is
      # destroyed, as a rule and not because today's code would fail
      # otherwise: `Notes::Remove` asks this purge's own right again, and a
      # `pages.delete` scoped to a branch is matched against the page's
      # closure rows, which its destroy deletes. The object in hand still
      # answers afterwards, but only because Active Record keeps its
      # `self_and_ancestor_ids` from this purge's first check; a copy of
      # the page read afresh is refused once the rows are gone (both are
      # pinned in `test/services/trash/purge_test.rb`). Asked first, the
      # answer does not depend on that.
      # (`content_blocks.to_a` loads the very objects the loop below reads
      # again and the destroy goes on to destroy.)
      remove_notes(with: (pages - [ @record ]) + pages.flat_map { |page| page.content_blocks.to_a })

      pages.each do |page|
        # Loaded *before* the destroy, so these are the very objects the
        # page's `dependent: :destroy` goes on to destroy (it destroys the
        # loaded association target) -- each is then `destroyed?`, which is
        # what makes `Media::UsageIndex.refresh` drop its rows rather than
        # recompute them from stale attributes.
        blocks = page.content_blocks.to_a
        # Every page this destroys gets its own `page.purged` -- a branch
        # member or a descendant trashed separately, earlier, would
        # otherwise vanish from the log without a trace of its own -- with
        # `purged_with` naming the page the editor actually purged. Before
        # the destroy, in the same transaction, like the root's: the
        # snapshot is the page's last state, and a refusal further down
        # rolls these back too.
        record_event("page.purged", subject: page, metadata: { purged_with: "Page##{@record.id}" }) unless page.equal?(@record)
        unless page.destroy
          @record.errors.merge!(page.errors) unless page.equal?(@record)
          raise ActiveRecord::Rollback
        end
        # The page's hero row and every destroyed block's rows go with them
        # (media library design spec §5.1) -- `media_usages.owner` is
        # polymorphic, so no FK cascade would ever remove them.
        [ page, *blocks ].each { |owner| Media::UsageIndex.refresh(owner) }
        Translations::StateIndex.remove(page)
      end
      true
    end

    # The page and every descendant, deepest first, read off the closure
    # table's `generations` in one query. The root itself is `@record`, the
    # object the caller holds, so its `destroyed?` reads true afterwards.
    # An id whose page is gone between the two queries (a concurrent purge
    # of a separately trashed descendant) is simply skipped -- it's already
    # what this purge wanted -- rather than raising `KeyError` out of the
    # whole branch.
    def branch_deepest_first
      ids = Page.hierarchy_class.where(ancestor_id: @record.id).order(generations: :desc, descendant_id: :asc).pluck(:descendant_id)
      loaded = Page.where(id: ids - [ @record.id ]).index_by(&:id).merge(@record.id => @record)
      ids.filter_map { |id| loaded[id] }
    end

    def purge_post
      @record.destroy || raise(ActiveRecord::Rollback)
      remove_notes
      # A destroyed owner's `media_usages` rows go with it (media library
      # design spec §5.1) -- `refresh` computes none for a destroyed record.
      Media::UsageIndex.refresh(@record)
      Translations::StateIndex.remove(@record)
      true
    end

    def purge_asset
      if @record.used?
        @record.errors.add(:base, @record.in_use_message(actor:))
        raise ActiveRecord::Rollback
      end
      @record.destroy || raise(ActiveRecord::Rollback)
      remove_notes
      Translations::StateIndex.remove(@record)
      true
    end

    # The threads on `@record` and on what goes with it, through
    # `Notes::Remove`. A refusal there (none is expected: it asks the right
    # this purge was just given) rolls the whole purge back, like any refusal
    # further down.
    #
    # A POST AND AN IMAGE: AFTER THE DESTROY, and with no lock taken for it.
    # The destroy's DELETE holds the record's row to the commit, and that
    # row is the first lock every notes service takes, read through `kept`
    # (`Notes::Authorization#lock_container`, the same statement for a post
    # and for an image). So a note started beside this purge -- on a record
    # restored in another tab after the purge had loaded it; a trashed one
    # takes no note at all -- either committed before the destroy got the
    # row, and its thread is found by the removal that follows, or waits on
    # the row and then finds none ("This post is in the trash or was
    # deleted."). No thread is left behind. A row lock taken BEFORE the
    # destroy would do the same and was tried: it turns the purge's order
    # round to the post's row and then its join rows, while `Posts::Save`
    # writes `post_tags` first (`@post.tags =`) and the post after, so a
    # save that changes tags beside a purge of the same post could
    # deadlock, and nothing here rescues `ActiveRecord::Deadlocked`. This
    # way the purge takes its locks in the order it always did.
    #
    # THE OTHER HALF IS STILL OPEN, and is older than notes: `Tags::Merge`
    # takes a post's row and its `post_tags` rows in the opposite order to
    # `Posts::Save`. A purge cannot take them in an order that agrees with
    # both, so the purge of a trashed post that carries a tag, beside a
    # merge of that tag, can still deadlock (a 500, nothing lost, a retry
    # works). No order of this method's fixes it; it is a row of
    # `docs/roadmap.md` and in `docs/reference/notes.md`, "Removal".
    #
    # The right `Notes::Remove` asks again is answered for the destroyed
    # object as it was before: a `content_types` or `own` scope reads the
    # post's own attributes, an image's uploader its `created_by_id`,
    # `trash.empty` and an owner no record at all. Only a page's branch
    # scope reads rows the destroy deletes, which is why a page goes the
    # other way round (`#purge_branch`).
    def remove_notes(with: [])
      Notes::Remove.call(@record, with: with, actor: actor).ok? || raise(ActiveRecord::Rollback)
    end

    def event_prefix = { Page => "page", Post => "post", Media::Asset => "media" }.fetch(@record.class)

    def noun = { Page => "page", Post => "post", Media::Asset => "image" }.fetch(@record.class)
  end
end
