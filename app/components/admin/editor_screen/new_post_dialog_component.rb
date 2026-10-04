module Admin
  module EditorScreen
    # The New post dialog (`new-post-dialog`, 560 wide), rendered ONCE in the
    # layout outside `#content` (forms can't nest). Only the SHELL is rendered
    # there: a loading line and an empty `<turbo-frame id="new-post-form-frame">`,
    # and a disabled Create button. The form itself is loaded when the dialog
    # opens (`admin--new-record` sets the frame's `src` to `GET /posts/new`,
    # with the trigger's preset as query params), because building it costs
    # a listing-page lookup per content type -- not something every
    # CS Studio request should pay -- and a copy rendered with the page would go
    # stale after a rename. The shell needs no query: it is rendered when the
    # viewer holds `posts.create` anywhere (`can?` without a record). A
    # trigger without the dialog on the page falls through to its `href`, the
    # standalone no-JS page.
    #
    # Opened with `data: dialog_trigger("new-post-dialog")` merged with
    # `"new-post-type-param": name` and `"new-post-title-param": text`
    # (read from the trigger's own attributes on the `admin--dialog:opening` event).
    class NewPostDialogComponent < Admin::AdminComponent
      ID = "new-post-dialog".freeze
      FRAME_ID = "new-post-form-frame".freeze

      def initialize(url_options: {})
        @url_options = url_options
      end

      def render? = can?("posts.create")

      def form_url = helpers.new_admin_post_path(**url_options)

      private

      attr_reader :url_options
    end
  end
end
