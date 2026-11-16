module Media
  # Deletes a library folder (docs/reference/media.md): its images and its
  # subfolders move one level up, into its parent, or to the top (no folder)
  # when it had none; then the row goes. Never refused for what it holds.
  #
  # Needs `media.manage`, as every write to the tree does.
  #
  # THE ORDER inside the transaction: the tree's lock (`Media::Folder.lock_tree!`),
  # then the folder's own row FOR UPDATE, then the images, the subfolders and
  # the row. A move or upload into the folder holds its row FOR KEY SHARE, so one
  # waits for the other: a move that commits first has its images moved up with
  # the rest, one that comes after finds the folder gone. Without the row lock
  # first, an image moved in between this delete's update and its delete would
  # fall to "Not in a folder" by the foreign key's nullify instead of the
  # parent.
  #
  # THE SHARED LOCK ORDER with `Media::MoveImages`: folder rows first, then
  # image rows by id. The images are locked in one ordered statement and
  # updated by the ids that statement returned; an unordered `update_all` would
  # take the same rows in scan order and could deadlock with a move holding
  # some of them.
  #
  # The update is over every image with the folder's id, kept or trashed, so a
  # trashed image restored later comes back to the parent. It touches no
  # `updated_at` and no content version: a folder is never drawn on the site.
  #
  # A subfolder whose name the parent already holds (case ignored, the unique
  # index's rule) takes the first free " 2", " 3", ..., recorded as its own
  # `media_folder.renamed`. One `media_folder.deleted` is recorded on the
  # folder before the row goes, its metadata the parent, the count of moved
  # images (their ids only for IDS_KEPT or fewer) and the moved folders'
  # ids; no event per image.
  class DeleteFolder < ApplicationService
    IDS_KEPT = 200

    # What the confirm dialog says before the press: `renames` maps a
    # subfolder's id to the name it will take, `target` is the folder
    # everything moves into (nil: the top).
    Preview = Data.define(:image_count, :folder_count, :renames, :target)

    def self.preview(folder, tree: Media::FolderTree.load)
      Preview.new(
        image_count: Media::Asset.kept.where(folder_id: folder.id).count,
        folder_count: tree.children(folder.id).size,
        renames: renames(folder, tree),
        target: folder.parent_id && Media::Folder.find_by(id: folder.parent_id)
      )
    end

    # A subfolder keeps its name unless a folder already in the parent holds
    # it; those that keep theirs are counted as taken first, so a suffixed
    # name never lands on one of them.
    def self.renames(folder, tree)
      siblings = (folder.parent_id ? tree.children(folder.parent_id) : tree.roots).reject { |node| node.id == folder.id }
      taken = siblings.to_set { |node| node.name.downcase }
      moving = tree.children(folder.id)
      clashing, keeping = moving.partition { |node| taken.include?(node.name.downcase) }
      taken.merge(keeping.map { |node| node.name.downcase })
      clashing.to_h do |node|
        name = free_name(node.name, taken)
        taken << name.downcase
        [ node.id, name ]
      end
    end

    def self.free_name(name, taken)
      (2..).each do |number|
        suffix = " #{number}"
        candidate = "#{name.first(Media::Folder::NAME_LENGTH - suffix.length).rstrip}#{suffix}"
        return candidate unless taken.include?(candidate.downcase)
      end
    end

    def initialize(folder, actor: Current.actor)
      @folder = folder
      @actor = actor
    end

    def call
      return denied("media.manage", @folder) unless authorize!("media.manage", @folder)

      deleted = Media::Folder.transaction do
        Media::Folder.lock_tree!
        locked = Media::Folder.lock("FOR UPDATE").find_by(id: @folder.id)
        next false unless locked

        @folder = locked
        move_up(Media::FolderTree.load)
        Media::LibrarySignals.changed(reason: "folders")
        true
      end

      deleted ? success(@folder) : failure(@folder, [ "That folder is gone." ])
    end

    private

    def move_up(tree)
      parent_id = @folder.parent_id
      renames = self.class.renames(@folder, tree)
      rename(renames)

      image_ids = Media::Asset.where(folder_id: @folder.id).order(:id).lock("FOR UPDATE").pluck(:id)
      Media::Asset.where(id: image_ids).update_all(folder_id: parent_id) # version: none (a folder is never drawn on the site)
      folder_ids = tree.children(@folder.id).map(&:id)
      Media::Folder.where(parent_id: @folder.id).update_all(parent_id: parent_id) # version: none (a folder is never drawn on the site)

      metadata = { "parent_id" => parent_id, "moved_image_count" => image_ids.size, "moved_folder_ids" => folder_ids }
      metadata["moved_image_ids"] = image_ids if image_ids.size <= IDS_KEPT
      record_event("media_folder.deleted", subject: @folder, metadata: metadata, coalesce: false)
      @folder.destroy!
    end

    # Renamed before the move, while the subfolder is still under this folder,
    # where no sibling can hold the new name.
    def rename(renames)
      renames.each do |id, name|
        child = Media::Folder.find(id)
        was = child.name
        child.update!(name: name)
        record_event("media_folder.renamed", subject: child, field_changes: { "name" => [ was, child.name ] }, coalesce: false)
      end
    end
  end
end
