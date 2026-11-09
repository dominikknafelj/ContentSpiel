module Admin
  module Ui
    # The mark beside an audit sentence: who did it, in a 28px slot, the same
    # in the audit log's rows and the dashboard's "What changed recently", so
    # one person looks the same in both. It reads the sentence's actor facts
    # (`Audit::Sentence::Actor`) and draws:
    #
    #   a user        `AvatarComponent` at `:lg`, two letters from
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
        interface: %i[actor],
        limits: [
          "It draws one mark in a 28px slot and never the actor's name.",
          "A deleted user's circle is empty, because an event records no name to draw letters from."
        ],
        states: %i[user own deleted_user system nobody],
        keys: [],
        slots: [],
        controller: nil
      )

      SLOT = "flex size-7 shrink-0 items-center justify-center".freeze

      def initialize(actor:)
        @actor = actor
      end

      def call
        if actor.none then tag.span(class: SLOT, aria: { hidden: true })
        elsif actor.user then render(AvatarComponent.new(initials: initials, size: :lg, tone: actor.you ? :own : :other))
        elsif actor.user_id then render(AvatarComponent.new(initials: "", size: :lg, tone: :empty))
        else tag.span(render(IconChipComponent.new(icon: :settings, family: :neutral)), class: SLOT, aria: { hidden: true })
        end
      end

      private

      attr_reader :actor

      # The two letters of a user's circle.
      def initials = ::PersonName.initials(::PersonName.of(actor.user))
    end
  end
end
