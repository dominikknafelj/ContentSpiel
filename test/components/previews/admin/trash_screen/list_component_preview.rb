module Admin
  module TrashScreen
    # `Admin::TrashScreen::ListComponent`: the card with its table -- a page
    # branch ("Includes N subpages: …"), a post and an image, each row's who,
    # sentence and counts worked out by the list from real records (rolled back
    # with the preview request) -- and its empty states: the whole trash, one
    # tab, and the list that is empty only for this viewer.
    class ListComponentPreview < ViewComponent::Preview
      def with_items
        section = PreviewFixtures.page(title: "Spring campaign")
        members = %w[Landing Offer FAQ Terms].map do |title|
          section.children.create!(page_type: :standard, title: "#{title} #{SecureRandom.hex(4)}", published_at: Time.current)
        end
        ([ section ] + members).each { |page| page.update_columns(trashed_at: 3.hours.ago, trash_root_id: section.id) }
        post = PreviewFixtures.post(title: "Retired announcement").tap { |record| record.update_columns(trashed_at: 1.day.ago) }
        asset = PreviewFixtures.media_asset.tap { |record| record.update_columns(trashed_at: 2.days.ago) }

        render Admin::TrashScreen::ListComponent.new(items: [ section.reload, post.reload, Media::Asset.with_variants.find(asset.id) ], retention_days: 30)
      end

      def empty
        render Admin::TrashScreen::ListComponent.new(items: [], retention_days: 30)
      end

      def empty_tab
        render Admin::TrashScreen::ListComponent.new(items: [], retention_days: 30, tab: "images")
      end

      # What a `trash.empty` holder sees when the trash holds items none of
      # which they may restore or delete one by one.
      def nothing_this_viewer_can_restore
        render Admin::TrashScreen::ListComponent.new(items: [], retention_days: 30, tab: "posts", hidden_items: true)
      end
    end
  end
end
