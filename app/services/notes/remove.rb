module Notes
  # Deletes every thread of a record that is being deleted for good, and of
  # the records that go with it (notes spec §3.5, decision D12). Not called by
  # a person: `Trash::Purge` calls it for a page with its branch and blocks, a
  # post and an image, and `ContentBlocks::Destroy` for a block and the blocks
  # deleted with a section. A thread's subject is polymorphic, so no foreign
  # key could do this -- the same reason `Media::UsageIndex.refresh` is called
  # beside it.
  #
  # THE LOCK IS THE CALLER'S. It runs INSIDE the caller's transaction and
  # takes no lock of its own before it reads: the caller already holds the
  # row of every container whose threads go, which is the first lock every
  # notes service takes (`Authorization#lock_container`):
  #
  # - `ContentBlocks::Destroy`: the block's page, `Structure#lock_owner`, the
  #   first statement of its transaction.
  # - `Trash::Purge` of a page: every page of the branch, locked in id order
  #   (`#purge_branch`) before anything of it is deleted. A block's threads
  #   are filed under its page, so that covers the blocks too.
  # - `Trash::Purge` of a post or an image: the row its destroy has just
  #   deleted, held by that DELETE to the commit. No lock is taken ahead of
  #   the destroy (`Trash::Purge#remove_notes` has the deadlock with
  #   `Posts::Save` that one would open).
  #
  # So a note being written beside the delete either committed before and is
  # removed here, or waits for the container's row and finds it gone ("This
  # note is gone…", "This block was deleted."). The read of the ids below
  # cannot miss a thread, and nothing is left behind.
  #
  # THE ORDER OF ITS OWN STATEMENTS is the one the notes services keep:
  # container (held by the caller), then the thread rows, then what hangs on
  # them. The one DELETE names `note_threads`; the messages, deliveries and
  # follows go by their foreign keys' cascade, which Postgres runs after the
  # thread's row is deleted. It never starts from a message. A notes service
  # that touches a thread or a message row holds the container's row while
  # it does (a trashed container is refused before any notes row is locked),
  # so it has either finished or not begun when this runs, and the two can
  # not hold what the other waits for.
  #
  # WHEN IT IS CALLED. For a page, `Trash::Purge` calls it BEFORE it destroys
  # anything: the check below asks the purge's own right again, and a
  # `pages.delete` scoped to a branch is matched against the page's closure
  # rows, which the destroy deletes. The very object the purge checked still
  # answers afterwards (Active Record keeps the ancestor ids it read for
  # that first check), so the purge would not in fact be refused; a page
  # read afresh would be, and asking first depends on neither. For a post
  # and an image `Trash::Purge` calls it AFTER the destroy: every way of
  # holding their delete right is read from the object in memory or from no
  # record at all. `ContentBlocks::Destroy` calls it after the block is
  # gone: a block's right is its page's, and the page is still there.
  #
  # Constant in statements whatever the number of threads and of files: one
  # read of the thread ids, one of the people told, one audit insert, one read
  # of the files (and two DELETEs when there are any, `Notes::Files.remove`),
  # one DELETE. A purge that rolls back keeps every file where it was: the
  # stored bytes are erased only after the outermost commit. `notes.removed` is recorded on
  # `record` with the ids only, and only when there was something to remove.
  #
  # THE SIGNAL (`Notes::Signals`): one per CONTAINER that lost a thread, on
  # that container's record stream, sent when the caller's transaction
  # commits and not at all when it rolls back. It names the lowest thread id
  # removed there; a tab fetches the whole list again whichever it names.
  # And one `inbox` signal per PERSON who had a delivery on any removed
  # thread (read before the delete), so their count goes down in open tabs.
  # A bulk removal therefore broadcasts (containers that had a thread) +
  # (people who had a delivery there) times, whatever the number of threads,
  # at the price of one more read. What the record's signal means for each
  # caller:
  #
  # - `ContentBlocks::Destroy` (a block; a section with its blocks): the
  #   threads are filed under the PAGE, which is still there and may be open
  #   in an editor with its drawer -- one signal on the page's stream, so the
  #   drawer drops the deleted block's group. This is the case it is for.
  # - `Trash::Purge` of a page: one signal per page of the branch that had a
  #   thread (its own or a block's). Nobody is left to hear it: a purged page
  #   was in the trash, where no editor opens and `Notes::RecordChannel`
  #   rejects a subscription, and a tab subscribed since before the trashing
  #   fetches and gets a 404.
  # - `Trash::Purge` of a post or an image: one signal on its stream, for
  #   the same nobody.
  #
  # The purge's signals are sent all the same, by the one rule, because
  # telling a gone record's stream costs a broadcast nobody receives and
  # leaving it out would be a second rule to keep right.
  #
  # It authorizes what its callers already did -- the item's delete right or
  # `trash.empty` for a page, post or image, the page's edit right for a
  # block -- so a refusal never happens on those paths (if it did, the
  # caller rolls back, and the `access.denied` written here inside its
  # transaction goes with it); it is here so that nothing else can call this
  # to wipe notes it may not moderate.
  class Remove < ApplicationService
    include Trash::ItemPermissions

    def initialize(record, with: [], actor: Current.actor)
      @record = record
      @with = Array(with)
      @actor = actor
    end

    def call
      refused = refusal
      return denied(refused, @record) if refused

      Thread.transaction(requires_new: true) do
        rows = threads_on([ @record, *@with ]).order(:id).pluck(:id, :container_type, :container_id)
        next if rows.empty?

        ids = rows.map(&:first)
        # Read before the delete, whose cascade takes the rows.
        told = Delivery.where(thread_id: ids).distinct.pluck(:user_id)
        record_event("notes.removed", subject: @record, snapshot: nil, metadata: { "thread_ids" => ids })
        # The files of the messages about to go (notes spec §3.6), while the
        # messages still say whose they are: the cascade below runs no
        # callback. Rows now, stored bytes when the caller has committed.
        Files.remove(Message.where(thread_id: ids))
        Thread.where(id: ids).delete_all # version: none (note tables only; no public page reads a note)
        rows.uniq { |_id, type, container_id| [ type, container_id ] }.each { |id, type, container_id| Signals.threads_removed(type, container_id, id) }
        told.each { |user_id| Signals.inbox(user_id) }
      end
      success(@record)
    end

    private

    def refusal
      if @record.is_a?(ContentBlock)
        key = "#{AccessControl::Checker::BLOCK_OWNER_PREFIX.fetch(@record.owner.class.name)}.edit"
        return (key unless authorize!(key, @record))
      end

      refused = item_refusal(@record) { |key| authorize!(key, @record) }
      refused unless refused.nil? || authorize!("trash.empty", nil)
    end

    # One relation over every record, whatever their classes.
    def threads_on(records)
      records.group_by { |record| record.class.polymorphic_name }
        .map { |type, list| Thread.where(subject_type: type, subject_id: list.map(&:id)) }.reduce(:or)
    end
  end
end
