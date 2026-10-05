module Admin
  module TrashScreen
    # `RowComponent` (round 3, Task 14): a post row, a page row with its
    # subpage sentence, and an image that is still used (Delete now… disabled
    # with its reason as text) -- built from unsaved records -- and the three
    # ways a page's Restore is drawn, built from real pages (rolled back with
    # the preview request): one click for a root whose parent is still there,
    # an inline "Restore under" with its parent select when the parent is in
    # the trash too, and the same disabled with its reason when the viewer has
    # no page to restore it under.
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

      def page_restores_in_one_click
        page = PreviewFixtures.page(title: "Spring campaign")
        page.update_columns(trashed_at: 2.hours.ago, trash_root_id: page.id)
        table(row(page.reload, who: "You"))
      end

      def page_restore_under
        child = orphaned_child
        table(row(child, who: "Ada Lovelace", parent_choices: [ [ "Home", PreviewFixtures.root_page.id ], [ "Home / About", PreviewFixtures.page(title: "About").id ] ], tab: "pages"))
      end

      def page_restore_under_with_no_parent_to_offer
        table(row(orphaned_child, who: "Ada Lovelace", parent_choices: []))
      end

      private

      # A page trashed on its own whose parent went to the trash afterwards:
      # its own root, with nowhere to go back to.
      def orphaned_child
        section = PreviewFixtures.page(title: "Section")
        child = section.children.create!(page_type: :standard, title: "Child #{SecureRandom.hex(4)}", published_at: Time.current)
        child.update_columns(trashed_at: 1.day.ago, trash_root_id: child.id)
        section.update_columns(trashed_at: 1.hour.ago, trash_root_id: section.id)
        child.reload
      end

      def post = Post.new(id: 9000, title: "Retired announcement", trashed_at: 1.day.ago)

      def row(item, **opts)
        Admin::TrashScreen::RowComponent.new(item:, retention_days: 30, **opts)
      end

      def table(row) = render_with_template(template: "admin/trash_screen/row_component_preview/row", locals: { row: })
    end
  end
end
