module Admin
  # The Folders column's writes (media-folders spec §8): create, rename or move,
  # and delete a folder, each through its service (`Media::SaveFolder`,
  # `Media::DeleteFolder`), answered as Turbo Streams (`Admin::Answers::Folder*`).
  #
  # `media.manage` gates every action BEFORE any folder is looked up, so an id
  # that names nothing and one that exists answer alike ("not found, not
  # forbidden" would otherwise tell a person without the right which ids
  # exist). `place` is the place the screen was showing (the `folder` words of
  # the listing), which the answer keeps or leaves.
  class MediaFoldersController < BaseController
    include MediaPlaces

    before_action -> { forbidden! unless can?("media.manage") }
    before_action :set_folder, only: %i[update destroy]

    def create
      result = Media::SaveFolder.call(attributes: folder_attributes)
      return saved(result, created: true) if result.ok?

      refused(result)
    end

    def update
      result = Media::SaveFolder.call(@folder, attributes: folder_attributes)
      return saved(result, created: false) if result.ok?

      refused(result)
    end

    def destroy
      result = Media::DeleteFolder.call(@folder)
      return refused_without_form(result) unless result.ok?

      parent = result.record.parent_id && Media::Folder.find_by(id: result.record.parent_id)
      answer(Admin::Answers::FolderDeleted.new(view: view_context, url: place_url, column: method(:folder_column_for)).answer(parent: parent))
    end

    private

    def set_folder = @folder = Media::Folder.find(params[:id])

    # Only the keys that were sent: a rename sends no parent and a move no name.
    # A parent that is no number names a folder that is gone (id 0), as an
    # upload's does.
    def folder_attributes
      sent = params.fetch(:media_folder, ActionController::Parameters.new).permit(:name, :parent_id)
      attributes = sent.to_h.symbolize_keys
      attributes[:parent_id] = (Integer(attributes[:parent_id].to_s, 10, exception: false) || 0) if attributes[:parent_id].present?
      attributes[:parent_id] = nil if attributes.key?(:parent_id) && attributes[:parent_id].blank?
      attributes
    end

    def saved(result, created:)
      place = shown_place(Media::FolderTree.load)
      answer(Admin::Answers::FolderSaved.new(view: view_context, url: place_url, column: method(:folder_column_for)).answer(folder: result.record, place: place, created: created))
    end

    # A create or a rename (a name was sent) draws the dialog's form again,
    # as it was sent; a move answers with its sentences alone.
    def refused(result)
      return refused_without_form(result) unless sent_name?

      errors = result.record.respond_to?(:errors) && result.record.errors.any? ? result.record.errors.messages : { base: result.errors }
      form = Admin::MediaLibrary::FolderFormComponent.new(
        tree: Media::FolderTree.load, folder: @folder, parent_id: (folder_attributes[:parent_id] unless @folder),
        name: params.dig(:media_folder, :name).to_s, errors: errors, place: params[:place].to_s, query: shown_query
      )
      answer(Admin::Answers::FolderRefused.new(view: view_context).answer(form: form, status: Admin::RefusalStatus.for(result)))
    end

    def refused_without_form(result)
      sentences = result.record.respond_to?(:errors) && result.record.errors.any? ? result.record.errors.map(&:message) : result.errors
      answer(Admin::Answers::FolderRefused.new(view: view_context).toast(sentences: sentences, status: Admin::RefusalStatus.for(result)))
    end

    def sent_name? = params[:media_folder].respond_to?(:key?) && params[:media_folder].key?(:name)

    def place_url = ->(place) { admin_media_path(**place_query(place)) }

    def answer(answer) = render(turbo_stream: answer.streams, status: answer.status)
  end
end
