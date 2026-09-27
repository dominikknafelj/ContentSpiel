module Admin
  # The page tree's own move endpoint (cs-studio spec §4.2): dragging a node
  # PATCHes here with the moved page, its new parent and its new rank among
  # that parent's other children, and the response is always a fresh render
  # of the whole tree from the database -- success or failure alike, since a
  # single move can renumber siblings the dragged node never touched
  # (`Page::TreeRanking`), so nothing short of a real re-render is
  # trustworthy afterward. See `app/javascript/controllers/admin/
  # tree_controller.js` for the client side this answers.
  class TreeController < BaseController
    # A GET for the tree frame on its own -- most navigation gets the tree
    # for free via `content_for :tree` on whichever Pages view is showing,
    # but this exists too (routed `resource :tree, only: %i[show update]`)
    # for anything that wants to (re)fetch just this column, e.g. a
    # lazily-loaded `<turbo-frame src="...">` in a later task.
    def show
      render turbo_stream: tree_stream(selected: Page.find_by(id: params[:page_id]))
    end

    def update
      page = Page.find(params[:page_id])
      parent = Page.find(params[:parent_id])
      result = Pages::Move.call(page, parent: parent, position: params[:position])

      status = result.ok? ? :ok : :unprocessable_entity
      message = result.ok? ? nil : result.errors.to_sentence
      render turbo_stream: tree_stream(selected: page, message: message), status: status
    rescue ActiveRecord::RecordNotFound
      # The dragged page or its drop target was deleted elsewhere (another
      # tab, another editor) between SortableJS's optimistic DOM move and
      # this PATCH landing -- not a bug in the drag itself, just a stale
      # client. The tree as the database has it right now is still a
      # perfectly good answer; `selected: nil` since whichever id went
      # missing can no longer be looked up to highlight.
      render turbo_stream: tree_stream(selected: nil, message: "That page no longer exists — the tree was refreshed"),
        status: :not_found
    end

    private

    def tree_stream(selected:, message: nil)
      [
        turbo_stream.replace("tree", Admin::TreeComponent.new(root: Page.find_by(parent_id: nil), selected: selected, locale: admin_locale, url_options: admin_url_options)),
        turbo_stream.replace("tree-status", partial: "admin/tree/status", locals: { message: message })
      ]
    end
  end
end
