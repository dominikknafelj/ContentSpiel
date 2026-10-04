module Admin
  module EditorScreen
    # The form inside the New post dialog (design pass round 2, handoff
    # `Studio Modals.dc.html`): a type picker (radio cards, each the type's dot
    # and label, only the types the viewer may create -- `posts.create` scoped
    # on `content_types`), Title and a live URL line, or "Not listed on any
    # page yet" for a type no listing page lists. Its own component for the
    # same two reasons as `NewPageFormComponent`: the no-JS `GET /posts/new`
    # page and the Turbo Stream that replaces just `#new-post-form` after a
    # refused create.
    #
    # Loaded when the dialog OPENS, into the shell's turbo-frame (see
    # `NewPostDialogComponent`), so the listing paths are never stale.
    #
    # A post's URL is its canonical listing page's path plus its own slug
    # (`PublicSite::Paths.canonical_pages`, asked once for an unsaved post of
    # every creatable type), so each radio carries `data-path`: that page's path in the editing
    # language, locale prefix included, no trailing slash -- blank when no page
    # lists the type, which is what makes `admin--new-record` print the
    # "Not listed" line. The first type is preselected unless one was asked for
    # (a split button's type, the posts list) or typed before a refusal.
    class NewPostFormComponent < Admin::AdminComponent
      FORM_ID = "new-post-form".freeze
      TITLE_ID = "new-post-title".freeze
      TYPE_ID = "new-post-type".freeze

      Choice = Struct.new(:name, :label, :path, keyword_init: true)

      def initialize(url_options: {}, locale: ::Locales.default, content_type: nil, title: nil, errors: nil)
        @url_options = url_options
        @locale = locale.to_s
        @requested_type = content_type.to_s
        @title = title.to_s
        @errors = errors
      end

      def creatable? = choices.any?

      def render? = creatable?

      def form_id = FORM_ID

      def url = helpers.admin_posts_path(**url_options)

      attr_reader :title

      def choices
        @choices ||= begin
          prefix = PublicSite::Urls.new.prefix(locale)
          types = ContentTypes.all.select { |type| can?("posts.create", Post.new(content_type: type.name)) }
          posts = types.to_h { |type| [ type, Post.new(content_type: type.name) ] }
          pages = PublicSite::Paths.canonical_pages(posts.values)
          # One query for every listing page's stored path, not one per page.
          stored = PublicPath.current.where(record_type: "Page", record_id: pages.values.compact.map(&:id), locale: locale).pluck(:record_id, :path).to_h
          types.map do |type|
            page = pages.fetch(posts.fetch(type))
            # A draft or private listing page's path is only for someone who may
            # read that page: a posts-only author reads "Not listed on any
            # page yet" instead of learning the slug path of a page they can't
            # open (final review A, M4).
            visible = page && (page.live? || can?("pages.read", page))
            path = visible && stored[page.id] ? "#{prefix}#{stored[page.id]}".sub(%r{/+\z}, "") : nil
            Choice.new(name: type.name, label: type.label, path: path)
          end
        end
      end

      def selected_choice = @selected_choice ||= choices.find { |choice| choice.name == requested_type } || choices.first

      def selected?(choice) = choice.name == selected_choice.name

      def initial_url
        path = selected_choice.path
        path ? "URL: #{path}/#{title.parameterize}" : "Not listed on any page yet"
      end

      def note = "Created as a draft in #{::Locales.name(locale)}. Everything can be changed in the editor."

      def error_summary
        @error_summary ||= NewRecordErrors.summarise(errors)
      end

      def field_ids = { "title" => TITLE_ID, "slug" => TITLE_ID, "content_type" => TYPE_ID }

      def title_invalid? = error_summary.is_a?(Hash) && (error_summary.key?("title") || error_summary.key?("slug"))

      private

      attr_reader :url_options, :locale, :requested_type, :errors
    end
  end
end
