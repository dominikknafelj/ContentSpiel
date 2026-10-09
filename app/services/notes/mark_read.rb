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
  # deletes beside it is simply not there to mark.
  class MarkRead < ApplicationService
    include Authorization

    # audit: none (a read mark is the reader's own bookkeeping, not a change to content or to a note)

    def initialize(thread: nil, container: nil, actor: Current.actor)
      @thread = thread
      @container = thread ? thread.container : container
      @actor = actor
    end

    def call
      if @container
        refused = read_refusal(@container) { |key| authorize!(key, @container) }
        return denied(refused, @container) if refused
      end
      return success(nil) unless actor_user

      marked = Delivery.transaction(requires_new: true) do
        next false if @container && !lock_container(@container)

        now = Time.current
        unread_rows.update_all(read_at: now, updated_at: now) # version: none (note_deliveries is a person's inbox; no public page reads it)
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
