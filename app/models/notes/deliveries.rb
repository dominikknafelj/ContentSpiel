module Notes
  # Who follows a thread and who is told about what (notes spec §3.3, D17).
  # Called by the services inside the transaction of the action, so a
  # rolled-back note tells nobody.
  #
  # FOLLOWING. A message's author and everyone it mentions follow the thread:
  # a missing row is created; an author's explicit unfollow is left alone
  # (writing again is not asking to be told again); a mentioned person's
  # unfollow is undone (the mention is addressed to them).
  #
  # DELIVERIES.
  # - a new message: everyone it mentions (`mention`), and every follower
  #   (`reply`). A mention wins over a reply. On a thread's first message the
  #   followers are its author and the mentioned, so only mentions are told.
  # - an edit: only the people it newly mentions.
  # - a resolve or a reopen: every follower (`resolved`, `reopened`), on the
  #   thread's FIRST message.
  #
  # Never the person who did it, and at most one row per person and message
  # (the unique index). That rule meets the last bullet: someone mentioned in
  # the first message already has a row for it, and so does every follower
  # after the first resolve. The row is REUSED -- it takes the new reason and
  # is unread again -- because the newest thing to tell that person about
  # that message is what just happened to the thread. The same goes for an
  # edit that mentions someone the message had already told as a reply.
  #
  # A mentioned id whose user is gone follows nothing and is told nothing; a
  # follower who lost the right to read the record still gets the row, which
  # the inbox does not show (`Notes.readable_threads`).
  #
  # Every row written here, new or reused, signals its person's stream once
  # the action has committed (`Notes::Signals.delivery`): an id and a reason,
  # which the inbox's own scoped request then answers or doesn't.
  module Deliveries
    module_function

    def followers(thread) = Follow.where(thread_id: thread.id, following: true).pluck(:user_id)

    def follow(thread, author_id:, mentioned_ids:)
      # `can_sign_in`: an invited person follows nothing and is told nothing.
      mentioned = mentioned_ids.empty? ? [] : User.can_sign_in.where(id: mentioned_ids).pluck(:id)
      user_ids = ([ author_id ] + mentioned).compact.uniq
      rows = Follow.where(thread_id: thread.id, user_id: user_ids).index_by(&:user_id)
      user_ids.each do |user_id|
        row = rows[user_id]
        if row.nil?
          Follow.create!(thread_id: thread.id, user_id: user_id, following: true)
        elsif !row.following && mentioned.include?(user_id)
          row.update!(following: true)
        end
      end
    end

    def for_new_message(message, actor_user:)
      follow(message.thread, author_id: message.author_id, mentioned_ids: message.mentioned_user_ids)
      reasons = followers(message.thread).index_with { "reply" }.merge(message.mentioned_user_ids.index_with { "mention" })
      write(message, reasons, actor_user)
    end

    def for_edit(message, newly_mentioned:, actor_user:)
      follow(message.thread, author_id: nil, mentioned_ids: newly_mentioned)
      write(message, newly_mentioned.index_with { "mention" }, actor_user)
    end

    def for_state(thread, reason, actor_user:)
      first = thread.first_message or return []
      write(first, followers(thread).index_with { reason }, actor_user)
    end

    def write(message, reasons, actor_user)
      reasons = reasons.except(actor_user&.id)
      return [] if reasons.empty?

      User.can_sign_in.where(id: reasons.keys).order(:id).pluck(:id).map do |user_id|
        delivery = Delivery.find_or_initialize_by(user_id: user_id, message_id: message.id)
        delivery.update!(thread_id: message.thread_id, reason: reasons.fetch(user_id), read_at: nil)
        Signals.delivery(delivery)
        delivery
      end
    end
  end
end
