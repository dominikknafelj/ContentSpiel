module Admin
  module NotesScreen
    # A message's reactions (notes spec §4.5, handoff "Reaction chip"): a chip
    # per emoji in use, drawn like a tag chip -- the emoji and a mono count --
    # with the accent tint for the viewer's own, and the people who reacted in
    # its title; a press toggles the viewer's. Then the chip that opens the
    # set to add from: the composer's own popover (its panel and its buttons,
    # `ComposerComponent::EMOJI_PANEL_CLASS`, over `Notes::EMOJI`), here with
    # each emoji a submit.
    #
    # Every button is a submit of a small Turbo form into the notes frame; no
    # script, and no autosave form. The forms stand below the message's text,
    # inside no other form (not the reply's, not an edit's).
    #
    # Accent here means "yours": the one control the handoff gives the accent
    # tint to for something other than "unread for you".
    #
    # The reactions come from the listing (`Notes::Listing#reactions_of`, read
    # once for the whole thread), and so do the names: nothing here asks the
    # database per message.
    class ReactionsComponent < Admin::AdminComponent
      CHIP = "inline-flex h-6 cursor-pointer items-center gap-[5px] rounded-full border px-[9px] focus-visible:outline-2 focus-visible:outline-accent".freeze
      # Only one message's set is open at a time: `<details>` of one name
      # close each other, without a script.
      ADD_GROUP = "note-reaction-add".freeze

      def initialize(message:, listing:, viewer:, type:, view:)
        @message = message
        @listing = listing
        @viewer = viewer
        @type = type
        @view = view
      end

      private

      attr_reader :message, :listing, :viewer

      # `[[emoji, [reaction, ...]], ...]` in the order each emoji first appeared.
      def groups = listing.reactions_of(message).group_by(&:emoji).to_a

      def mine?(reactions) = viewer.present? && reactions.any? { |reaction| reaction.user_id == viewer.id }

      # "Dana, Jonas", in the order they reacted. A reaction goes with its
      # user (the foreign key), so everyone named here exists.
      def names(reactions) = reactions.filter_map { |reaction| listing.users[reaction.user_id]&.display_name }.join(", ")

      def chip_class(mine) = "#{CHIP} #{mine ? "border-accent bg-accent-tint" : "border-line bg-sunken"}"

      def path
        helpers.admin_record_note_message_reactions_path(*helpers.note_args(listing.container), message.thread_id, message,
          **{ view: (@view unless @view == "editor"), **helpers.admin_url_options }.compact)
      end

      def panel_class = "#{Admin::NotesScreen::ComposerComponent::EMOJI_PANEL_CLASS} bottom-full mb-1.5"

      def emoji_class = Admin::NotesScreen::ComposerComponent::EMOJI_BUTTON_CLASS
    end
  end
end
