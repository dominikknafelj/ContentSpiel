module Notes
  # Adds the actor's reaction to a message, or takes it back (a toggle;
  # notes spec §3.5, decision D10). Needs the read right, like a reply:
  # whoever may read the record may react (D3). An emoji that is not one of
  # the set the composer and the chips offer (`Notes::EMOJI`) is refused, so
  # a forged value is never stored and never drawn.
  #
  # It tells nobody: no delivery row, so nothing reaches an inbox, the
  # sidebar's count, a toast or the chime. It moves no date (the thread's
  # `last_message_at`, the message's `updated_at`) and never writes the
  # record the note is on. Only the record's stream is signalled
  # (`Notes::Signals.threads`), so a thread open in another tab redraws its
  # chips.
  #
  # Like every notes write on an existing thread, the container's row lock is
  # the first statement of the transaction (`with_locked_thread`), and a
  # record in the trash or purged, a thread removed a moment ago and a
  # message deleted in another tab are the ordinary failure "This note is
  # gone", with nothing written and no signal. Under that lock two presses of
  # the same chip run one after the other, so the unique index is never what
  # answers the second.
  class React < ApplicationService
    include Authorization

    # audit: none (a reaction is an acknowledgement, not a change to content or to a note's text)

    def initialize(message, emoji:, actor: Current.actor)
      @message = message
      @emoji = emoji.to_s
      @actor = actor
    end

    def call
      # `&.`: a message loaded before its thread was removed has none
      # (`Authorization`, "A container that is nil").
      thread = @message.thread
      container = thread&.container
      refused = read_refusal(container) { |key| authorize!(key, container) }
      return denied(refused, container) if refused
      return failure(@message, [ I18n.t("admin.notes.errors.emoji") ]) unless Notes::EMOJI.include?(@emoji)
      return success(@message) unless actor_user

      outcome = with_locked_thread(thread) do |current|
        # Among the locked thread's own messages: never a message by its id alone.
        next :gone unless Message.where(id: @message.id, thread_id: current.id).exists?

        mine = Reaction.find_by(message_id: @message.id, user_id: actor_user.id, emoji: @emoji)
        mine ? mine.destroy! : Reaction.create!(message_id: @message.id, user_id: actor_user.id, emoji: @emoji)
        Signals.threads(current)
        @message
      end
      thread_answer(outcome, @message)
    end
  end
end
