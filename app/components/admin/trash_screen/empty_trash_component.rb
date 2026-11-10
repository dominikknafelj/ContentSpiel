module Admin
  module TrashScreen
    # "Empty trash…" in the screen header, and its confirm dialog. Only for a
    # `trash.empty` holder, and only while something is in the trash.
    #
    # The sentence counts what `Trash::Empty` really deletes -- everything in
    # the trash, which `trash.empty` reaches whether or not the viewer could
    # list it (the screen's tabs count only what they may act on) -- so the
    # numbers are `Trash.roots`', handed in as `pages` (branch roots),
    # `subpages` (the pages that go with a root), `posts`, `images` and
    # `forms`. Only the kinds present are named, the subpages in brackets
    # after the pages ("1 page (with 1 subpage), 1 post and 1 image").
    class EmptyTrashComponent < Admin::AdminComponent
      DIALOG_ID = "empty-trash-dialog".freeze

      def initialize(pages:, subpages:, posts:, images:, forms: 0, url_options: {})
        @pages = pages
        @subpages = subpages
        @posts = posts
        @images = images
        @forms = forms
        @url_options = url_options
      end

      def render? = can?("trash.empty") && (@pages + @posts + @images + @forms).positive?

      def sentence = t(".body", items: listed(kinds))

      # Each kind present, counted in its own words.
      def kinds
        parts = []
        if @pages.positive?
          pages = t(".pages", count: @pages)
          parts << (@subpages.positive? ? t(".pages_with_subpages", pages:, subpages: t(".subpages", count: @subpages)) : pages)
        end
        { posts: @posts, images: @images, forms: @forms }.each { |kind, count| parts << t(".#{kind}", count:) if count.positive? }
        parts
      end

      # "a", "a and b", "a, b and c": the last two joined by `list_last`, the
      # rest by `list_separator`.
      def listed(parts)
        return parts.first if parts.one?

        t(".list_last", rest: parts[0...-1].join(t(".list_separator")), last: parts.last)
      end

      def empty_path = helpers.admin_empty_trash_path(**@url_options)
    end
  end
end
