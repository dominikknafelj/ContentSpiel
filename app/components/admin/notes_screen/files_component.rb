module Admin
  module NotesScreen
    # A message's files (notes spec §3.6; handoff "Attachment row", "Inline
    # image and still GIF tile"). An image is shown inline through the notes
    # file action. Anything else is a row with its name, its kind and size,
    # and a download. EVERY ADDRESS HERE IS `admin_record_note_file_path`:
    # never a blob URL, a signed id or a variant (decision D15;
    # `test/integration/admin/note_files_test.rb`).
    #
    # A PLAIN CLICK ON A PICTURE OPENS THE IMAGE VIEWER
    # (`Admin::Ui::ImageViewerComponent`, drawn once by the layout). Each
    # picture's link is a viewer item (`data-image-viewer-item`, with its
    # `data-name`, its `data-facts` as a document's row says them, and
    # `data-image-viewer-gif` on a GIF), and the files' box is the group the
    # viewer steps through (`data-image-viewer-group`, the message's id), so
    # the viewer steps through this message's pictures and never a
    # document's or another message's. The link stays a link to the picture
    # in a new tab: a modified or middle click, and a page without the
    # script, open it there.
    #
    # A PICTURE IS SHOWN AT ITS NATURAL SIZE, up to the full width of the
    # message, left-aligned, and never enlarged (the handoff's decision 32):
    # the box shrinks to the picture (`w-fit`), the picture is `max-w-full`
    # with `width` and `height` auto. Its size is not known before it has
    # loaded -- nothing analyzes a note's file (`Notes::Files`), so there is
    # no stored width or height to reserve the space with -- and the box
    # grows from nothing to the picture when it arrives: that shift is
    # accepted. The placeholder gradient is the box's background, seen behind
    # a picture that is partly transparent.
    #
    # A VERY SMALL PICTURE (the handoff's decision 37). The tile of a GIF and
    # of a still image is at least 120×90, border included; a picture smaller
    # than that stands centred in it at its own size, on the placeholder
    # ground, so a GIF's label and its Play control always fit. A larger
    # picture is its own tile, as before.
    #
    # A GIF moves. Its tile is `Admin::Ui::GifComponent` on this box (the
    # same part the image viewer's stage draws): without reduced motion it
    # plays, like any image; with it, the tile shows a STILL, the first frame
    # `admin--ui--gif` paints on a canvas over the invisible picture, under a
    # Play button that shows the picture and reads Pause. No variant is made
    # for the still: the browser has the frame already.
    class FilesComponent < Admin::AdminComponent
      # The handoff's attachment row; the composer's chosen files are the
      # same row with a remove button for the download.
      ROW_CLASS = "grid grid-cols-[16px_minmax(0,1fr)_28px] items-center gap-2.5 rounded-cs border border-line py-1.5 pl-2.5 pr-1.5 text-dim".freeze
      NAME_CLASS = "truncate text-[13px] text-ink".freeze
      FACTS_CLASS = "truncate text-label text-meta".freeze
      ROW_BUTTON_CLASS = "flex size-7 items-center justify-center rounded-cs".freeze
      PICTURE_BOX_CLASS = "admin-note-picture relative flex min-h-[90px] w-fit min-w-[120px] max-w-full items-center justify-center self-start overflow-hidden border border-line".freeze
      PICTURE_CLASS = "block h-auto w-auto min-w-0 max-w-full".freeze

      def initialize(message:, listing:)
        @message = message
        @listing = listing
      end

      def render? = attachments.any?

      private

      attr_reader :message, :listing

      def attachments = listing.files_of(message)

      def path(attachment) = helpers.admin_record_note_file_path(*helpers.note_args(listing.container), message.thread_id, message.id, attachment.id)

      def image?(attachment) = ::Notes::Files.image?(attachment.blob.content_type)

      def gif?(attachment) = attachment.blob.content_type == "image/gif"

      # The marks that make a picture's link a viewer item: what the viewer's
      # head says of it, read once when the viewer opens.
      def viewer_item(attachment, name) = { image_viewer_item: true, name: name, facts: facts(attachment) }

      def facts(attachment)
        size = helpers.number_to_human_size(attachment.blob.byte_size) # i18n-ok: a byte size ("1.2 MB"), its units from Rails' own locale data
        [ ::Notes::Files::ALLOWED.fetch(attachment.blob.content_type, t(".file")), size ].join(" · ")
      end
    end
  end
end
