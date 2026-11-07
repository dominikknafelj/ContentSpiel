module Admin
  module Ui
    # A person as a round circle with their initials: THE ONE DRAWING of it,
    # in a note's message and thread row and among a record's people. Notes draws its
    # authors through it (`Admin::NotesScreen::AvatarComponent`, which knows
    # who the viewer is and what a deleted user is called) and presence the
    # people on a record (`Admin::PresenceScreen::PeopleComponent`).
    #
    # It is told the initials (`PersonName.initials`, drawn upper-case by the
    # style) and knows nothing of users. Decoration only: whoever draws it
    # names the person beside it or on the element around it, so it is hidden
    # from a screen reader.
    #
    # `size`: `:lg` is 28px with 11px letters (an activity row's actor, on the
    # dashboard and in the audit log), `:md` 24px with 9px, `:sm` 20px with 8px.
    # `tone`: `:other` is anybody (sunken, a strong line, ink); `:own` is the
    # viewer in a note (filled ink); `:away` is someone whose tab is hidden or
    # idle (no fill, the plain line, meta letters -- never
    # a lower opacity, which would take the letters below contrast).
    # `ring`: a 2px ring in the colour of what the circles stand on, for
    # circles that overlap: `:paper` (an editor's header) or `:surface` (the
    # media panel).
    class AvatarComponent < Admin::AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "Decoration hidden from a screen reader, with no role and no focus: whoever draws it names the person beside it.",
        motion: :none,
        content_edges: %i[short],
        widths: :fixed,
        interface: %i[initials size tone ring],
        limits: [
          "It is told the initials and knows nothing of users.",
          "It draws three sizes, three tones and two rings, and anything else is refused."
        ],
        states: %i[other own away],
        keys: [],
        slots: [],
        controller: nil
      )

      SIZES = { lg: "size-7 text-count", md: "size-6 text-[9px]", sm: "size-5 text-[8px]" }.freeze
      TONES = { other: "border border-line-strong bg-sunken text-ink", own: "bg-ink text-paper", away: "border border-line bg-paper text-meta" }.freeze

      RINGS = { paper: "ring-2 ring-paper", surface: "ring-2 ring-surface" }.freeze

      def initialize(initials:, size:, tone: :other, ring: nil)
        @initials = initials
        @size = SIZES.fetch(size)
        @tone = TONES.fetch(tone)
        @ring = ring && RINGS.fetch(ring)
      end

      def call
        tag.span(@initials, aria: { hidden: true },
          class: class_names("flex shrink-0 items-center justify-center rounded-full font-medium uppercase leading-none", @size, @tone, @ring))
      end
    end
  end
end
