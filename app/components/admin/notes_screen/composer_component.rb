module Admin
  module NotesScreen
    # The field a note is typed in (notes spec §4.2; handoff "Composer",
    # "Mention picker"): one bordered box holding a textarea and, under a
    # line, its toolbar -- the emoji popover and the at-sign on the left, the
    # send key's hint and the submit on the right. "@" opens the mention
    # picker. Enter adds a line; Ctrl/⌘+Enter sends (`admin--note-composer`).
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
    # (`admin--note-composer` clones the row in the `<template>`, so the
    # icons are drawn by the server); a sixth file or one over the limit is
    # refused there, in a 12px line, before anything is sent. The server
    # decides again, and alone decides what a file IS (`Notes::Files`).
    # An edit form has none of this (`files: false`): a message's files are
    # fixed when it is written. `files_lost` adds, under a refusal's
    # reasons, that the files have to be attached again: the form that comes
    # back has the text, and a browser never gives a file field its files
    # back.
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
      TOOL_CLASS = "flex size-7 cursor-pointer items-center justify-center rounded-cs text-dim hover:bg-sunken hover:text-ink focus-visible:outline-2 focus-visible:outline-accent".freeze

      # `unsaved` makes it an EDIT form: the words of the note ("Unsaved
      # edit") it shows when its field was filled from a draft instead of the
      # saved text (`admin--note-composer`, "an edit that was left").
      def initialize(url:, key:, label:, submit:, mentions_url:, method: :post, body: "", names: {}, errors: [], hidden: {}, rows: 2, unsaved: nil,
        files: true, files_lost: false)
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
        @unsaved = unsaved
        @files = files
        @files_lost = files_lost
      end

      private

      attr_reader :url, :key, :label, :submit, :mentions_url, :method, :body, :names, :errors, :hidden, :rows, :unsaved

      def files? = @files

      def files_lost? = @files_lost.present?

      def field_id = "note-field-#{key}"

      def file_row = Admin::NotesScreen::FilesComponent

      # `user`: the draft is the signed-in person's own. `sessionStorage`
      # belongs to the tab, not to the session, so without it the next person
      # to sign in on the same tab would be handed the last one's unsent text.
      def form_data
        { controller: "admin--note-composer", turbo_frame: "notes", note_composer: key,
          "admin--note-composer-key-value": key, "admin--note-composer-mentions-url-value": mentions_url,
          "admin--note-composer-user-value": Current.user&.id, "admin--note-composer-edit-value": unsaved.present?,
          action: "turbo:submit-start->admin--note-composer#sending turbo:submit-end->admin--note-composer#sent", messages: script_messages }
      end

      # On a line of its own, ending the line: `test/lib/script_messages_test.rb`
      # reads the literal keys of a `messages_data(...)` call only when the
      # closing bracket is followed by a line end, a comma or another bracket.
      def script_messages = messages_data("notes.script.mentions.none", "notes.script.mentions.count", "notes.script.files.too_many", "notes.script.files.too_big", "notes.script.files.remove")
    end
  end
end
