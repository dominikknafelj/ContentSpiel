module Pages
  # Moves a page to rank `position` under `parent` (spec §7.2). The rank
  # semantics live in Page::TreeRanking; this adds the rules a UI must not be
  # able to break: the homepage stays the root, and a page can't become its
  # own ancestor.
  class Move < ApplicationService
    def initialize(page, parent:, position:, actor: Current.actor)
      @page, @parent, @position, @actor = page, parent, position.to_i, actor
    end

    def call
      authorize!(:move, @page)
      return failure(@page, [ "The homepage can't be moved" ]) if @page.root?
      return failure(@page, [ "A page can't be moved under itself or one of its own subpages" ]) if @parent.self_and_ancestors.include?(@page)

      @page.parent = @parent
      @page.position = @position
      return failure(@page) unless @page.save

      record_event(:page_moved, page: @page)
      success(@page)
    end
  end
end
