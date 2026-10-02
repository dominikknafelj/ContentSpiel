module Admin
  module DashboardScreen
    # The dashboard's quick-create bar (dashboard spec §4.1): a quick draft
    # form (title + content type), "New page" and "Upload image" -- each
    # part shown only to someone who could use it, and the whole bar not at
    # all for someone who can use none of them.
    #
    # The type select offers exactly the registered content types the actor
    # may create a post of, judged per type against an unsaved post of it
    # (`posts.create` can be scoped by `content_types`) -- the same check
    # `Admin::PostsController#creatable_content_types` makes for "New
    # post". It only narrows what's offered: `Posts::Save` repeats the
    # check on whatever type actually arrives, so a forged one is refused
    # there (403), not merely hidden here.
    #
    # `title:`/`content_type:`/`errors:` carry a failed draft back into the
    # re-rendered form (`Admin::DashboardController#create_draft`).
    class QuickCreateComponent < Admin::AdminComponent
      def initialize(title: nil, content_type: nil, errors: [])
        @title = title
        @content_type = content_type
        @errors = errors
      end

      def render? = content_types.any? || new_page? || upload_image?

      def content_types
        @content_types ||= ContentTypes.all.select { |type| can?("posts.create", Post.new(content_type: type.name)) }
      end

      def new_page? = can?("pages.create")

      def upload_image? = can?("media.upload")

      private

      attr_reader :title, :content_type, :errors

      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
    end
  end
end
