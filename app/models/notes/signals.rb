module Notes
  # What is pushed to open CS Studio tabs (notes spec §6.1, decision D16).
  # A SIGNAL CARRIES NO NOTE TEXT, NO TITLE AND NO NAME: a kind and ids. The
  # browser then fetches the part again through the same scoped request it
  # uses on load, so a push can never show a note to someone who may not read
  # it, whatever changed since they subscribed. `test/models/notes/
  # signals_test.rb` asserts it on every broadcast of every notes service,
  # and fails for a service that has no case there.
  #
  # Two streams. A PERSON's: "a delivery row was written for you" -- the
  # inbox, the sidebar's count, the toast, the chime -- and "your inbox got
  # smaller" (`inbox`: rows of yours were read in another tab, or went with
  # a deleted note), which names nothing at all: the tab asks for its count
  # again. A RECORD's: "a thread of this page, post or image changed" -- the
  # list or the thread showing it, and the count markers. `origin`, on a
  # record's signal and on `inbox`, is the opaque id of the browser tab
  # whose request made the change (`Current.notes_tab`), so that
  # tab does not fetch again what its own answer already showed it. It comes
  # from the client, so it is echoed only in the shape `TAB` allows -- an id
  # a tab made up, never a sentence -- and checked here as well as where the
  # header is read: this is the last place before it leaves.
  #
  # AFTER COMMIT. Each is called from inside a service's transaction and sent
  # once every transaction open at that moment has committed
  # (`ActiveRecord.after_all_transactions_commit`): a service's own
  # `requires_new` savepoint hands the callback up to the transaction around
  # it, so `Notes::Remove` inside a purge signals when the purge commits, and
  # a rollback at any level sends nothing. A tab told before the commit would
  # fetch and find the old rows, and nothing would tell it again. What is
  # sent is decided when the method is called, not when it is sent: by then
  # the thread may be deleted and `Current` reset.
  #
  # A PUSH IS BEST EFFORT. A broadcast that fails (the cable's database is
  # away) is reported, logged and swallowed -- the log line holds the
  # signal's kind and the error's CLASS, never its message (a driver's
  # message can quote what it was sending) and never the payload: the note
  # is already committed, a tab that missed the signal shows it on its next
  # load, and an exception here
  # would turn a saved note into an error page and stop the callbacks queued
  # behind it in the same commit -- a deferred `PublicSite.bump_version!`
  # among them, when the signal is `Notes::Remove`'s inside a purge.
  module Signals
    TAB = /\A[a-z0-9-]{8,40}\z/

    module_function

    def person_stream(user_id) = "notes:person:#{user_id}"

    def record_stream(container_type, container_id) = "notes:record:#{Notes.key(container_type, container_id)}"

    # A delivery row was written or reused for its person.
    def delivery(delivery)
      later(person_stream(delivery.user_id), { kind: "delivery", delivery_id: delivery.id, reason: delivery.reason })
    end

    # This person's inbox holds fewer rows, or fewer unread ones, than a
    # moment ago. No ids: there may be no row left to name.
    def inbox(user_id)
      later(person_stream(user_id), { kind: "inbox", origin: origin }.compact)
    end

    # A thread of its container changed.
    def threads(thread) = threads_removed(thread.container_type, thread.container_id, thread.id)

    # The same signal for a thread there is no row of any more.
    def threads_removed(container_type, container_id, thread_id)
      later(record_stream(container_type, container_id), { kind: "threads", thread_id: thread_id, origin: origin }.compact)
    end

    def origin = Current.notes_tab.to_s[TAB]

    def later(stream, payload)
      ActiveRecord.after_all_transactions_commit do
        ActionCable.server.broadcast(stream, payload)
      rescue StandardError => error
        Rails.logger.warn("Notes signal not sent (#{payload[:kind]}): #{error.class}")
        Rails.error.report(error, handled: true)
      end
      nil
    end
  end
end
