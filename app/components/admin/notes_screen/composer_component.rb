module Admin
  module NotesScreen
    # The field a note is typed in (notes spec §4.2; handoff "Composer",
    # "Mention picker"): one bordered box holding a textarea and, under a
    # line, its toolbar -- the paperclip, the emoji popover and the at-sign
    # on the left, the submit on the right (the send key is said by the
    # submit's tooltip, see below). "@" opens the mention
    # picker. Enter adds a line; Ctrl/⌘+Enter sends (`admin--notes--composer`).
    # An ordinary Turbo form inside the notes frame: it sends no base and is
    # no autosave form.
    #
    # The textarea shows a mention as "@Dana Smith"; `mention_names` carries
    # the names the picker inserted with their ids, and the controller turns
    # them into tokens (`Notes::Mentions`). `key` names the form for its draft
    # in `sessionStorage` and for the answer of a failed submit.
    #
    # The two popovers open below the box, and above it in the thread's reply
    # dock (`[data-note-part=reply]`, which sits at the bottom of the drawer
    # where there is no room below): `POPOVER_SIDE`.
    #
    # FILES (notes spec D9, §3.6; handoff "Composer"). `files: true` gives the
    # form a paperclip and one file field (`files[]`, `multiple`): the files
    # travel WITH the note, as one multipart post -- no direct upload, so
    # nothing is stored for a note that is not saved. The chosen files are
    # listed above the field as attachment rows, each with a remove button
    # (`admin--notes--composer` clones the row in the `<template>`, so the
    # icons are drawn by the server); a sixth file or one over the limit is
    # refused there, in a 12px line, before anything is sent. The server
    # decides again, and alone decides what a file IS (`Notes::Files`).
    # An edit form has none of this (`files: false`): a message's files are
    # fixed when it is written.
    #
    # FILES THAT WERE CHOSEN AND ARE GONE (the handoff's decision 33). A
    # browser never gives a file field its files back, so a form that is
    # drawn again has its text and not its files. A line above the field
    # then names them: "Choose the files again: press-kit.pdf, about.png".
    # `files_lost` is their names after a note that was refused (the server
    # has just been sent them); for a draft that comes back the script fills
    # the same line from the names it kept beside the text. It goes once
    # files are chosen or the note is sent.
    #
    # THE SEND KEY is said by the submit button, not by a hint in the row
    # (decision 30): its `title` and `aria-keyshortcuts`. The server writes
    # the Ctrl form; on an Apple platform the script writes "Send (⌘↵)".
    #
    # `secondary` is a control drawn in the bottom row, 8px to the left of the
    # submit: the thread's Resolve / Reopen, which belongs to a form of its
    # own and names it with `form=` (this component only gives it the place).
    class ComposerComponent < Admin::AdminComponent
      renders_one :secondary

      POPOVER_SIDE = "top-full mt-1.5 [[data-note-part=reply]_&]:top-auto [[data-note-part=reply]_&]:bottom-full [[data-note-part=reply]_&]:mb-1.5 [[data-note-part=reply]_&]:mt-0".freeze
      # The emoji popover: the menu panel with the set (`Notes::EMOJI`) six to
      # a row. A message's "Add a reaction" chip opens the same panel with
      # the same buttons (`Admin::NotesScreen::ReactionsComponent`): one
      # picker, drawn from here. Which edge it hangs from is its user's.
      EMOJI_PANEL_CLASS = "absolute z-30 grid w-56 grid-cols-6 gap-0.5 rounded-cs border border-line bg-surface p-1 shadow-menu".freeze
      EMOJI_BUTTON_CLASS = "cursor-pointer rounded-cs px-1 py-0.5 text-base hover:bg-sunken focus-visible:bg-sunken".freeze
      # `disabled:` is the shared button's own disabled look
      # (`Admin::Ui::ButtonComponent::COMMON_CLASS`): the paperclip and the
      # at-sign are disabled while a note is being sent (decision 41).
      TOOL_CLASS = "flex size-7 cursor-pointer items-center justify-center rounded-cs text-dim hover:bg-sunken hover:text-ink focus-visible:outline-2 focus-visible:outline-accent disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:bg-transparent disabled:hover:text-dim".freeze

      # `edit` makes it an EDIT form: its field is drawn with the saved text,
      # and a draft is what differs from that (`admin--notes--composer`, "an
      # edit that was left"). That a restored draft is unsaved is said in the
      # message's meta line, never above the field (decision 29): that space
      # is for errors. `saved` is the SAVED text of an edit whose field is drawn
      # with something else -- a refused edit comes back holding what was
      # typed -- so the script still measures a draft against what is stored.
      def initialize(url:, key:, label:, submit:, mentions_url:, method: :post, body: "", names: {}, errors: [], hidden: {}, rows: 2, edit: false,
        files: true, files_lost: [], saved: nil)
        @url = url
        @key = key
        @label = label
        @submit = submit
        @mentions_url = mentions_url
        @method = method
        @body = body
        @names = names
        @errors = Array(errors)
        @hidden = hidden
        @rows = rows
        @edit = edit
        @files = files
        @files_lost = Array(files_lost).map(&:to_s).compact_blank
        @saved = saved
      end

      private

      attr_reader :url, :key, :label, :submit, :mentions_url, :method, :body, :names, :errors, :hidden, :rows, :files_lost

      def files? = @files

      def edit? = @edit

      # `TOOL_CLASS`'s `disabled:` look, for the one tool that cannot be
      # `disabled`: the emoji set's <summary>, which says `aria-disabled`.
      TOOL_DISABLED_CLASS = "aria-disabled:cursor-not-allowed aria-disabled:opacity-50 aria-disabled:hover:bg-transparent aria-disabled:hover:text-dim".freeze

      # The submit button's data and what says the send key.
      def submit_attributes
        { title: t(".send_title"), aria: { keyshortcuts: "Control+Enter" }, data: { "admin--notes--composer-target": "submit" } } # i18n-ok: a key combination in ARIA's own notation
      end

      def max_size = ::Notes::Files.max_size

      def field_id = "note-field-#{key}"

      def file_row = Admin::NotesScreen::FilesComponent

      # `user`: the draft is the signed-in person's own. `sessionStorage`
      # belongs to the tab, not to the session, so without it the next person
      # to sign in on the same tab would be handed the last one's unsent text.
      def form_data
        { controller: "admin--notes--composer", turbo_frame: "notes", note_composer: key,
          "admin--notes--composer-key-value": key, "admin--notes--composer-mentions-url-value": mentions_url,
          "admin--notes--composer-user-value": Current.user&.id, "admin--notes--composer-edit-value": edit?, "admin--notes--composer-saved-value": @saved,
          action: "submit->admin--notes--composer#sending turbo:submit-start->admin--notes--composer#sending turbo:submit-end->admin--notes--composer#sent", messages: script_messages }
      end

      # On a line of its own, ending the line: `test/lib/script_messages_test.rb`
      # reads the literal keys of a `messages_data(...)` call only when the
      # closing bracket is followed by a line end, a comma or another bracket.
      def script_messages = messages_data("notes.script.mentions.none", "notes.script.mentions.count", "notes.script.files.too_many", "notes.script.files.too_big", "notes.script.files.remove", "notes.script.files.again", "notes.script.send_apple", "notes.script.sending")
    end
  end
end
