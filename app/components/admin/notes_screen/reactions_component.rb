module Admin
  module NotesScreen
    # A message's reactions (notes spec §4.5, handoff "Reaction chip" and its
    # decisions 22-24): a chip per emoji in use, drawn like a tag chip -- the
    # emoji and a mono count -- with the accent tint for the viewer's own and
    # the people who reacted in its title; a press gives the viewer's reaction
    # or takes it back. Then the chip that opens the set to add from: the
    # composer's own popover (its panel and its buttons,
    # `ComposerComponent::EMOJI_PANEL_CLASS`, over `Notes::EMOJI`), here with
    # each emoji a submit.
    #
    # THREE STATES (`state`).
    # - `:open`: the chips are buttons and the add chip is there. The add chip
    #   shows at rest only under a message that has reactions; otherwise on
    #   hover or keyboard focus of the message (`group/note` on the message,
    #   `:focus-within`), and while its set is open. It keeps its place when
    #   it is not shown, so nothing moves under the pointer. For touch the
    #   message's "⋯" menu has "React", which opens the same set
    #   (`admin--note-reactions#open`).
    # - `:disabled`, while the message is being edited: everything stays,
    #   under the edit form, at half opacity, and nothing can be pressed --
    #   the buttons are `disabled`, so the keyboard skips them. (A press would
    #   be answered with the thread drawn again, without the form.)
    # - `:closed`, in a resolved thread: the chips are read, not pressed --
    #   no button, no add chip. `Notes::React` refuses there too.
    #
    # A press says the state it is meant to reach (`on`), never "toggle": a
    # request sent twice ends where the person meant (`Notes::React`).
    #
    # Every button is a submit of a small Turbo form into the notes frame; no
    # autosave form. The forms stand below the message's text or beside its
    # edit form, inside no other form. Where the set opens, Escape and a
    # press outside it are `admin--note-reactions`' (on the message).
    #
    # Accent here means "yours": the one control the handoff gives the accent
    # tint to for something other than "unread for you".
    #
    # A chip's accessible name is words -- the emoji's name, how many, whether
    # one is the viewer's, and who -- because a glyph and a number say little
    # to a screen reader, and a `title` nothing to most of them.
    #
    # The reactions come from the listing (`Notes::Listing#reactions_of`, read
    # once for the whole thread), and so do the names: nothing here asks the
    # database per message.
    class ReactionsComponent < Admin::AdminComponent
      STATES = %i[open disabled closed].freeze

      CHIP = "inline-flex h-6 items-center gap-[5px] rounded-full border px-[9px]".freeze
      PRESSABLE = "cursor-pointer focus-visible:outline-2 focus-visible:outline-accent".freeze
      ADD_CHIP = "flex h-6 w-[30px] items-center justify-center rounded-full border border-line text-meta".freeze
      # Shown on hover or focus of the message, and while the set is open.
      AT_REST_HIDDEN = "opacity-0 group-hover/note:opacity-100 group-focus-within/note:opacity-100 open:opacity-100".freeze
      # Above the chip; below it when `admin--note-reactions` found no room
      # above inside the thread's scroll area (`data-side` on the <details>).
      PANEL_SIDE = "bottom-full mb-1.5 [[data-side=below]_&]:bottom-auto [[data-side=below]_&]:top-full [[data-side=below]_&]:mb-0 [[data-side=below]_&]:mt-1.5".freeze
      # Only one message's set is open at a time: `<details>` of one name
      # close each other, without a script.
      ADD_GROUP = "note-reaction-add".freeze

      def initialize(message:, listing:, viewer:, type:, view:, state: :open)
        raise ArgumentError, "unknown reactions state #{state.inspect}" unless STATES.include?(state)

        @message = message
        @listing = listing
        @viewer = viewer
        @type = type
        @view = view
        @state = state
      end

      # Nothing at all for a resolved thread's message nobody reacted to.
      def render? = !(closed? && groups.empty?)

      private

      attr_reader :message, :listing, :viewer

      def closed? = @state == :closed

      def disabled? = @state == :disabled

      # `[[emoji, [reaction, ...]], ...]` in the order each emoji first appeared.
      def groups = @groups ||= listing.reactions_of(message).group_by(&:emoji).to_a

      def mine?(reactions) = viewer.present? && reactions.any? { |reaction| reaction.user_id == viewer.id }

      # "Dana, Jonas", in the order they reacted. A reaction goes with its
      # user (the foreign key), so everyone named here exists.
      def people(reactions) = reactions.filter_map { |reaction| listing.users[reaction.user_id]&.display_name }.join(", ")

      # The emoji in words ("thumbs up"): the locale file's list, in the
      # set's own order.
      def name_of(emoji) = emoji_names.fetch(emoji, emoji)

      def emoji_names = @emoji_names ||= ::Notes::EMOJI.zip(Array(t(".names"))).to_h.compact

      def chip_name(emoji, reactions)
        t(mine?(reactions) ? ".chip_mine" : ".chip", name: name_of(emoji), count: reactions.size, people: people(reactions))
      end

      def chip_class(mine) = "#{CHIP} #{mine ? "border-accent bg-accent-tint" : "border-line bg-sunken"}"

      def count_class(mine) = "font-cs-mono text-[11px] #{mine ? "text-accent" : "text-dim"}"

      def add_class = [ ADD_CHIP, PRESSABLE, "list-none hover:bg-sunken [&::-webkit-details-marker]:hidden" ].join(" ")

      def path
        helpers.admin_record_note_message_reactions_path(*helpers.note_args(listing.container), message.thread_id, message,
          **{ view: (@view unless @view == "editor"), **helpers.admin_url_options }.compact)
      end

      def panel_class = "#{Admin::NotesScreen::ComposerComponent::EMOJI_PANEL_CLASS} #{PANEL_SIDE}"

      def emoji_class = Admin::NotesScreen::ComposerComponent::EMOJI_BUTTON_CLASS
    end
  end
end
