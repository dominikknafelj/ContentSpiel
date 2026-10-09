module Notes
  # Starts a thread on a page, a post, a block or a library image, with its
  # first message (notes spec §3.5). Needs the container's read right.
  #
  # A NOTE NEVER WRITES THE RECORD IT IS ON: no `touch`, no `updated_at`, no
  # public content version. An autosave base is never moved by a note.
  #
  # EXISTENCE UNDER A LOCK. The subject is re-read inside the transaction,
  # the container's row lock first (`Authorization#lock_container`), then,
  # for a block, the block among that page's. A block deleted or a page
  # purged a moment ago is an ordinary failure, and one deleted a moment
  # later finds this thread in `Notes::Remove`, which runs under the same
  # lock.
  class Start < ApplicationService
    include Authorization

    def initialize(subject, body:, quote: nil, origin_view: "editor", origin_locale: nil, actor: Current.actor)
      @subject = subject
      @body = body.to_s.strip
      @quote = quote.to_s.strip.first(Thread::MAX_QUOTE).presence
      @origin_view = Thread::ORIGIN_VIEWS.include?(origin_view.to_s) ? origin_view.to_s : "editor"
      @origin_locale = Locales.enabled?(origin_locale) ? origin_locale.to_s : nil
      @actor = actor
    end

    def call
      container = Notes.container_for(@subject)
      refused = read_refusal(container) { |key| authorize!(key, container) }
      return denied(refused, container) if refused

      errors = body_errors(@body).presence || mention_errors(Mentions.ids(@body), container)
      return failure(nil, errors) if errors.any?

      thread = Thread.transaction(requires_new: true) do
        next unless subject_still_there?(container)

        created = Thread.create!(subject: @subject, quote: @quote, origin_view: @origin_view, origin_locale: @origin_locale,
          created_by: actor_user, last_message_at: Time.current)
        message = created.messages.create!(author: actor_user, body: @body)
        created.update!(last_message_at: message.created_at)
        Deliveries.for_new_message(message, actor_user: actor_user)
        record_event("note.started", subject: @subject, snapshot: nil, metadata: note_metadata(created, message))
        created
      end

      thread ? success(thread) : failure(nil, [ gone(kind_of(@subject)) ])
    end

    private

    # A block whose page is gone has no container (`Authorization`, "A
    # container that is nil"): the sentence names the subject, as below.
    def gone_kind = kind_of(@subject)

    def subject_still_there?(container)
      return false unless lock_container(container)

      !@subject.is_a?(ContentBlock) || ContentBlock.where(id: @subject.id, owner: container).exists?
    end
  end
end
