module Admin
  # Moves library images into a folder or out of every folder
  # (`Media::MoveImages`, all or nothing; `asset_ids[]`, and `folder` the
  # target: `none` or a folder's id). `place` is the place the screen was
  # showing, which tells the answer what to take off the screen.
  #
  # Gated like the panel's writes, before any image or folder is read: a right
  # that could ever let a move through (`media.manage`, or `media.upload` for
  # one's own images). Which images are the actor's is the service's answer.
  class MediaMovesController < BaseController
    include MediaPlaces

    before_action -> { forbidden! unless holds_any?(%w[media.upload media.manage]) }

    GONE = "That folder is gone.".freeze

    def create
      tree = Media::FolderTree.load
      target = Media::Place.parse(params[:folder], tree: tree)
      return refuse([ GONE ], :unprocessable_entity) if target.nil? || target.all?

      folder = target.none? ? nil : Media::Folder.find_by(id: target.folder)
      return refuse([ GONE ], :unprocessable_entity) if folder.nil? && !target.none?

      result = Media::MoveImages.call(asset_ids: asset_ids, folder: folder)
      return refuse(result.errors, Admin::RefusalStatus.for(result)) unless result.ok?

      place = shown_place(tree)
      counts = Media::Search.new(q: params[:q], place: place, actor: Current.actor).counts
      render_answer(Admin::Answers::ImagesMoved.new(view: view_context).answer(assets: result.moved, folder: folder, place: place, counts: counts, column: method(:folder_column_for)))
    end

    private

    # Strings only: `asset_ids[a]=1` or a nested value names nothing.
    def asset_ids
      raw = params[:asset_ids]
      raw.is_a?(Array) ? raw.select { |id| id.is_a?(String) } : []
    end

    def refuse(errors, status)
      render_answer(Admin::Answers::ImagesMoved.new(view: view_context).refused(errors: errors, status: status))
    end

    def render_answer(answer) = render(turbo_stream: answer.streams, status: answer.status)
  end
end
