module Admin
  # A page, post or library image found THROUGH THE READ SCOPE for a request
  # that is about it (notes, presence): the record of a kind (`RecordKinds`)
  # the viewer may read, or no such record. Rights that are per record make
  # every nil a 404 (a record outside the scope is not found, never
  # forbidden). A kind whose right opens every record (the library:
  # `media.upload`) is a 403 for someone without it, as
  # `Admin::MediaController`'s gate is; that says nothing of any one record
  # (`RecordKinds::Kind#scoped`).
  module RecordOfKind
    private

    # The record, or nil after the 403 has been rendered (the caller's action
    # or before_action then ends, as a render ends one); raises
    # `ActiveRecord::RecordNotFound` (a 404) for an unknown kind and for every
    # other nil.
    def record_of_kind(name, id)
      kind = RecordKinds.named(name) or raise ActiveRecord::RecordNotFound
      if !kind.scoped && !can?(kind.read)
        forbidden!
        return
      end

      kind.find(Current.actor, id, channel: Current.channel) or raise ActiveRecord::RecordNotFound
    end
  end
end
