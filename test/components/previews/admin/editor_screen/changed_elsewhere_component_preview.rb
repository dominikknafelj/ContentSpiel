module Admin
  module EditorScreen
    # The "Changed elsewhere" bar (handoff §10 B19). A page nobody has
    # audited yet reads without a name.
    class ChangedElsewhereComponentPreview < ViewComponent::Preview
      def default
        render Admin::EditorScreen::ChangedElsewhereComponent.new(record: Page.first || Page.new, reload_url: "#")
      end
    end
  end
end
