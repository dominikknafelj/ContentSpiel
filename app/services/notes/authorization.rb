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
  #
  # A CONTAINER THAT IS NIL. No thread outlives its record (`Notes::Remove`),
  # but a request can still carry one that was loaded a moment before the
  # purge committed: its `container` then reads nil, and so does the `thread`
  # of a message loaded that way and the `owner` of a block whose page went.
  # There is no record left to ask a right of, and none to lock. Both
  # refusal checks below raise `ContainerGone` for it, before anything is
  # read or written, and `AnswersGone` -- prepended to every service that
  # includes this module, so it is said once here and not in each `#call` --
  # turns that into the ordinary failure the drawer shows ("This note is
  # gone…"; `Notes::Start` names its subject instead). It is the answer the
  # same call gets a moment later from `lock_container`, when the record is
  # found in the trash or not at all; before this it was a `NoMethodError`
  # out of the permission lookup, a 500. Nothing is logged as a denial:
  # nobody was refused a right.
  module Authorization
    include Media::Ownership

    ContainerGone = Class.new(StandardError)

    module AnswersGone
      def call
        super
      rescue ContainerGone
        failure(nil, [ gone(gone_kind) ])
      end
    end

    def self.included(service)
      super
      service.prepend(AnswersGone)
    end

    private

    # What the "gone" sentence names when the container is nil: the note,
    # for every service that acts on an existing thread.
    def gone_kind = "note"

    # Both yield the key to check and answer the refused key, or nil, like
    # `ContentBlocks::OwnerPermissions#owner_refusal`: the service itself
    # writes `authorize!(key, container)` in the block, which is what
    # `test/services/service_contract_test.rb` looks for in its class body.
    def read_refusal(container)
      raise ContainerGone if container.nil?

      key = Notes.read_key(container)
      key unless yield(key)
    end

    def moderation_refusal(container)
      raise ContainerGone if container.nil?

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

      # An invited person is not found, so mentioning one is the same refusal.
      users = User.can_sign_in.where(id: user_ids).to_a
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
