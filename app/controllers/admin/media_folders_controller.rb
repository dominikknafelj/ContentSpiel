module Admin
  # The Folders column's writes (media-folders spec §8): create, rename or move,
  # and delete a folder, each through its service (`Media::SaveFolder`,
  # `Media::DeleteFolder`), answered as Turbo Streams (`Admin::Answers::Folder*`).
  #
  # `media.manage` gates every action BEFORE any folder is looked up, so an id
  # that names nothing and one that exists answer alike ("not found, not
  # forbidden" would otherwise tell a person without the right which ids
  # exist). A folder that is gone by then (deleted in another tab) is no 404
  # page, which a Turbo Stream request draws nothing for: it is refused with
  # "That folder is gone." as the service's own race is, under the dialog's
  # field for a rename and as an error toast for a delete or a move
  # (`#gone`). `place` is the place the screen was showing (the `folder` words of
  # the listing), which the answer keeps or leaves.
  #
  # A move sent by the Move to… dialog (`dialog=move`, no name) is refused
  # in the dialog instead: its list drawn again with the sentences on top
  # (`Admin::Answers::MoveRefused`); a folder gone by then has no list.
  #
  # `index` is the column's part as it stands now, for a tab that heard that
  # another changed the library (`admin--media--live`, the card's D13): read
  # with the screen's own gate, `media.upload`, and the screen's words
  # (`folder`, `q`, `filter`; `picker` for the picker's places).
  #
  # `images` is a folder's own kept images as JSON, for the picker's "Add
  # all … new images in this folder" (gallery spec §10.6): behind the
  # picker's gate, `media.upload`, asked before the folder is looked up, so
  # someone without it learns nothing of which ids exist; a folder the tree
  # does not hold is then a 404.
  class MediaFoldersController < BaseController
    include MediaPlaces

    before_action -> { require_permission("media.upload") }, only: %i[index images]
    before_action -> { forbidden! unless can?("media.manage") }, except: %i[index images]
    before_action :set_folder, only: %i[update destroy]

    # The services' sentence for a folder deleted meanwhile (`Media::SaveFolder`,
    # `Media::DeleteFolder`), said here for one already gone at the lookup.
    GONE = "That folder is gone.".freeze

    # The part for the place `folder` names, its digest on it; a folder that
    # is gone is All media, and the part says so (`data-media-place-gone`).
    def index
      tree = Media::FolderTree.load
      place = Media::Place.parse(params[:folder], tree: tree)
      gone = place.nil?
      place ||= Media::Place::ALL
      return render(folder_column_for(place, gone: gone), layout: false) unless params[:picker].present?

      render Admin::MediaLibrary::FolderTreeComponent.new(tree: tree, counts: Media::FolderCounts.call, place: place, query: shown_query,
        open_set: TreeOpenSet::EMPTY, manage: false, mode: :picker, digest: place.digest(tree), gone: gone), layout: false
    end

    # `total` counts the folder's kept images with a file (never a
    # subfolder's) whose ids `except` does not name; `items` are the oldest
    # `limit` of them by id, upload order, each with the keys a picker tile
    # hands back, in the admin language. `limit` and `except` never pass a gallery's size.
    def images
      place = Media::Place.parse(params[:id].to_s, tree: Media::FolderTree.load)
      raise ActiveRecord::RecordNotFound unless place&.folder

      # One scope for both, so "Add all N" never counts an image it would not
      # add: one with no file is no picker tile and no gallery item.
      scope = place.narrow(Media::Asset.kept.joins(:file_attachment)).where.not(id: excepted_ids)
      items = scope.with_file.order(:id).limit(images_limit).map { |asset| picked_keys(asset) }
      render json: { total: scope.count, items: items }
    end

    def create
      result = Media::SaveFolder.call(attributes: folder_attributes)
      return saved(result, created: true) if result.ok?

      refused(result)
    end

    def update
      result = Media::SaveFolder.call(@folder, attributes: folder_attributes)
      return saved(result, created: false, moved: !sent_name? && folder_attributes.key?(:parent_id)) if result.ok?

      refused(result)
    end

    def destroy
      result = Media::DeleteFolder.call(@folder)
      return refused_without_form(result) unless result.ok?

      parent = result.record.parent_id && Media::Folder.find_by(id: result.record.parent_id)
      answer(Admin::Answers::FolderDeleted.new(view: view_context, url: place_url, column: method(:folder_column_for)).answer(parent: parent))
    end

    private

    def set_folder
      @folder = Media::Folder.find_by(id: params[:id])
      gone unless @folder
    end

    # A rename draws its form again, the sentence under the field and the
    # address it was sent to; a delete or a move says it in a toast.
    def gone
      refusal = Admin::Answers::FolderRefused.new(view: view_context)
      return refused_in_move_dialog(Media::Folder.new(id: 0), [ GONE ], :not_found) if action_name == "update" && from_move_dialog?
      return answer(refusal.toast(sentences: [ GONE ], status: :not_found)) unless action_name == "update" && sent_name?

      form = Admin::MediaLibrary::FolderFormComponent.new(
        tree: Media::FolderTree.load, folder: Media::Folder.new(id: params[:id].to_i), name: sent_folder[:name].to_s,
        errors: { base: [ GONE ] }, place: params[:place].to_s, query: shown_query
      )
      answer(refusal.answer(form: form, status: :not_found))
    end

    # Only the keys that were sent: a rename sends no parent and a move no name.
    # A parent that is no number names a folder that is gone (id 0), as an
    # upload's does.
    def folder_attributes
      sent = sent_folder.permit(:name, :parent_id)
      attributes = sent.to_h.symbolize_keys
      attributes[:parent_id] = (Integer(attributes[:parent_id].to_s, 10, exception: false) || 0) if attributes[:parent_id].present?
      attributes[:parent_id] = nil if attributes.key?(:parent_id) && attributes[:parent_id].blank?
      attributes
    end

    def saved(result, created:, moved: false)
      place = shown_place(Media::FolderTree.load)
      answer(Admin::Answers::FolderSaved.new(view: view_context, url: place_url, column: method(:folder_column_for)).answer(folder: result.record, place: place, created: created, moved: moved))
    end

    # A create or a rename (a name was sent) draws the dialog's form again,
    # as it was sent; a move answers with its sentences alone.
    def refused(result)
      return refused_without_form(result) unless sent_name?

      errors = result.record.respond_to?(:errors) && result.record.errors.any? ? result.record.errors.messages : { base: result.errors }
      form = Admin::MediaLibrary::FolderFormComponent.new(
        tree: Media::FolderTree.load, folder: @folder, parent_id: (folder_attributes[:parent_id] unless @folder),
        name: sent_folder[:name].to_s, errors: errors, place: params[:place].to_s, query: shown_query
      )
      answer(Admin::Answers::FolderRefused.new(view: view_context).answer(form: form, status: Admin::RefusalStatus.for(result)))
    end

    def refused_without_form(result)
      sentences = result.record.respond_to?(:errors) && result.record.errors.any? ? result.record.errors.map(&:message) : result.errors
      return refused_in_move_dialog(@folder, sentences, Admin::RefusalStatus.for(result)) if action_name == "update" && from_move_dialog?

      answer(Admin::Answers::FolderRefused.new(view: view_context).toast(sentences: sentences, status: Admin::RefusalStatus.for(result)))
    end

    def refused_in_move_dialog(folder, sentences, status)
      answer(Admin::Answers::MoveRefused.new(view: view_context).answer(choices: move_choices_for({ kind: :folder, folder: folder }, refusal: sentences), status: status))
    end

    # `limit` as a whole number up to a gallery's size; absent or anything
    # else, the gallery's size.
    def images_limit
      limit = Integer(params[:limit].to_s, 10, exception: false)
      limit ? limit.clamp(0, BlockTypes::Gallery::MAX_IMAGES) : BlockTypes::Gallery::MAX_IMAGES
    end

    # `except`, comma-separated ids: what is not a whole number is dropped,
    # and no more than a gallery holds are read. Anything but a String
    # (`except[]=1`) names none.
    def excepted_ids
      sent = params[:except]
      return [] unless sent.is_a?(String)

      sent.split(",").grep(/\A\d{1,18}\z/).map(&:to_i).uniq.first(BlockTypes::Gallery::MAX_IMAGES)
    end

    # What a picker tile hands back (`Admin::MediaLibrary::TileComponent#pick_payload`'s
    # keys a gallery reads), the library's alt and caption in the admin
    # language.
    def picked_keys(asset)
      { id: asset.id, url: asset.thumbnail_url, title: asset.title,
        alt: asset.alt_text(override: nil, locale: admin_locale).to_s, caption: asset.caption_text(override: nil, locale: admin_locale).to_s }
    end

    def sent_name? = sent_folder.key?(:name)

    # `media_folder` as a form sends it; anything else (a forged plain
    # string) is an empty form.
    def sent_folder
      sent = params[:media_folder]
      sent.is_a?(ActionController::Parameters) ? sent : ActionController::Parameters.new
    end

    def place_url = ->(place) { admin_media_path(**place_query(place)) }

    def answer(answer) = render(turbo_stream: answer.streams, status: answer.status)
  end
end
