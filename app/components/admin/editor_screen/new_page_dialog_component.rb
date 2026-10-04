module Admin
  module EditorScreen
    # The New page dialog (`new-page-dialog`, 560 wide), rendered ONCE in the
    # layout outside `#content` (forms can't nest). Only the SHELL is rendered
    # there: a loading line and an empty `<turbo-frame id="new-page-form-frame">`,
    # and a disabled Create button. The form itself is loaded when the dialog
    # opens (`admin--new-record` sets the frame's `src` to `GET /pages/new`,
    # with the trigger's preset as query params), because building it costs
    # a page load and a permission check per page -- not something every
    # CS Studio request should pay -- and a copy rendered with the page would go
    # stale after a rename. The shell needs no query: it is rendered when the
    # viewer holds `pages.create` anywhere (`can?` without a record). A
    # trigger without the dialog on the page falls through to its `href`, the
    # standalone no-JS page.
    #
    # Opened with `data: dialog_trigger("new-page-dialog")` merged with
    # `"new-page-parent-id-param": id` and `"new-page-title-param": text`
    # (read from the trigger's own attributes on the `admin--dialog:opening` event).
    class NewPageDialogComponent < Admin::AdminComponent
      ID = "new-page-dialog".freeze
      FRAME_ID = "new-page-form-frame".freeze

      def initialize(url_options: {})
        @url_options = url_options
      end

      def render? = can?("pages.create")

      def form_url = helpers.new_admin_page_path(**url_options)

      private

      attr_reader :url_options
    end
  end
end
