module Admin
  module EditorScreen
    # The three form dialogs of the rich-text editor (handoff §10 B25), rendered
    # once by the admin layout -- outside `#content` and every autosave form,
    # like every dialog, so there is exactly one of each however many editors
    # a page holds (one per block card) and the dialogs' own fields never
    # feed an autosave:
    #
    # - `rich-text-image-dialog`: alt text and caption for one image, shown
    #   after the media picker (Insert image) or when an existing image is
    #   edited (Save). The fields carry no `name`; their placeholders are the
    #   library's own text, set per open.
    # - `rich-text-youtube-dialog`: one URL-or-id field with a live
    #   "Video id: …" line and the error line.
    # - `rich-text-page-dialog`: search pages and posts, pick one -- the
    #   Insert menu's "Page link".
    #
    # `admin--rich-text-dialog` (the wrapper's controller) fills and opens
    # them. The wire is `CustomEvent`s: the editor dispatches
    # `rich-text-dialog:open` on `window` naming itself as the `opener`, and
    # the answer comes back as `rich-text-dialog:closed` on that one element
    # -- so two editors on a page never cross wires. The forms' submit
    # buttons name their form with `form=`, which keeps the footer (a
    # sibling of the dialog body) in the same form.
    #
    # A view-only editor opens none of them (`admin--rich-text` refuses every
    # command read-only), so they are rendered for everyone and simply idle.
    class RichTextDialogsComponent < AdminComponent
      IMAGE = "rich-text-image-dialog".freeze
      YOUTUBE = "rich-text-youtube-dialog".freeze
      PAGE = "rich-text-page-dialog".freeze

      def search_url = helpers.admin_link_targets_path
    end
  end
end
