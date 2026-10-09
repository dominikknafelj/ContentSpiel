module Notes
  # Gives a message the actor's reaction, or takes it back (notes spec §3.5,
  # decision D10). Needs the read right, like a reply: whoever may read the
  # record may react (D3). An emoji that is not one of the set the composer
  # and the chips offer (`Notes::EMOJI`) is refused, so a forged value is
  # never stored and never drawn.
  #
  # THE CALLER SAYS WHICH (`on:`), it is not a blind toggle: a chip sends the
  # state its press is meant to reach, so a POST that is sent twice, or a
  # press in a tab that had not yet seen the reaction given in another, ends
  # where the person meant instead of undoing itself. Asking for what is
  # already so succeeds, writes nothing and signals nobody.
  #
  # A RESOLVED THREAD TAKES NO REACTION and gives none back (the handoff's
  # decision 24: it is closed, and whoever wants to add something reopens
  # it). Its chips are drawn read-only; this refusal is for the request that
  # is sent all the same -- an ordinary failure, nothing written, no signal.
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

    def initialize(message, emoji:, on:, actor: Current.actor)
      @message = message
      @emoji = emoji.to_s
      @on = on ? true : false
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

        next I18n.t("admin.notes.errors.resolved") if current.resolved?

        mine = Reaction.find_by(message_id: @message.id, user_id: actor_user.id, emoji: @emoji)
        next @message if @on == mine.present?

        @on ? Reaction.create!(message_id: @message.id, user_id: actor_user.id, emoji: @emoji) : mine.destroy!
        Signals.threads(current)
        @message
      end
      thread_answer(outcome, @message)
    end
  end
end
