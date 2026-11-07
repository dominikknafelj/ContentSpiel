module Admin
  module TagsScreen
    # One tag's detail, in the Tags list's rail (`app/views/admin/tags/
    # show.html.erb`, the `tag-detail` frame): its name, how many of its
    # posts the viewer may read, the newest-changed of them with their state,
    # "Show all N posts" when there are more than the rail lists, and the
    # triggers of the list's one Merge dialog and one Delete dialog.
    #
    # It reads nothing it isn't handed: `posts` (at most `DETAIL_POSTS`,
    # already read-scoped and kept, `Posts::List`), `count` (that list's All
    # count) and `carriers` (every post carrying the tag, trashed ones too,
    # the number the dialogs' sentences say) come from the controller, which
    # hands `[]`, nil and nil to a viewer without `posts.read`: such a viewer
    # is told no figure and shown no post, and the dialogs say their neutral
    # sentences.
    #
    # The root's id is the tag's (`tag-detail-<id>`): a rename's answer
    # replaces it with the detail again, a delete's with the empty line, and
    # neither touches a detail of another tag. The heading takes the focus
    # when a Details link opened it (`admin--tags--detail`), so it carries
    # `tabindex="-1"`.
    #
    # Merge into… is the secondary button and Delete tag… the danger text
    # button: a destructive trigger outside a dialog is danger text, and the
    # red fill is the dialog's own confirm. Neither is primary: the Tags
    # screen has none outside its dialogs, since tags are made on posts.
    class DetailComponent < Admin::AdminComponent
      FRAME_ID = "tag-detail".freeze
      DETAIL_POSTS = 8

      def initialize(tag:, posts:, count:, carriers:, locale:, url_options: {})
        @tag = tag
        @posts = posts
        @count = count
        @carriers = carriers
        @url_options = url_options
        @locale = locale.to_s
      end

      def root_id = "tag-detail-#{tag.id}"

      def heading_id = "#{root_id}-name"

      def counted? = !count.nil?

      def show_all? = counted? && count > posts.size

      def title_of(post) = post.title(locale: locale).presence || t(".untitled")

      def editor_path(post) = helpers.admin_post_path(post, **url_options)

      def posts_path = helpers.admin_posts_path(tag: tag.name, **url_options)

      def merge_data
        dialog_trigger("merge-tag-dialog").merge(
          tag_id: tag.id, tag_name: tag.name,
          tag_merge_title: helpers.tag_merge_title(tag), tag_merge_text: helpers.tag_merge_text(tag, carriers, count)
        )
      end

      def delete_data
        dialog_trigger("delete-tag-dialog").merge(
          tag_id: tag.id, tag_name: tag.name,
          tag_delete_title: helpers.tag_delete_title(tag), tag_delete_text: helpers.tag_delete_text(carriers, count)
        )
      end

      private

      attr_reader :tag, :posts, :count, :carriers, :url_options, :locale
    end
  end
end
