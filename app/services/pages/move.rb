module Pages
  # Moves a page to rank `position` under `parent` (spec §7.2). The rank
  # semantics live in Page::TreeRanking; this adds the rules a UI must not be
  # able to break: the homepage stays the root, and a page can't become its
  # own ancestor.
  #
  # Permissions (access-control design spec §3.3 "Move page"): `pages.move`
  # on the page where it stands now, *and* `pages.create` on the target
  # parent's branch -- moving a page into a branch is putting a new page
  # there, as far as that branch is concerned, so an editor limited to one
  # branch can neither pull pages out of it nor push pages into another.
  # A reorder among the same siblings needs the same `pages.create` on the
  # current parent. Deliberately, that includes a branch root: an editor
  # whose grants are scoped to `page_ids: [root_of_branch]` can reorder
  # pages *inside* the branch, but not the branch root itself among its
  # siblings -- its parent lies outside the branch, and the siblings'
  # order is someone else's (the tree above the branch).
  class Move < ApplicationService
    def initialize(page, parent:, position:, actor: Current.actor)
      @page, @parent, @position, @actor = page, parent, position.to_i, actor
    end

    def call
      return denied("pages.move", @page) unless authorize!("pages.move", @page)
      return denied("pages.create", @page) unless may_create_under_target?
      return failure(@page, [ "The homepage can't be moved" ]) if @page.root?
      return failure(@page, [ "A page can't be moved under itself or one of its own subpages" ]) if @parent.self_and_ancestors.include?(@page)

      moved = Page.transaction do
        @page.parent = @parent
        @page.position = @position
        # Before saving: closure_tree's `after_save` reloads the page,
        # clearing `saved_changes` (see `Audit::Snapshot.field_changes_for`).
        pending = @page.changes_to_save
        @page.save || raise(ActiveRecord::Rollback)

        record_event("page.moved", subject: @page, field_changes: Audit::Snapshot.field_changes_for(@page, pending))
        true
      end

      return failure(@page) unless moved

      success(@page)
    end

    private

    # `pages.create` reads the branch from the record's assigned `parent`
    # (`AccessControl::Checker#branch_ids`), so the target is set just for
    # the check and put back straight after -- a refused move leaves the
    # page object exactly as the caller handed it over.
    def may_create_under_target?
      original = @page.parent
      @page.parent = @parent
      authorize!("pages.create", @page)
    ensure
      @page.parent = original
    end
  end
end
