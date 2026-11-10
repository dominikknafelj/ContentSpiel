module Admin
  module Ui
    # The mark beside an audit sentence: who did it, the same in the audit
    # log's rows, the dashboard's "What changed recently" and Trash's
    # "Trashed" column, so one person looks the same in all three. It reads
    # the sentence's actor facts (`Audit::Sentence::Actor`) and draws, in a
    # 28px slot (`size: :lg`) or a 22px one (`:sm`, a dense row's):
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
        interface: %i[actor size],
        limits: [
          "It draws one mark and never the actor's name.",
          "It draws in a 28px or a 22px slot.",
          "A deleted user's circle is empty, because an event records no name to draw letters from."
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
        sm: "flex size-[22px] shrink-0 items-center justify-center"
      }.freeze
      # The System chip that fits each slot.
      CHIP_SIZES = { lg: :regular, sm: :xsmall }.freeze

      def initialize(actor:, size: :lg)
        raise ArgumentError, "unknown actor avatar size #{size.inspect}" unless SLOTS.key?(size)

        @actor = actor
        @size = size
      end

      def call
        if actor.none then tag.span(class: slot, aria: { hidden: true })
        elsif actor.user then render(AvatarComponent.new(initials: initials, size: @size, tone: actor.you ? :own : :other))
        elsif actor.user_id then render(AvatarComponent.new(initials: "", size: @size, tone: :empty))
        else tag.span(render(IconChipComponent.new(icon: :settings, family: :neutral, size: CHIP_SIZES.fetch(@size))), class: slot, aria: { hidden: true })
        end
      end

      private

      attr_reader :actor

      def slot = SLOTS.fetch(@size)

      # The two letters of a user's circle.
      def initials = ::PersonName.initials(::PersonName.of(actor.user))
    end
  end
end
