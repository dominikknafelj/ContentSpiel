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
    # TWO PLACES (`place`), one of which is drawn (the handoff's decision 26).
    # - `:row`, under the text, for a message that HAS reactions: its chips,
    #   and the add chip at the end of the row, always on show.
    # - `:meta`, in the message's meta line just left of the "⋯" menu, for a
    #   message nobody reacted to: a 24px smile control, shown on hover or
    #   keyboard focus of the message (`group/note` on the message,
    #   `:focus-within`) and while its set is open. Such a message has no row
    #   at all, so the control costs no height at rest. The set hangs from its
    #   right edge there, since the control stands at the end of the line.
    # For touch the message's "⋯" menu has "React", which opens the same set
    # wherever it stands (`admin--notes--reactions#open`).
    #
    # THREE STATES (`state`).
    # - `:open`: the chips are buttons and the way to the set is there.
    # - `:disabled`, while the message is being edited: the row stays, under
    #   the edit form, at half opacity, and nothing can be pressed -- the
    #   buttons are `disabled`, so the keyboard skips them. (A press would be
    #   answered with the thread drawn again, without the form.) The
    #   meta-line control is not drawn.
    # - `:closed`, in a resolved thread: the chips are read, not pressed --
    #   no button, no add chip, no meta-line control. `Notes::React` refuses
    #   there too.
    #
    # A press says the state it is meant to reach (`on`), never "toggle": a
    # request sent twice ends where the person meant (`Notes::React`).
    #
    # Every button is a submit of a small Turbo form into the notes frame; no
    # autosave form. The forms stand below the message's text or beside its
    # edit form, inside no other form. Where the set opens, Escape and a
    # press outside it are `admin--notes--reactions`' (on the message).
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
      PLACES = %i[row meta].freeze

      CHIP = "inline-flex h-6 items-center gap-[5px] rounded-full border px-[9px]".freeze
      PRESSABLE = "cursor-pointer focus-visible:outline-2 focus-visible:outline-accent".freeze
      ADD_CHIP = "flex h-6 w-[30px] items-center justify-center rounded-full border border-line text-meta".freeze
      META_CONTROL = "flex size-6 items-center justify-center rounded-cs text-meta hover:text-ink".freeze
      # Shown on hover or focus of the message, and while the set is open.
      AT_REST_HIDDEN = "opacity-0 group-hover/note:opacity-100 group-focus-within/note:opacity-100 open:opacity-100".freeze
      # Above the chip; below it when `admin--notes--reactions` found no room
      # above inside the thread's scroll area (`data-side` on the <details>).
      PANEL_SIDE = "bottom-full mb-1.5 [[data-side=below]_&]:bottom-auto [[data-side=below]_&]:top-full [[data-side=below]_&]:mb-0 [[data-side=below]_&]:mt-1.5".freeze
      # Only one message's set is open at a time: `<details>` of one name
      # close each other, without a script.
      ADD_GROUP = "note-reaction-add".freeze

      def initialize(message:, listing:, viewer:, view:, state: :open, place: :row)
        raise ArgumentError, "unknown reactions state #{state.inspect}" unless STATES.include?(state)
        raise ArgumentError, "unknown reactions place #{place.inspect}" unless PLACES.include?(place)

        @message = message
        @listing = listing
        @viewer = viewer
        @view = view
        @state = state
        @place = place
      end

      # The row for a message with reactions; the meta-line control for one
      # without, while the thread is open and the message is not being edited.
      def render? = meta? ? @state == :open && groups.empty? : groups.any?

      private

      attr_reader :message, :listing, :viewer

      def meta? = @place == :meta

      def closed? = @state == :closed

      def disabled? = @state == :disabled

      # `[[emoji, [reaction, ...]], ...]` in the order each emoji first appeared.
      def groups = @groups ||= listing.reactions_of(message).group_by(&:emoji).to_a

      def mine?(reactions) = viewer.present? && reactions.any? { |reaction| reaction.user_id == viewer.id }

      # "Dana, Jonas", in the order they reacted. A reaction goes with its
      # user (the foreign key), so everyone named here exists.
      def people(reactions) = reactions.filter_map { |reaction| listing.users[reaction.user_id]&.then { |user| ::Notes.name_of(user) } }.join(", ")

      # The emoji in words ("thumbs up"): the locale file's list, in the
      # set's own order.
      def name_of(emoji) = emoji_names.fetch(emoji, emoji)

      def emoji_names = @emoji_names ||= ::Notes::EMOJI.zip(Array(t(".names"))).to_h.compact

      def chip_name(emoji, reactions)
        t(mine?(reactions) ? ".chip_mine" : ".chip", name: name_of(emoji), count: reactions.size, people: people(reactions))
      end

      def chip_class(mine) = "#{CHIP} #{mine ? "border-accent bg-accent-tint" : "border-line bg-sunken"}"

      def count_class(mine) = "font-cs-mono text-[11px] #{mine ? "text-accent" : "text-dim"}"

      def add_class = [ meta? ? META_CONTROL : ADD_CHIP, PRESSABLE, "list-none hover:bg-sunken [&::-webkit-details-marker]:hidden" ].join(" ")

      def add_icon_size = meta? ? "size-4" : "size-3"

      def path
        helpers.admin_record_note_message_reactions_path(*helpers.note_args(listing.container), message.thread_id, message,
          **{ view: (@view unless @view == "editor"), **helpers.admin_url_options }.compact)
      end

      def panel_class = "#{Admin::NotesScreen::ComposerComponent::EMOJI_PANEL_CLASS} #{meta? ? "right-0" : "left-0"} #{PANEL_SIDE}"

      def emoji_class = Admin::NotesScreen::ComposerComponent::EMOJI_BUTTON_CLASS
    end
  end
end
