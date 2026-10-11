module Admin
  # The page tree's own move endpoint (cs-studio spec §4.2): dragging a node
  # PATCHes here with the moved page, its new parent and its new rank among
  # that parent's other children, and the response is always a fresh render
  # of the whole tree from the database -- success or failure alike, since a
  # single move can renumber siblings the dragged node never touched
  # (`Page::TreeRanking`), so nothing short of a real re-render is
  # trustworthy afterward. See `app/javascript/controllers/admin/
  # tree_controller.js` for the client side this answers.
  #
  # A move is a write to the moved page (`Pages::Move` saves it, so its
  # `updated_at` moves), made from OUTSIDE that page's editor forms -- and the
  # page settings form of that very page may be open next to the tree,
  # holding the old `settings_changed_at` as its autosave base. See
  # `#page_base_streams` for how the answer keeps that form able to save.
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
      # Before the write touches it -- see `#page_base_streams`.
      settings_base_before_move = page.settings_changed_at
      result = Pages::Move.call(page, parent: parent, position: params[:position])

      status = if result.ok? then :ok
      elsif result.denied? then :forbidden
      else :unprocessable_entity
      end
      message = result.ok? ? nil : result.errors.to_sentence
      streams = tree_stream(selected: page, message: message)
      if result.ok?
        streams.concat(Array(move_toast(page, before)))
        streams.concat(page_base_streams(page, settings_base_before_move))
      end
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

    # The page settings form's new base, when the form that is open is the
    # MOVED page's and was current (final fix wave 1, reviews A I1 / B I1).
    #
    # Since a stale autosave base is refused (`Admin::AutosaveResponses
    # #refuse_stale_autosave`), a move of the page one has open -- which is
    # what the New page dialog tells an editor to do ("Drag it in the tree to
    # move it") -- locked that page's own form: its next save was a final
    # 409, "Changed elsewhere" against the editor's own move, the typed text
    # not saved. So this answers with the form's new base:
    # `admin--pages--tree` sends the open form's base as
    # `X-Page-Base-Updated-At`, through the same queue as every other write on
    # the screen, and the form's base is moved forward to the page's new
    # `settings_changed_at`. This one stays, unlike the block side's (a block
    # write no longer moves the settings base at all): `Pages::Move` saves the
    # page's own columns, so the move DOES move `settings_changed_at`.
    #
    # Only when the sent base EQUALS the moved page's `settings_changed_at` as loaded
    # for this request. That one test says both things that have to hold:
    # - the open form is this page's. The client only sends the header when
    #   it is, but the tree lists every page, and handing a form another
    #   page's (newer) `updated_at` as its base would let a stale form pass
    #   the staleness check and overwrite someone else's save. Hence `==`
    #   here;
    # - nobody saved the page since the form loaded it. If someone did, the
    #   base is left alone and the form's next save is still, rightly,
    #   refused.
    # No header (the moved page is not the open one, or an older client) or
    # an unparseable one: nothing to vouch for.
    def page_base_streams(page, settings_base_before_move)
      sent = request.headers["X-Page-Base-Updated-At"]
      return [] unless sent.present? && Time.iso8601(sent) == settings_base_before_move

      id = "#{Admin::EditorScreen::PageSettingsFormComponent::ID_PREFIX}-base-updated-at"
      [ turbo_stream.replace(id, partial: "admin/shared/base_updated_at_field",
        locals: { id: id, value: Page.where(id: page.id).pick(:settings_changed_at).iso8601(6) }) ]
    rescue ArgumentError
      []
    end

    def tree_stream(selected:, message: nil)
      [
        turbo_stream.replace("tree", Admin::PagesScreen::TreeComponent.new(root: root_page, selected: selected, locale: admin_locale, url_options: admin_url_options)),
        turbo_stream.replace("tree-status", partial: "admin/tree/status", locals: { message: message })
      ]
    end
  end
end
