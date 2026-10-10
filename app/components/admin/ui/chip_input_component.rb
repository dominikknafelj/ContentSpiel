module Admin
  module Ui
    # A multi-value input that shows each value as a removable chip, with
    # autocomplete (design pass round 2, handoff §4.1 "Tags"): the post
    # editor's tags and related posts. Replaces the comma-separated tag text
    # field and the related-posts list-plus-search.
    #
    # The form's source of truth is real controls, never the chips' text: one
    # hidden input per chip (`name` is an array name such as
    # `post[tag_names][]`) plus a blank sentinel ahead of them, so a list the
    # editor emptied still submits the key and saves as empty -- absent would
    # mean "this PATCH says nothing about it" (`Admin::EditorScreen::RelatedPostsComponent`'s
    # own class comment has the contract). `admin--ui--chip-input` adds and removes
    # those inputs and dispatches a bubbling `change` from the sentinel, which
    # the form's autosave (`admin--autosave`) already listens for; typing in the
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
    # (`admin--save-bar#snapshot`), so the sentinel and every chip's input are
    # marked -- adding a chip is then "1 unsaved change", removing it likewise,
    # and the sentinel's bubbling `change` makes the footer look. Typing in the
    # search box still counts as nothing: its text input has no name and its
    # events are swallowed.
    #
    # In a view-only editor the surrounding `<fieldset disabled>` disables the
    # input and every remove button, so the whole component is inert.
    class ChipInputComponent < AdminComponent
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

      def chip_class(chip)
        [ "admin-chip inline-flex max-w-full items-center gap-1.5 rounded-full py-0.5 pl-2.5 pr-1 text-sm",
          chip[:invalid] ? "bg-danger-tint text-danger-ink" : "bg-sunken text-ink" ]
      end

      # `aria-describedby` on the input: the help line, plus the error slot
      # when there are errors (the slot itself is always rendered, empty, so
      # autosave has something to replace).
      def described_by = [ (help_id if help), (errors_id if errors.any?) ].compact.join(" ").presence

      private

      attr_reader :name, :id, :label, :search_url, :chips, :create, :noun, :placeholder, :errors, :hidden_note, :help, :single, :exclude, :lowercase, :max_length, :track
    end
  end
end
