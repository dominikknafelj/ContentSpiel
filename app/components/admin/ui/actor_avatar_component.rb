module Admin
  module Ui
    # The mark of who did or wrote something: THE ONE RULE that turns a user
    # into a circle, so one person looks the same everywhere. Two forms ask
    # it. `actor:` is an audit sentence's actor facts
    # (`Audit::Sentence::Actor`): the audit log's rows, the dashboard's "What
    # changed recently" and Trash's "Trashed" column. `user:` with `viewer:`
    # is a person a note names (a message's author, a thread row's, an inbox
    # row's, an open thread's writers), where a nil user is one who has been
    # deleted: a note always had an author, so neither System nor nobody
    # comes from that form. It draws, in a 28px slot (`size: :lg`), a 26px
    # one (`:md`, a note row's) or a 22px one (`:sm`, a dense row's or a
    # message's):
    #
    #   a user        `AvatarComponent` at the slot's size, two letters from
    #                 `PersonName.initials` of `PersonName.of(user)` (the rule
    #                 notes and presence use); the viewer's own in `:own`, as
    #                 notes draws it, anyone else in `:other`
    #   a deleted     the `:empty` circle (a hairline, no letters, never
    #   user          dashed: that is away): an event records no user's
    #                 name (`actor_label` is a token's name or the visitor's),
    #                 so there are no letters to draw
    #   System        not a person: the neutral settings icon chip, centred in
    #                 the slot
    #   nobody        (a failed sign-in, a visitor) no circle, an empty slot of
    #                 the same width, so the sentences stay aligned
    #
    # Decoration only: the sentence beside it names the actor.
    class ActorAvatarComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "Decoration with no role, name or focus: the circle, the chip and the empty slot are hidden from a screen reader, and the sentence beside it names the actor.",
        motion: :none,
        content_edges: %i[none missing],
        widths: :fixed_width,
        interface: %i[actor user viewer size],
        limits: [
          "It draws one mark and never the actor's name.",
          "It draws in a 28px, a 26px or a 22px slot.",
          "It takes an audit actor or a user, never both.",
          "A deleted user's circle is empty, because there is no name left to draw letters from."
        ],
        states: %i[user own deleted_user system nobody],
        keys: [],
        slots: [],
        controller: nil,
        keyboard: "It takes no focus: a circle or chip hidden from a screen reader, drawn beside the sentence that names the actor."
      )

      # A size's slot, which the empty slot and the System chip stand in at
      # the circle's own width, so the sentences beside them stay aligned.
      SLOTS = {
        lg: "flex size-7 shrink-0 items-center justify-center",
        md: "flex size-[26px] shrink-0 items-center justify-center",
        sm: "flex size-[22px] shrink-0 items-center justify-center"
      }.freeze
      # The System chip that fits each slot.
      CHIP_SIZES = { lg: :regular, md: :small, sm: :xsmall }.freeze

      def initialize(actor: nil, user: nil, viewer: nil, size: :lg)
        raise ArgumentError, "unknown actor avatar size #{size.inspect}" unless SLOTS.key?(size)
        raise ArgumentError, "an actor avatar takes an audit actor or a user, not both" if actor && (user || viewer)

        @actor = actor
        @user = actor ? actor.user : user
        @own = actor ? actor.you : viewer.present? && user.present? && user.id == viewer.id
        @size = size
      end

      def call
        case mark
        when :nobody then tag.span(class: slot, aria: { hidden: true })
        when :user then render(AvatarComponent.new(initials: initials, size: @size, tone: @own ? :own : :other))
        when :deleted then render(AvatarComponent.new(initials: "", size: @size, tone: :empty))
        else tag.span(render(IconChipComponent.new(icon: :settings, family: :neutral, size: CHIP_SIZES.fetch(@size))), class: slot, aria: { hidden: true })
        end
      end

      private

      # Which of the four marks. An event's `user_id` outlives its user, so a
      # user_id with no user is a deleted one; in the `user:` form a nil user
      # is.
      def mark
        if @actor&.none then :nobody
        elsif @user then :user
        elsif @actor.nil? || @actor.user_id then :deleted
        else :system
        end
      end

      def slot = SLOTS.fetch(@size)

      # The two letters of a user's circle: `PersonName.of`, the short name
      # notes and presence use, so a person with no name gets the letters of
      # the part of their address before the at sign.
      def initials = ::PersonName.initials(::PersonName.of(@user))
    end
  end
end
