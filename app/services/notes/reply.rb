module Notes
  # Adds a message to a thread (notes spec §3.5). Needs the read right.
  # Replying to a resolved thread reopens it: the reply is the news, so the
  # followers get the `reply` row and the log gets both events.
  #
  # The thread is re-read under the container's lock: one removed meanwhile
  # (its block deleted, its page purged, its last message deleted) is an
  # ordinary failure the drawer shows, never an exception.
  #
  # FILES (`files:`) as in `Notes::Start`: checked by their bytes first
  # (`Notes::Files`), and one refused file refuses the reply.
  #
  # Signals the record's stream once (a reply that reopens is one change to
  # one thread), and each person told theirs (`Notes::Signals`).
  class Reply < ApplicationService
    include Authorization

    def initialize(thread, body:, files: [], actor: Current.actor)
      @thread = thread
      @body = body.to_s.strip
      @files = Array(files)
      @actor = actor
    end

    def call
      container = @thread.container
      refused = read_refusal(container) { |key| authorize!(key, container) }
      return denied(refused, container) if refused

      errors = (body_errors(@body).presence || mention_errors(Mentions.ids(@body), container)) + Files.errors_for(@files)
      return failure(nil, errors) if errors.any?

      stored = true
      message = Thread.transaction(requires_new: true) do
        thread = lock_container(container) && Thread.where(id: @thread.id).lock.first
        next unless thread

        reopened = thread.resolved?
        created = thread.messages.create!(author: actor_user, body: @body)
        # A file that could not be written fails the note, whole.
        unless Files.attach(created, @files)
          stored = false
          raise ActiveRecord::Rollback
        end
        thread.update!(last_message_at: created.created_at, **(reopened ? { state: "open", resolved_at: nil, resolved_by: nil } : {}))
        Deliveries.for_new_message(created, actor_user: actor_user)
        record_event("note.replied", subject: thread.subject, snapshot: nil, metadata: note_metadata(thread, created))
        record_event("note.reopened", subject: thread.subject, snapshot: nil, metadata: note_metadata(thread)) if reopened
        Signals.threads(thread)
        created
      end

      return failure(nil, [ Files.not_stored ]) unless stored

      message ? success(message) : failure(nil, [ gone("note") ])
    end
  end
end
