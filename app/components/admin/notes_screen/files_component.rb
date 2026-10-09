module Admin
  module NotesScreen
    # A message's files (notes spec §3.6; handoff "Attachment row", "Inline
    # image and still GIF tile"). An image is shown inline at the message's
    # width, up to 368px, through the notes file action, and a click opens the
    # same address in a new tab (there is no lightbox). Anything else is a
    # row with its name, its kind and size, and a download. EVERY ADDRESS HERE
    # IS `admin_record_note_file_path`: never a blob URL, a signed id or a
    # variant (decision D15; `test/integration/admin/note_files_test.rb`).
    #
    # An image has no size until it is loaded (nothing analyzes a note's
    # file, `Notes::Files`), so its box shows the placeholder gradient at a
    # least height meanwhile; `object-contain` keeps a very wide image from
    # being stretched to that height.
    #
    # A GIF moves. Without reduced motion it plays, like any image. With it,
    # the tile shows a STILL: the picture itself is drawn invisible
    # (`motion-reduce:opacity-0`, so it keeps the tile's shape) and
    # `admin--note-gif` paints its first frame on the canvas over it, under a
    # Play button; Play shows the picture and reads Pause. No variant is
    # made for the still: the browser has the frame already.
    class FilesComponent < Admin::AdminComponent
      # The handoff's attachment row; the composer's chosen files are the
      # same row with a remove button for the download.
      ROW_CLASS = "grid grid-cols-[16px_minmax(0,1fr)_28px] items-center gap-2.5 rounded-cs border border-line py-1.5 pl-2.5 pr-1.5 text-dim".freeze
      NAME_CLASS = "truncate text-[13px] text-ink".freeze
      FACTS_CLASS = "truncate font-cs-mono text-[10px] text-meta".freeze
      ROW_BUTTON_CLASS = "flex size-7 items-center justify-center rounded-cs".freeze
      PICTURE_BOX_CLASS = "admin-note-picture relative block w-full max-w-[368px] overflow-hidden border border-line".freeze
      PICTURE_CLASS = "block h-auto min-h-16 w-full object-contain".freeze

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

      def facts(attachment)
        size = helpers.number_to_human_size(attachment.blob.byte_size) # i18n-ok: a byte size ("1.2 MB"), its units from Rails' own locale data
        [ ::Notes::Files::ALLOWED.fetch(attachment.blob.content_type, t(".file")), size ].join(" · ")
      end
    end
  end
end
