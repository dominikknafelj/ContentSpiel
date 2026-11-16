module Admin
  # What the Media screen's three controllers (`MediaController`,
  # `MediaFoldersController`, `MediaMovesController`) share about places.
  module MediaPlaces
    extend ActiveSupport::Concern

    included do
      # The one builder of a link to a place (the Folders column's rows, the
      # breadcrumb, the picker's places, a write's answer): `q` and `filter`
      # kept, `folder` the place's own (nothing for All media), the language,
      # and never `page` (page 3 of one folder is no page of another),
      # `selected` or `select`.
      helper_method :place_query
    end

    private

    # `request.parameters`, not the query string alone: a write's `q` and
    # `filter` ride in its body, and for the listing the two are the same.
    def place_query(place)
      query = shown_query
      query[:folder] = place.to_param unless place.all?
      query.merge(admin_url_options.slice(:locale))
    end

    # The search and the segment the screen shows (`q`, `filter`, Strings
    # only, an empty one left out: a folder dialog sends both, empty when no
    # search is typed), which every link to a place keeps: the Folders
    # column's `query:`.
    def shown_query
      request.parameters.slice("q", "filter").select { |_, value| value.is_a?(String) && value.present? }.symbolize_keys
    end

    # The Folders column as it stands after a write, `place` selected and
    # `go_to` the address the screen goes to next (`data-media-go`): the
    # answers' part (`Admin::Answers::FolderTreePart`), and the part a tab
    # fetches again (`Admin::MediaFoldersController#index`, `gone`: the
    # folder asked for is gone). It carries the place's digest.
    def folder_column_for(place, go_to: nil, gone: false)
      tree = Media::FolderTree.load
      Admin::MediaLibrary::FolderTreeComponent.new(
        tree: tree, counts: Media::FolderCounts.call, place: place, query: shown_query,
        open_set: TreeOpenSet.parse(cookies[TreeOpenSet::MEDIA_COOKIE], readable_ids: tree.ids),
        manage: can?("media.manage"), go_to: go_to, digest: place.digest(tree), gone: gone
      )
    end

    # The Move to… dialog's list for `subject` (`{ kind: :images, ids: }` or
    # `{ kind: :folder, folder: }`), from the tree as it is now. Its current
    # place is the folder's parent (the top: `Media::Place::NONE`), or the
    # one place every image stands in (none when they stand in several).
    # `refusal` is the sentences of a move it sent that was refused.
    def move_choices_for(subject, refusal: nil)
      tree = Media::FolderTree.load
      Admin::MediaLibrary::MoveChoicesComponent.new(
        tree: tree, subject: subject, current: current_place_of(subject, tree), refusal: refusal,
        place: params[:place].is_a?(String) ? params[:place] : "", query: shown_query, url_options: admin_url_options
      )
    end

    # A move sent by the Move to… dialog, whose refusal draws its list again.
    def from_move_dialog? = params[:dialog] == Admin::MediaLibrary::MoveChoicesComponent::DIALOG

    # An image's Folder fact after a move, for a mover (who may move it).
    def folder_fact_for(asset, tree)
      Admin::MediaLibrary::FolderFactComponent.new(asset: asset, tree: tree, movable: true, query: shown_query, url_options: admin_url_options)
    end

    # The place the screen was showing when a write was sent (`place`, the
    # same words as `folder`), All media when it is absent or names no folder
    # (a folder deleted meanwhile).
    def shown_place(tree)
      Media::Place.parse(params[:place], tree: tree) || Media::Place::ALL
    end

    def current_place_of(subject, tree)
      if subject.fetch(:kind) == :folder
        node = tree.find(subject.fetch(:folder).id)
        return nil unless node

        return node.parent_id ? Media::Place.new(:folder, node.parent_id) : Media::Place::NONE
      end

      folders = Media::Asset.kept.where(id: subject.fetch(:ids)).distinct.pluck(:folder_id)
      return nil unless folders.size == 1

      folders.first ? Media::Place.new(:folder, folders.first) : Media::Place::NONE
    end
  end
end
