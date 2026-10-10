module Admin
  module EditorScreen
    # `Admin::EditorScreen::ScheduleDialogComponent`: a draft, a scheduled
    # record (Remove schedule at the bottom left) and a refused submit. The
    # dialogs start closed -- Lookbook's layout has no `admin--ui--dialog` on
    # `<body>` -- so open one from the console with
    # `document.querySelector("dialog").showModal()`.
    class ScheduleDialogComponentPreview < ViewComponent::Preview
      def draft
        render Admin::EditorScreen::ScheduleDialogComponent.new(record: unpublished_page)
      end

      def scheduled
        page = unpublished_page
        page.update!(published_at: 1.week.from_now)
        render Admin::EditorScreen::ScheduleDialogComponent.new(record: page)
      end

      def past_time_error
        render Admin::EditorScreen::ScheduleDialogComponent.new(record: unpublished_page, error: "Pick a time in the future.")
      end

      private

      def unpublished_page
        PreviewFixtures.root_page.children.create!(page_type: :standard, title: "Schedule preview #{SecureRandom.hex(4)}")
      end
    end
  end
end
