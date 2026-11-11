module Admin
  module Ui
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
    # `admin--rich-text--dialog` (the wrapper's controller) fills and opens
    # them. The wire is `CustomEvent`s: the editor dispatches
    # `rich-text-dialog:open` on `window` naming itself as the `opener`, and
    # the answer comes back as `rich-text-dialog:closed` on that one element
    # -- so two editors on a page never cross wires. The forms' submit
    # buttons name their form with `form=`, which keeps the footer (a
    # sibling of the dialog body) in the same form.
    #
    # A view-only editor opens none of them (`admin--rich-text--editor` refuses every
    # command read-only), so they are rendered for everyone and simply idle.
    #
    # The words the script writes (the image dialog's Edit image / Insert
    # image title and its Save, the alt placeholder's fallback, the YouTube
    # error and "Video id: …") are this component's keys, served on <body>
    # (`Admin::MessagesHelper::SCRIPT_MESSAGES`): the dialogs are drawn once
    # per page, beside it.
    class RichTextDialogsComponent < Admin::AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "Three shared dialogs (native modals named by their titles, Escape closes them) whose fields are labelled, with their help tied by aria-describedby; the YouTube field's Video id line is a polite status and its error an alert; the page search is a list of options under its field, moved through with the arrow keys and picked with Enter; Cancel, Insert, Save and Remove are buttons.",
        motion: :reduced,
        content_edges: %i[none many long],
        widths: :fixed_width,
        interface: [],
        limits: [
          "It is drawn once, by the admin layout; an editor opens a dialog with rich-text-dialog:open and never draws one of its own.",
          "It only gathers input: the editor that opened a dialog applies the answer, so nothing here writes a field or a document.",
          "The page search's rows and words are rich_text/target_search's, shared with the Link popover."
        ],
        states: %i[rest],
        script_states: {
          open: [ "test/system/admin/rich_text_test.rb", "the YouTube dialog rejects text that is not a video, shows the id live, and Enter inserts" ]
        },
        keys: %w[image_title edit_image insert_image save remove_image cancel alt_text caption media_fallback alt_fallback
                 youtube_title insert_video youtube_label youtube_placeholder not_youtube video_id
                 page_title remove_link page_search page_placeholder page_list],
        slots: [],
        controller: "admin--rich-text--dialog",
        keyboard: [ "test/system/admin/rich_text_test.rb", "the YouTube dialog by the keyboard: its field takes the focus, Tab reaches Insert video and Enter inserts" ]
      )

      IMAGE = "rich-text-image-dialog".freeze
      YOUTUBE = "rich-text-youtube-dialog".freeze
      PAGE = "rich-text-page-dialog".freeze

      def search_url = helpers.admin_link_targets_path
    end
  end
end
