module Notes
  # Marks the ACTOR'S OWN deliveries read (notes spec §3.3): those of one
  # thread (opening the thread does this), those on all of one record's
  # threads, or all of them ("Mark all read"). With a thread or a container it
  # needs that container's read right; without either there is nothing to
  # check -- the rows are the actor's own, and reading them tells nobody
  # anything.
  #
  # With a thread or a container it also follows the one rule of every notes
  # write on an existing thread: the container's row lock is the first
  # statement of the transaction (`Authorization#lock_container`), and a
  # record in the trash, or purged, is the ordinary failure "This note is
  # gone" with nothing written. "Mark all read" names no record, so it takes
  # no lock: it is one UPDATE of the actor's own rows, and a row `Trash::Purge`
  # deletes beside it is simply not there to mark. It marks EVERY unread row
  # of the actor's, the ones the inbox is hiding at that moment included (a
  # record in the trash, a right since lost): accepted, because a row that
  # comes back into view read is a smaller surprise than a button that says
  # "all" and leaves a count behind.
  #
  # `updated_at` is NOT written: it is when the row last had something new to
  # tell (`Notes::Deliveries` reuses a row for a resolve), which the inbox
  # sorts and dates by (`Delivery.inbox_order`). Reading a row is not news,
  # and must not move it above what was read before it.
  #
  # Signals nobody (`Notes::Signals`): a person's stream says that a row was
  # WRITTEN for them, and a read mark is no news to anyone else.
  class MarkRead < ApplicationService
    include Authorization

    # audit: none (a read mark is the reader's own bookkeeping, not a change to content or to a note)

    def initialize(thread: nil, container: nil, actor: Current.actor)
      @thread = thread
      @container = thread ? thread.container : container
      # A thread whose record is gone names a record all the same: it must
      # not read as "Mark all read", which names none and checks nothing.
      @names_record = thread.present? || container.present?
      @actor = actor
    end

    def call
      if @names_record
        refused = read_refusal(@container) { |key| authorize!(key, @container) }
        return denied(refused, @container) if refused
      end
      return success(nil) unless actor_user

      marked = Delivery.transaction(requires_new: true) do
        next false if @names_record && !lock_container(@container)

        unread_rows.update_all(read_at: Time.current) # version: none (note_deliveries is a person's inbox; no public page reads it)
        true
      end

      marked ? success(nil) : failure(nil, [ gone("note") ])
    end

    private

    # The actor's unread rows the call names: one thread's, one record's, or all.
    def unread_rows
      rows = Delivery.unread.where(user_id: actor_user.id)
      if @thread
        rows.where(thread_id: @thread.id)
      elsif @container
        rows.where(thread_id: Thread.where(container: @container).select(:id))
      else
        rows
      end
    end
  end
end
