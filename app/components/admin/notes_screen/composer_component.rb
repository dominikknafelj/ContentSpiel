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
    class ComposerComponent < Admin::AdminComponent
      POPOVER_SIDE = "top-full mt-1.5 [[data-note-part=reply]_&]:top-auto [[data-note-part=reply]_&]:bottom-full [[data-note-part=reply]_&]:mb-1.5 [[data-note-part=reply]_&]:mt-0".freeze
      TOOL_CLASS = "flex size-7 cursor-pointer items-center justify-center rounded-cs text-dim hover:bg-sunken hover:text-ink focus-visible:outline-2 focus-visible:outline-accent".freeze

      def initialize(url:, key:, label:, submit:, mentions_url:, method: :post, body: "", names: {}, errors: [], hidden: {}, rows: 2)
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
      end

      private

      attr_reader :url, :key, :label, :submit, :mentions_url, :method, :body, :names, :errors, :hidden, :rows

      def field_id = "note-field-#{key}"

      def form_data
        { controller: "admin--note-composer", turbo_frame: "notes", note_composer: key,
          "admin--note-composer-key-value": key, "admin--note-composer-mentions-url-value": mentions_url,
          action: "turbo:submit-end->admin--note-composer#sent", messages: script_messages }
      end

      # On a line of its own, ending the line: `test/lib/script_messages_test.rb`
      # reads the literal keys of a `messages_data(...)` call only when the
      # closing bracket is followed by a line end, a comma or another bracket.
      def script_messages = messages_data("notes.script.mentions.none", "notes.script.mentions.count")
    end
  end
end
