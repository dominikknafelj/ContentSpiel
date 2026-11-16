module Media
  # Creates, renames or moves a library folder (docs/reference/media.md). With
  # no folder it creates one; with one, the keys of `attributes` that are
  # present change: `name` renames it, `parent_id` moves it (nil is the top).
  #
  # Needs `media.manage`: a folder is shared by every image, so there is no
  # per-record scope to check (`media.upload` alone may put images in a folder,
  # never shape the tree).
  #
  # THE TREE'S LOCK FIRST (`Media::Folder.lock_tree!`), then one read of the
  # whole tree (`Media::FolderTree`): the depth, the count and the one name per
  # parent in any case are judged from that read, which no other writer can
  # change before this transaction ends. The unique index is the same rule
  # kept by the database; it can only fire for a writer that skipped the lock,
  # and answers as the name's failure all the same.
  #
  # A refusal is a failure on `:name` or `:parent_id` of the record, and its
  # `errors` are those sentences as they stand. A rename and a move are each
  # their own event, never coalesced: the log keeps every name a folder had.
  class SaveFolder < ApplicationService
    NAME_INDEX = "index_media_folders_on_parent_and_name".freeze

    def initialize(folder = nil, attributes:, actor: Current.actor)
      @folder = folder || Media::Folder.new
      @attributes = attributes.to_h.symbolize_keys
      @actor = actor
    end

    def call
      return denied("media.manage", @folder) unless authorize!("media.manage", @folder)

      saved = Media::Folder.transaction do
        Media::Folder.lock_tree!
        @tree = Media::FolderTree.load
        write || raise(ActiveRecord::Rollback)
      end

      saved ? success(@folder) : refusal
    rescue ActiveRecord::RecordNotUnique => error
      raise unless error.message.include?(NAME_INDEX)

      @folder.errors.add(:name, taken_sentence)
      refusal
    end

    private

    # Judged and written under the lock; false leaves the errors on the folder.
    def write
      return gone(:base) unless fresh_from_the_table

      was_name, was_parent_id = @folder.name, @folder.parent_id
      @folder.name = @attributes[:name] if @attributes.key?(:name)
      @folder.parent_id = @attributes[:parent_id] if @attributes.key?(:parent_id)
      return false unless @folder.valid? && parent_there? && not_inside_itself? && shallow_enough? && room_left? && name_free?

      new_record = @folder.new_record?
      @folder.save!
      record_changes(new_record, was_name, was_parent_id)
      true
    end

    # The row as the lock sees it; a folder deleted meanwhile is gone, not an
    # error page.
    def fresh_from_the_table
      return true if @folder.new_record?

      @folder.reload
      true
    rescue ActiveRecord::RecordNotFound
      false
    end

    def parent_there?
      return true if @folder.parent_id.nil? || @tree.find(@folder.parent_id)

      gone(:parent_id)
    end

    def not_inside_itself?
      return true unless @folder.persisted? && @folder.parent_id && @tree.inside?(@folder.parent_id, of: @folder.id)

      @folder.errors.add(:parent_id, "A folder can't go inside itself.")
      false
    end

    # The deepest folder of the moved subtree, below the new parent, may sit at
    # MAX_DEPTH and no lower.
    def shallow_enough?
      above = @folder.parent_id ? @tree.depth(@folder.parent_id) : 0
      below = @folder.persisted? ? @tree.height(@folder.id) : 1
      return true if above + below <= Media::Folder::MAX_DEPTH

      @folder.errors.add(:parent_id, "That would nest folders more than #{Media::Folder::MAX_DEPTH} levels deep.")
      false
    end

    def room_left?
      return true unless @folder.new_record? && @tree.size >= Media::Folder::MAX_FOLDERS

      @folder.errors.add(:name, "A site holds at most 1,000 folders.")
      false
    end

    def name_free?
      return true unless name_taken?

      @folder.errors.add(:name, taken_sentence)
      false
    end

    # A sibling of the same name, case ignored: "Trips" and "trips" are one.
    def name_taken?
      siblings = @folder.parent_id ? @tree.children(@folder.parent_id) : @tree.roots
      siblings.any? { |node| node.id != @folder.id && node.name.downcase == @folder.name.downcase }
    end

    def taken_sentence = "A folder named “#{@folder.name}” is already here."

    def gone(field)
      @folder.errors.add(field, "That folder is gone.")
      false
    end

    def record_changes(new_record, was_name, was_parent_id)
      if new_record
        record_event("media_folder.created", subject: @folder, coalesce: false)
        return
      end

      changes = Audit::Snapshot.field_changes_for(@folder)
      record_event("media_folder.renamed", subject: @folder, field_changes: changes.slice("name"), coalesce: false) if @folder.name != was_name
      return if @folder.parent_id == was_parent_id

      # The parent's name is kept with the event: the sentence reads after the
      # parent is renamed or deleted.
      parent = @tree.find(@folder.parent_id)&.name
      record_event("media_folder.moved", subject: @folder, field_changes: changes.slice("parent_id"), metadata: { "parent" => parent }.compact, coalesce: false)
    end

    def refusal = failure(@folder, @folder.errors.map(&:message))
  end
end
