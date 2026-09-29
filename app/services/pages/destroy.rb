module Pages
  # Deletes a page (spec §7.2). The homepage check lives here, since `Page`
  # itself has no notion of "the homepage" beyond `root?`; the "still has
  # children" check is `Page#ensure_no_children` (`before_destroy, prepend:
  # true`) instead, so any caller that destroys a Page directly gets that
  # refusal too, not just this service.
  #
  # Needs `pages.delete` on the page (access-control design spec §3.3).
  # `page.deleted` is recorded before the destroy, in its transaction, so
  # the snapshot is the page's last state and a refused destroy (children,
  # say) rolls the event back with it.
  class Destroy < ApplicationService
    def initialize(page, actor: Current.actor)
      @page = page
      @actor = actor
    end

    def call
      return denied("pages.delete", @page) unless authorize!("pages.delete", @page)
      return failure(@page, [ "The homepage can't be deleted" ]) if @page.root?

      destroyed = Page.transaction do
        record_event("page.deleted", subject: @page)
        # Loaded *before* the destroy, so these are the very objects the
        # page's `dependent: :destroy` goes on to destroy (it destroys the
        # loaded association target) -- each is then `destroyed?`, which is
        # what makes `Media::UsageIndex.refresh` drop its rows rather than
        # recompute them from stale attributes.
        blocks = @page.content_blocks.to_a
        @page.destroy || raise(ActiveRecord::Rollback)
        # The page's hero row and every destroyed block's rows go with them
        # (media library design spec §5.1) -- `media_usages.owner` is
        # polymorphic, so no FK cascade would ever remove them.
        [ @page, *blocks ].each { |owner| Media::UsageIndex.refresh(owner) }
        true
      end

      return failure(@page) unless destroyed

      success(@page)
    end
  end
end
