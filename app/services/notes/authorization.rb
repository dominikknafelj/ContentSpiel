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

    def body_errors(body)
      return [ I18n.t("admin.notes.errors.blank") ] if body.blank?
      return [ I18n.t("admin.notes.errors.too_long") ] if body.length > Message::MAX_BODY

      []
    end

    # A mention is addressed to a person: it must name a user who exists and
    # who may read the record, or the inbox would show them a title and a
    # quote they are not allowed to see. Judged as that user would be judged
    # in CS Studio (`:admin`), whatever channel this call runs on.
    def mention_errors(user_ids, container)
      return [] if user_ids.empty?

      users = User.where(id: user_ids).index_by(&:id)
      user_ids.filter_map do |id|
        user = users[id]
        if user.nil?
          I18n.t("admin.notes.errors.mention_unknown")
        elsif !Notes.readable?(user, container, channel: :admin)
          I18n.t("admin.notes.errors.mention_cannot_read.#{kind_of(container)}", name: user.display_name)
        end
      end.uniq
    end

    def lock_container(container) = container.class.kept.where(id: container.id).lock.pick(:id)

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
