module Pages
  # Deletes a page (spec §7.2). The homepage check lives here, since `Page`
  # itself has no notion of "the homepage" beyond `root?`; the "still has
  # children" check is `Page#ensure_no_children` (`before_destroy, prepend:
  # true`) instead, so any caller that destroys a Page directly -- Avo
  # included -- gets that refusal too, not just this service.
  class Destroy < ApplicationService
    def initialize(page, actor: Current.actor)
      @page = page
      @actor = actor
    end

    def call
      authorize!(:destroy, @page)
      return failure(@page, [ "The homepage can't be deleted" ]) if @page.root?

      return failure(@page) unless @page.destroy

      record_event(:page_destroyed, page: @page)
      success(@page)
    end
  end
end
