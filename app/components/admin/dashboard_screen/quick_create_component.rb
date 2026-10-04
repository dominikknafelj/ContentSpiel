module Admin
  module DashboardScreen
    # The dashboard's quick-create bar (design pass round 2, Task 16): ONE
    # row in a card -- a title input, a type `<select>` and "Create draft".
    # The select offers the content types the actor may create a post of plus
    # "Page" when they may create pages; choosing Page and submitting opens
    # the New page dialog with the typed title carried over (Inside = Home,
    # the dialog's own default) instead of creating anything here
    # (`admin--quick-create`, which clicks the hidden "New page" trigger, a
    # real link to the standalone New page screen -- also where a submit
    # lands without JS: `Admin::DashboardController#create_draft` redirects
    # a "page" there). "New page" and "Upload image" are gone from the bar:
    # the tree, the sidebar and ⌘K own those. The whole bar is hidden when
    # nothing is creatable.
    #
    # The type select offers exactly the registered content types the actor
    # may create a post of, judged per type against an unsaved post of it
    # (`posts.create` can be scoped by `content_types`) -- the same check
    # `Admin::EditorScreen::NewPostFormComponent#choices` makes for "New
    # post". It only narrows what's offered: `Posts::Save` repeats the
    # check on whatever type actually arrives, so a forged one is refused
    # there (403), not merely hidden here.
    #
    # `title:`/`content_type:`/`errors:` carry a failed draft back into the
    # re-rendered form (`Admin::DashboardController#create_draft`).
    class QuickCreateComponent < Admin::AdminComponent
      # The select's value for "Page" -- never a registered content type name.
      PAGE = "page".freeze

      def initialize(title: nil, content_type: nil, errors: [])
        @title = title
        @content_type = content_type
        @errors = errors
      end

      def render? = content_types.any? || new_page?

      def content_types
        @content_types ||= ContentTypes.all.select { |type| can?("posts.create", Post.new(content_type: type.name)) }
      end

      def new_page? = can?("pages.create")

      # `[label, value]` pairs of the select, Page last.
      def choices
        options = content_types.map { |type| [ type.label, type.name ] }
        options << [ "Page", PAGE ] if new_page?
        options
      end

      private

      attr_reader :title, :content_type, :errors

      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
    end
  end
end
