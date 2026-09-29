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
    #
    # Both pages are loaded through the read scope (access-control design
    # spec §3.3), so naming one the actor can't read lands in the same
    # "no longer exists" answer below as a deleted one -- a 404 that
    # discloses nothing. `Pages::Move` decides the move itself (`pages.move`
    # on the page, `pages.create` under the target); a refusal is a 403.
    def update
      pages = admin_scope(Page.all)
      page = pages.find(params[:page_id])
      parent = pages.find(params[:parent_id])
      result = Pages::Move.call(page, parent: parent, position: params[:position])

      status = if result.ok? then :ok
      elsif result.denied? then :forbidden
      else :unprocessable_entity
      end
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
        turbo_stream.replace("tree", Admin::TreeComponent.new(root: root_page, selected: selected, locale: admin_locale, url_options: admin_url_options)),
        turbo_stream.replace("tree-status", partial: "admin/tree/status", locals: { message: message })
      ]
    end
  end
end
