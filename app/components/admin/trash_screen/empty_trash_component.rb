module Admin
  module TrashScreen
    # "Empty trash…" in the screen header, and its confirm dialog. Only for a
    # `trash.empty` holder, and only while something is in the trash.
    #
    # The sentence counts what `Trash::Empty` really deletes -- everything in
    # the trash, which `trash.empty` reaches whether or not the viewer could
    # list it (the screen's tabs count only what they may act on) -- so the
    # numbers are `Trash.roots`', handed in as `pages` (branch roots),
    # `subpages` (the pages that go with a root), `posts` and `images`.
    # Only the kinds present are named; subpages appear in brackets, as in
    # the handoff's mock ("1 page (with 1 subpage), 1 post and 1 image").
    class EmptyTrashComponent < Admin::AdminComponent
      DIALOG_ID = "empty-trash-dialog".freeze

      def initialize(pages:, subpages:, posts:, images:, url_options: {})
        @pages = pages
        @subpages = subpages
        @posts = posts
        @images = images
        @url_options = url_options
      end

      def render? = can?("trash.empty") && (@pages + @posts + @images).positive?

      def sentence
        parts = []
        if @pages.positive?
          part = helpers.pluralize(@pages, "page")
          part += " (with #{helpers.pluralize(@subpages, "subpage")})" if @subpages.positive?
          parts << part
        end
        parts << helpers.pluralize(@posts, "post") if @posts.positive?
        parts << helpers.pluralize(@images, "image") if @images.positive?
        "This deletes #{parts.to_sentence(last_word_connector: " and ")} for good. It can't be undone."
      end

      def empty_path = helpers.admin_empty_trash_path(**@url_options)
    end
  end
end
