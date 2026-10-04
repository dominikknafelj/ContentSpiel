module Admin
  module TrashScreen
    # `RowComponent` (round 3, Task 14): a post row, a page row with its
    # subpage sentence, and an image that is still used (Delete now… disabled
    # with its reason as text). Rows are built from unsaved records.
    class RowComponentPreview < ViewComponent::Preview
      def post_row = table(row(post, who: "You"))

      def page_row
        page = Page.new(id: 9001, title: "Spring campaign", trashed_at: 3.hours.ago, trash_root_id: 9001)
        table(row(page, who: "Ada Lovelace", subpage_sentence: "Includes 4 subpages: Landing, Offer, FAQ and 1 more", purge_subpage_count: 4))
      end

      def image_in_use
        created = PreviewFixtures.media_asset.tap { |a| a.update_columns(trashed_at: 2.days.ago) }
        asset = Media::Asset.with_variants.find(created.id)
        table(row(asset, who: "System", used_by: 2))
      end

      private

      def post = Post.new(id: 9000, title: "Retired announcement", trashed_at: 1.day.ago)

      def row(item, **opts)
        Admin::TrashScreen::RowComponent.new(item:, retention_days: 30, **opts)
      end

      def table(row) = render_with_template(template: "admin/trash_screen/row_component_preview/row", locals: { row: })
    end
  end
end
