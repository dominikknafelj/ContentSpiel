module Admin
  module Ui
    # A multi-value input that shows each value as a removable chip, with
    # autocomplete: the post editor's tags and related posts, and the group
    # editor's members.
    #
    # The form's source of truth is real controls, never the chips' text: one
    # hidden input per chip (`name` is an array name such as
    # `post[tag_names][]`) plus a blank sentinel ahead of them, so a list the
    # editor emptied still submits the key and saves as empty -- absent would
    # mean "this PATCH says nothing about it" (`Admin::EditorScreen::RelatedPostsComponent`'s
    # own class comment has the contract). `admin--ui--chip-input` adds and removes
    # those inputs and dispatches a bubbling `change` from the sentinel, which
    # the form's autosave (`admin--saving--autosave`) already listens for; typing in the
    # search box is swallowed at this component's root, so it never queues a
    # save by itself. The text input has no `name`, so it is never submitted.
    #
    # `chips:` is `[{ value:, label:, hint: nil, dot: nil, invalid: false }]`:
    # `hint` is the muted "· Draft" after the label, `dot` the Tailwind class
    # of a content-type dot (`Admin::Ui::ContentTypeDotComponent#mark_class`), and
    # `invalid` marks a chip the server refused (danger-tinted; the field's
    # error slot names it, rendered by this component from `errors:`).
    #
    # `search_url:` answers JSON rows -- either `{ value:, label:, hint: }`
    # (`Admin::TagSuggestionsController`) or the link-target shape
    # `{ id:, title:, status:, dot: }` (`Admin::LinkTargetsController`); the
    # controller reads both. `create: true` adds a "Create <noun> “typed”" row
    # when nothing matches exactly, and lets Enter or a comma commit the typed
    # text as a chip; without it only a suggestion can be chosen.
    #
    # `single: true` is a one-value field (a post-list block's tag filter): the
    # name is a plain scalar (`block[settings][tag]`, no `[]`) and the blank
    # sentinel ahead of the one chip makes the chip win when there is one -- a
    # repeated scalar name reads as its last occurrence -- and "" when there is
    # none. Choosing a suggestion replaces the chip it finds (`admin--ui--chip-input`'s
    # `single` value) instead of adding a second.
    #
    # `exclude:` lists values never offered as suggestions (a post's own id in
    # the related-posts field: `Posts::Save` would silently drop it). With
    # `lowercase: true` a chip made from typed text is lower-cased, because
    # the server stores the names that way (tags) and the chip should read as it
    # will after a reload. `max_length:` marks a chip longer than that as invalid
    # at once (danger tint, plus a visually hidden "(too long)" -- a chip is a
    # list item, which can't carry `aria-invalid`, and colour must not be the
    # only cue), where the server would refuse the
    # whole save (`Tag`'s length limit) and name it in the error slot.
    #
    # `track: true` is for a field inside an explicit-save form (the group
    # editor's members): the form's footer counts what the form would submit and
    # skips a hidden input unless it carries `data-save-bar-track`
    # (`admin--saving--save-bar#snapshot`), so the sentinel and every chip's input are
    # marked -- adding a chip is then "1 unsaved change", removing it likewise,
    # and the sentinel's bubbling `change` makes the footer look. Typing in the
    # search box still counts as nothing: its text input has no name and its
    # events are swallowed.
    #
    # In a view-only editor the surrounding `<fieldset disabled>` disables the
    # input and every remove button, so the whole component is inert.
    class ChipInputComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "A labelled combobox with a listbox of suggestions and a list of chips, each removable by a button named Remove and the chip; ArrowDown and Enter pick, Escape closes, Backspace in the empty field removes the last chip, and a polite status says what was added or removed.",
        motion: :none,
        content_edges: %i[none many long],
        widths: :from_container,
        interface: %i[name id label search_url chips create noun placeholder errors hidden_note help single exclude lowercase max_length track],
        limits: [
          "Its hidden inputs are what the form submits; the text input has no name and typing alone never saves.",
          "A noun it is handed has to have its two sentences under nouns, or its words are missing."
        ],
        states: %i[empty with_chips invalid hover focus],
        script_states: {
          suggesting: [ "test/system/admin/chip_input_test.rb", "typing, ArrowDown and Enter picks a suggestion as a chip, and it survives a reload" ],
          too_long: [ "test/system/admin/chip_input_test.rb", "a tag longer than the limit is tinted at once and the save names it in the error slot" ]
        },
        keys: %w[
          nouns.tag.no_matches nouns.tag.create nouns.user.no_matches nouns.user.create nouns.post.no_matches
          nouns.post.create remove invalid untitled too_long suggestions_label results search_failed already_added
          added removed
        ],
        slots: [],
        controller: "admin--ui--chip-input",
        keyboard: [ "test/system/admin/chip_input_test.rb", "a chip's remove button is reachable by keyboard, and focus lands on a neighbour" ]
      )

      # A chip's fixed look, which the audit log's subject chip draws too, and
      # its two grounds. `REMOVE_CLASS` is the chip's own × button.
      CHIP_CLASS = "admin-chip inline-flex max-w-full items-center gap-1.5 rounded-full py-0.5 pl-2.5 pr-1 text-sm".freeze
      CHIP_GROUND = "bg-sunken text-ink".freeze
      CHIP_INVALID = "bg-danger-tint text-danger-ink".freeze
      REMOVE_CLASS = "admin-chip__remove inline-flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-meta hover:bg-line hover:text-ink focus-visible:outline-2 focus-visible:outline-accent".freeze

      def initialize(name:, id:, label:, search_url:, chips: [], create: false, noun: "tag", placeholder: nil, errors: [], hidden_note: nil, help: nil, single: false, exclude: [], lowercase: false, max_length: nil, track: false)
        @name = name
        @id = id
        @label = label
        @search_url = search_url
        @chips = chips.map { |chip| chip.symbolize_keys }
        @create = create
        @noun = noun
        @placeholder = placeholder
        @errors = Array(errors)
        @hidden_note = hidden_note
        @help = help
        @single = single
        @exclude = Array(exclude).map(&:to_s)
        @lowercase = lowercase
        @max_length = max_length
        @track = track
      end

      def listbox_id = "#{id}-listbox"

      def errors_id = "#{id}-errors"

      def help_id = "#{id}-help"

      def status_id = "#{id}-status"

      def remove_label(chip) = t(".remove", label: chip[:label])

      # What `admin--ui--chip-input` says and writes into the page, by key
      # (`app/javascript/i18n/messages.js`): the same keys the server-rendered
      # chips above use, so a chip the script adds reads like one rendered here.
      # The noun is the caller's `noun:` (a key under `nouns`, each with the two
      # whole sentences that name it).
      def messages
        messages_data("components.ui.chip_input.nouns.#{noun}.no_matches", "components.ui.chip_input.nouns.#{noun}.create",
          "components.ui.chip_input.remove", "components.ui.chip_input.untitled", "components.ui.chip_input.too_long",
          "components.ui.chip_input.results", "components.ui.chip_input.search_failed", "components.ui.chip_input.already_added",
          "components.ui.chip_input.added", "components.ui.chip_input.removed", "components.ui.status_chip.labels.draft",
          "components.ui.status_chip.labels.scheduled")
      end

      # The `data:` a hidden input carries so the explicit-save footer counts it.
      def track_data = track ? { save_bar_track: true } : {}

      def chip_class(chip) = [ CHIP_CLASS, chip[:invalid] ? CHIP_INVALID : CHIP_GROUND ]

      # `aria-describedby` on the input: the help line, plus the error slot
      # when there are errors (the slot itself is always rendered, empty, so
      # autosave has something to replace).
      def described_by = [ (help_id if help), (errors_id if errors.any?) ].compact.join(" ").presence

      private

      attr_reader :name, :id, :label, :search_url, :chips, :create, :noun, :placeholder, :errors, :hidden_note, :help, :single, :exclude, :lowercase, :max_length, :track
    end
  end
end
