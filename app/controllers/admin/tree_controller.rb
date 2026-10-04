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
    include AutosaveResponses

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
      # Where the page stands *now*, read before the service runs: an Undo
      # is just this same move with these values (see `undo_toast`).
      before = placement(page)
      result = Pages::Move.call(page, parent: parent, position: params[:position])

      status = if result.ok? then :ok
      elsif result.denied? then :forbidden
      else :unprocessable_entity
      end
      message = result.ok? ? nil : result.errors.to_sentence
      streams = tree_stream(selected: page, message: message)
      streams.concat(Array(move_toast(page, before))) if result.ok?
      render turbo_stream: streams, status: status
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

    # A page's place in the tree as `Pages::Move` takes it: its parent and its
    # *rank* among that parent's kept siblings (`Page::TreeRanking` -- the same
    # ranking the service writes, which is not the stored `position` number
    # and counts siblings this actor may not see). Putting a page back with
    # these two values is exactly "move to rank N" again, so an Undo is as
    # faithful as the move was, with no inverse operation of its own.
    def placement(page)
      siblings = Page.kept.where(parent_id: page.parent_id).order(:position, :id).pluck(:id)
      [ page.parent_id, siblings.index(page.id) ]
    end

    # The toast after a successful move: an Undo that PATCHes this same
    # endpoint with the previous place (`button_to` with `method: :patch`, so
    # the existing route and `Pages::Move`'s ordinary permission checks serve
    # it -- no route of its own). `undo=1` marks the answer to an Undo, which
    # is confirmed plainly with no Undo of its own (two moves bouncing the
    # page back and forth would never end). A drop that left the page exactly
    # where it was is no move worth undoing: no toast at all.
    def move_toast(page, before)
      after = placement(page.reload)
      title = ::Locales.read(page, :title, locale: admin_locale).presence || "(untitled)"
      return toast_stream("Move undone.") if params[:undo].present?
      return [] if after == before

      parent_id, position = before
      toast_stream("Moved “#{title}”.", kind: :undo, action: {
        label: "Undo", method: :patch,
        url: admin_tree_path(page_id: page.id, parent_id: parent_id, position: position, undo: 1, **admin_url_options)
      })
    end

    def tree_stream(selected:, message: nil)
      [
        turbo_stream.replace("tree", Admin::TreeComponent.new(root: root_page, selected: selected, locale: admin_locale, url_options: admin_url_options)),
        turbo_stream.replace("tree-status", partial: "admin/tree/status", locals: { message: message })
      ]
    end
  end
end
