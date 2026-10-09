module Notes
  # The checks every notes service shares (notes spec §3.4). Notes follow the
  # content: reading, starting, replying, resolving and following need the
  # container's READ right; deleting someone else's note and pinning need its
  # EDIT right (an image: `media.manage`, or its uploader with `media.upload`,
  # `Media::Ownership`). A refusal names the container, the record whose
  # right was missing.
  #
  # `lock_container` is the first statement of every notes transaction: the
  # container's row lock, read through `kept`, so a record trashed or purged
  # meanwhile reads as gone. It is the same first lock every write to a
  # page's blocks takes (`ContentBlocks::Structure#lock_owner`: the page's
  # row, then block rows), so a note and a block's delete run one after the
  # other, never interleaved, and `Notes::Remove` can't miss a thread written
  # beside it.
  module Authorization
    include Media::Ownership

    private

    # Both yield the key to check and answer the refused key, or nil, like
    # `ContentBlocks::OwnerPermissions#owner_refusal`: the service itself
    # writes `authorize!(key, container)` in the block, which is what
    # `test/services/service_contract_test.rb` looks for in its class body.
    def read_refusal(container)
      key = Notes.read_key(container)
      key unless yield(key)
    end

    def moderation_refusal(container)
      key = Notes.moderate_key(container)
      return if yield(key)
      return if container.is_a?(Media::Asset) && uploader_may_manage?(container)

      key
    end

    def own?(message) = actor_user.present? && message.author_id == actor_user.id

    # What the text itself gets wrong, read from the text alone: no query. A
    # service asks `mention_errors` only when this is empty, so a body with
    # too many mentions is refused before anyone is looked up.
    def body_errors(body)
      return [ I18n.t("admin.notes.errors.blank") ] if body.blank?
      return [ I18n.t("admin.notes.errors.too_long") ] if body.length > Message::MAX_BODY
      return [ I18n.t("admin.notes.errors.too_many_mentions") ] if Mentions.ids(body).size > Mentions::MAX

      []
    end

    # A mention is addressed to a person: it must name a user who exists and
    # who may read the record, or the inbox would show them a title and a
    # quote they are not allowed to see. Judged as that user would be judged
    # in CS Studio (`:admin`), whatever channel this call runs on.
    #
    # THE REFUSAL NAMES NOBODY. It is one sentence for the whole message,
    # the same for one id or several, and the same for an id that belongs to
    # no user: the token can be typed by hand, so a sentence with a name in
    # it (or a different one for "no such user") would let anyone who may
    # read one page list the names and emails of users who can't, and learn
    # which ids exist, by sending `@[1] @[2] ...`.
    def mention_errors(user_ids, container)
      return [] if user_ids.empty?

      users = User.where(id: user_ids).to_a
      return [] if users.size == user_ids.uniq.size && users.all? { |user| Notes.readable?(user, container, channel: :admin) }

      [ I18n.t("admin.notes.errors.mention_cannot_read.#{kind_of(container)}") ]
    end

    # Nil for a container in the trash or gone: every service that writes to
    # an existing thread (`Reply`, `EditMessage`, `DeleteMessage`, and through
    # `with_locked_thread` `Resolve`, `Reopen`, `Pin`, `Unpin`, `SetFollowing`;
    # `MarkRead` when it names a record) then
    # answers `gone("note")` and writes nothing, so none of them runs
    # without this lock beside `Trash::Purge`.
    def lock_container(container) = container.class.kept.where(id: container.id).lock.pick(:id)

    # The thread re-read and locked, under its container's lock: the block's
    # value, or `:gone` when the thread, or what it is on, is no longer there
    # (a container in the trash reads as gone, `lock_container`). The lock is
    # the first statement of the transaction, before any notes row is read.
    def with_locked_thread(thread)
      Thread.transaction(requires_new: true) do
        current = lock_container(thread.container) && Thread.where(id: thread.id).lock.first
        current ? yield(current) : :gone
      end
    end

    # What `with_locked_thread` answered, as a Result: `:gone` and a sentence
    # are failures, anything else is the record of a success.
    def thread_answer(outcome, thread)
      case outcome
      when :gone then failure(thread, [ gone("note") ])
      when String then failure(thread, [ outcome ])
      else success(outcome)
      end
    end

    def kind_of(record)
      { "Page" => "page", "Post" => "post", "ContentBlock" => "block", "Media::Asset" => "image" }.fetch(record.class.polymorphic_name)
    end

    def gone(kind) = I18n.t("admin.notes.errors.gone.#{kind}")

    # Ids only (decision D14): the log is append-only, so a note's text in it
    # would outlive the note.
    def note_metadata(thread, message = nil)
      { "thread_id" => thread.id, "message_id" => message&.id }.compact
    end
  end
end
