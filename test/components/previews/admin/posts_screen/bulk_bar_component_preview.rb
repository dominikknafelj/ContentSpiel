module Admin
  module PostsScreen
    # The bulk bar. It is `hidden` by design until `admin--posts--bulk-select` (on
    # the list's wrapper) has rows ticked, so on its own this preview renders
    # nothing visible; the screen itself (the posts list) is where it shows.
    class BulkBarComponentPreview < ViewComponent::Preview
      def default
        render Admin::PostsScreen::BulkBarComponent.new(list_fields: { "scope" => "drafts" })
      end
    end
  end
end
