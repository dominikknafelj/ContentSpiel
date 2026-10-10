module Admin
  module Ui
    # A person as a round circle with their initials: THE ONE DRAWING of it
    # (the notes handoff's "Message" and "Thread row", the presence handoff's
    # item 1, which calls it "the existing actor avatar"). Notes draws its
    # authors through it (`Admin::NotesScreen::AvatarComponent`, which knows
    # who the viewer is and what a deleted user is called) and presence the
    # people on a record (`Admin::PresenceScreen::PeopleComponent`).
    #
    # It is told the initials (`PersonName.initials`, drawn upper-case by the
    # style) and knows nothing of users. Decoration only: whoever draws it
    # names the person beside it or on the element around it, so it is hidden
    # from a screen reader.
    #
    # `size`: `:md` is 24px with 9px letters, `:sm` 20px with 8px.
    # `tone`: `:other` is anybody (sunken, a strong line, ink); `:own` is the
    # viewer in a note (filled ink); `:away` is someone whose tab is hidden or
    # idle (presence handoff 4: no fill, the plain line, meta letters -- never
    # a lower opacity, which would take the letters below contrast).
    # `ring`: a 2px ring in the paper colour, for circles that overlap.
    class AvatarComponent < Admin::AdminComponent
      SIZES = { md: "size-6 text-[9px]", sm: "size-5 text-[8px]" }.freeze
      TONES = { other: "border border-line-strong bg-sunken text-ink", own: "bg-ink text-paper", away: "border border-line bg-paper text-meta" }.freeze

      def initialize(initials:, size:, tone: :other, ring: false)
        @initials = initials
        @size = SIZES.fetch(size)
        @tone = TONES.fetch(tone)
        @ring = ring
      end

      def call
        tag.span(@initials, aria: { hidden: true },
          class: class_names("flex shrink-0 items-center justify-center rounded-full font-cs-mono font-medium uppercase leading-none", @size, @tone, "ring-2 ring-paper": @ring))
      end
    end
  end
end
