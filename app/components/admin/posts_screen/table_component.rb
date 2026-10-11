module Admin
  module PostsScreen
    # The posts list's table (design pass round 2, Task 17, handoff §4.3):
    # checkbox, Title and path, Type, Status, Translations, a markers column, Updated, "⋯".
    # Wrapped in the list's card; the footer slot is the pagination.
    #
    # It reads nothing it isn't handed, which is what keeps the list's cost
    # flat: `paths` (each post's current public path, one query for the page),
    # `translation_states` (`Translations::StateIndex.states_for`, one query)
    # and the posts themselves come from the controller (no tags are shown or preloaded).
    # The same goes for what features mark a row with (`posts.row.markers`, in
    # the column after Translations; `posts.row.title`, on the title's line and
    # inside the row's link):
    # `Admin::Slots.load` calls each entry's loader once with all the rows of
    # the page, and each row's slot is handed its slice, so a row costs no
    # query of its own.
    #
    # Selection is `admin--posts--bulk-select`'s (on the wrapper around this and the
    # bulk bar): every row's checkbox is a `row` target, the header one is the
    # `all` target ("select all on this page"). They carry no form -- the bulk
    # forms are outside the table -- so their own name is never submitted.
    #
    # Each language chip links to that language's tab of the post's editor.
    # "⋯" is the row's menu: Open, View on site (only while live and listed on
    # a page -- there is no public address otherwise) and Move to trash
    # (only where the viewer may delete that post; it ticks just that row and opens
    # the bulk trash confirmation, so it keeps the list's filters and offers the
    # same Undo).
    class TableComponent < Admin::AdminComponent
      renders_one :footer

      def initialize(posts:, paths:, translation_states:, url_options: {}, locale: ::Locales.default)
        @posts = posts
        @paths = paths
        @translation_states = translation_states
        @loaded = Admin::Slots.load("posts.row.markers", posts, viewer: Current.actor)
        @title_loaded = Admin::Slots.load("posts.row.title", posts, viewer: Current.actor)
        @url_options = url_options
        @locale = locale.to_s
      end

      private

      attr_reader :posts, :paths, :translation_states, :loaded, :title_loaded, :url_options, :locale

      # The selection column is there only for someone who can act on a
      # selection: the bulk bar (`BulkBarComponent#render?`) offers Publish or
      # Move to trash, so a viewer holding neither would tick rows and see
      # nothing happen (final review C, M7).
      def selectable? = can?("posts.publish") || can?("posts.delete")

      def title_of(post) = post.title(locale: locale).presence || "(untitled)"

      def editor_path(post, **extra) = helpers.admin_post_path(post, **url_options.merge(extra))

      def path_of(post) = paths[post.id]

      # The site address of a live post: its path on the public site, in the
      # editing language. Nothing for a draft or scheduled post (the public
      # site answers 404) or one no page lists.
      def site_path(post) = (paths[post.id] if post.live?)
    end
  end
end
