module Media
  # Moves library images into a folder, or out of every folder (`folder` nil),
  # and is the one writer of `media_assets.folder_id` after an upload
  # (docs/reference/media.md). `Media::Save`, the panel's autosave, takes no
  # folder.
  #
  # RIGHTS, all or nothing: each image needs its edit right as `Media::Save`
  # judges it (`media.manage`, or the image's own uploader holding
  # `media.upload`, `Media::Ownership`). One image the actor may not move
  # refuses the whole move, said by how many, and the denial is recorded once.
  #
  # AT MOST `MAX` IDS, refused before anything is read. A trashed or missing
  # id is refused as missing, nothing moves.
  #
  # THE ORDER inside the transaction: the target folder's row FOR KEY SHARE, then
  # the images' rows FOR UPDATE by id. `Media::DeleteFolder` takes the folder's
  # row FOR UPDATE before it touches an image, so a delete waits for a move
  # that came first (its images go up with the rest) and a move that comes
  # after finds the folder gone and moves nothing; no image falls to "Not in a
  # folder" through the foreign key's nullify.
  #
  # The order is shared with `Media::DeleteFolder`: folder rows first, then
  # image rows by id, so two writers never take the same rows crosswise.
  #
  # FOR KEY SHARE and not FOR SHARE: it still blocks that FOR UPDATE and the
  # row's DELETE, which is all the rule needs, but not the re-parenting of the
  # folder. Deleting the target's PARENT re-parents the target (`update_all`
  # takes FOR NO KEY UPDATE on it, which FOR SHARE would block) after it has
  # updated that parent's images, the very ones a move may be holding: the
  # move would wait for the delete's image locks and the delete for the move's
  # folder lock, a deadlock answered as a 500.
  #
  # The write is one `update_all(folder_id:)`: it touches no `updated_at` and
  # no content version. An open panel's autosave base is the image's
  # `updated_at`, and a move is no edit of the image's text, so a move must
  # never make that save stale. An image already in the target is left out and
  # recorded nowhere. Each image that moved gets its own `media.moved`, never
  # coalesced, so the log keeps where every image went.
  class MoveImages < ApplicationService
    include Ownership

    MAX = 200

    # `record` is nil; `moved` is the images that changed folder.
    Result = Data.define(:record, :errors, :denied, :notice, :refusal, :moved) do
      def ok? = errors.empty?

      def denied? = denied
    end

    def initialize(asset_ids:, folder:, actor: Current.actor)
      @asset_ids = Array(asset_ids)
      @folder = folder
      @actor = actor
    end

    def call
      return answer(failure(nil, [ "Move at most #{MAX} images at once." ])) if @asset_ids.size > MAX

      ids = @asset_ids.map { |id| Integer(id.to_s, 10, exception: false) }.uniq
      found = Media::Asset.kept.where(id: ids.compact).to_a
      refused = found.reject { |asset| may_move?(asset) }
      return answer(not_yours(refused)) if refused.any?
      return answer(failure(nil, [ "An image you chose is gone. Nothing was moved." ])) if found.size != ids.size

      moved = nil
      outcome = Media::Asset.transaction do
        target = @folder && Media::Folder.lock("FOR KEY SHARE").find_by(id: @folder.id)
        next failure(nil, [ "That folder is gone." ]) if @folder && target.nil?

        locked = Media::Asset.kept.where(id: ids).order(:id).lock("FOR UPDATE").to_a
        next failure(nil, [ "An image you chose is gone. Nothing was moved." ]) if locked.size != ids.size

        moved = move(locked, target)
        Media::LibrarySignals.changed(reason: "moved") if moved.any?
        success(nil)
      end

      answer(outcome, moved || [])
    end

    private

    def may_move?(asset) = authorize!("media.manage", asset) || uploader_may_manage?(asset)

    # One denial, on the first image refused, with the count in the sentence.
    def not_yours(refused)
      sentence = refused.size == 1 ? "1 of these images is not yours to move." : "#{refused.size} of these images are not yours to move."
      denied("media.manage", refused.first, message: "#{sentence} Nothing was moved.")
    end

    def move(locked, target)
      was = locked.to_h { |asset| [ asset.id, asset.folder_id ] }
      changing = locked.reject { |asset| asset.folder_id == target&.id }
      return [] if changing.empty?

      Media::Asset.where(id: changing.map(&:id)).update_all(folder_id: target&.id) # version: none (a folder is never drawn on the site)
      Media::Asset.where(id: changing.map(&:id)).order(:id).to_a.each do |asset|
        record_event("media.moved", subject: asset, field_changes: { "folder_id" => [ was.fetch(asset.id), asset.folder_id ] },
          metadata: { "folder_name" => target&.name }, coalesce: false)
      end
    end

    def answer(result, moved = [])
      Result.new(**result.to_h, moved: moved)
    end
  end
end
