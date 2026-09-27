# The "move to rank N" logic (spec §3): the admin's reordering UI (and
# `Pages::Move`) express "put this page here" as a plain rank number rather
# than drag-and-drop (page-tree design spec section 5), and that number has to
# actually mean "this many places down from the top of its siblings" -- which
# closure_tree's own renumbering doesn't give for free (see the comment on
# `included do` below). Namespaced under `Page` (not a shared concern) because
# this logic is specific to the page tree's own reordering UI, not something
# any other closure_tree model in this app needs.
module Page::TreeRanking
  extend ActiveSupport::Concern

  included do
    # Reordering a branch is done by typing a new `position` (page-tree design
    # spec section 5 waives drag-and-drop, so that number *is* the reordering
    # UI), and the number has to mean "put me at this rank among my siblings".
    #
    # closure_tree does renumber siblings after a position change, but only from
    # the number that was written: two siblings holding the same number is a tie
    # Postgres breaks however it likes, so typing the number of the page you want
    # to get ahead of usually leaves the order exactly as it was. Only a number
    # below every sibling's, or above all of them, moved the page at all.
    #
    # So the rank is applied here instead: the requested number is captured
    # before closure_tree renumbers over it, and the siblings are then written
    # out in the order it asks for. `update_columns` keeps that from re-entering
    # this chain on every sibling, and leaves the dense 0..n-1 numbering
    # closure_tree expects.
    before_save :remember_requested_position
    after_save :place_among_siblings
  end

  private

  # closure_tree's own `after_save` reloads this record as part of renumbering,
  # which is what takes the requested number back out of reach of the callback
  # that has to act on it.
  #
  # Also captured on a parent change with no numeric change at all: `position`
  # is only unique *within* a parent, so a page moved to a new parent quite
  # often already happens to hold a number that some sibling under its *old*
  # parent also had (both start counting from 0) -- `will_save_change_to_
  # position?` alone would then see the same value going in as coming out and
  # never notice a rank was requested, leaving the move to fall back to
  # closure_tree's own tie-breaking (by id) instead of the rank `Pages::Move`
  # was actually asked for.
  def remember_requested_position
    @requested_position = position if will_save_change_to_position? || will_save_change_to_parent_id?
  end

  def place_among_siblings
    requested = @requested_position
    @requested_position = nil
    return if requested.nil?

    # `self` rather than the row for this page, so the in-memory record ends up
    # holding the position it was actually given.
    others = self.class.where(parent_id: parent_id).where.not(id: id).order(:position, :id).to_a
    ordered = others.insert(requested.clamp(0, others.size), self)

    ordered.each_with_index do |page, index|
      page.update_columns(position: index) unless page.position == index
    end
  end
end
