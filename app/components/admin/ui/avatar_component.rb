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
    # `size`: `:lg` is 28px (an activity row's actor), `:md` 26px (the
    # editor header's people, an inbox row, the hold strip) and `:sm` 22px (a
    # row's, a tile's, a message's): the letters are 11px, weight 600, at
    # every size, because two of them need 22px to stand 3px clear of the edge.
    # `tone`: `:other` is a colleague (the people tint, people letters);
    # `:own` is the viewer (the solid people fill, surface letters); `:away`
    # is someone whose tab is hidden or idle (the surface, meta letters and a
    # dashed edge -- the shape says it, never a lower opacity, which would
    # take the letters below contrast); `:more` is the "+N" circle (sunken,
    # ink letters).
    # `here`: a 1.5px people ring inside the circle, for someone who has the
    # record open now (an inset ring, so it stays inside the 2px ring below).
    # `ring`: a 2px ring outside the circle in the colour of what the circles
    # stand on, for circles that overlap: `:paper`, `:surface`, or `:ground`,
    # which reads `--admin-avatar-ground` from the stylesheet where the
    # ground is a rule's and not a token's. The same classes are
    # `app/javascript/ui/avatar.js`'s, which draws the circle in the browser.
    class AvatarComponent < Admin::AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "Decoration hidden from a screen reader, with no role and no focus: whoever draws it names the person beside it.",
        motion: :none,
        content_edges: %i[short],
        widths: :fixed_width,
        interface: %i[initials size tone ring here],
        limits: [
          "It is told the initials and knows nothing of users.",
          "It draws three sizes, four tones and three rings, and anything else is refused.",
          "Its letters are 11px at every size."
        ],
        states: %i[other own away more here],
        keys: %w[more many],
        slots: [],
        controller: nil
      )

      SIZES = { lg: "size-7", md: "size-[26px]", sm: "size-[22px]" }.freeze
      TONES = {
        other: "bg-people-tint text-people",
        own: "bg-people text-surface",
        away: "border-[1.5px] border-dashed border-field-line bg-surface text-meta",
        more: "bg-sunken text-ink"
      }.freeze
      RINGS = { paper: "ring-2 ring-paper", surface: "ring-2 ring-surface", ground: "ring-2 ring-(--admin-avatar-ground)" }.freeze
      HERE = "inset-ring-[1.5px] inset-ring-people"
      LETTERS = "flex shrink-0 items-center justify-center rounded-full text-count font-semibold uppercase leading-none"

      # Above this many the "+N" circle reads "9+": three characters would not
      # stand in it.
      MORE_LIMIT = 9

      # The "+N" circle's letters.
      def self.more_label(count)
        count > MORE_LIMIT ? I18n.t("admin.components.ui.avatar.many") : I18n.t("admin.components.ui.avatar.more", count: count)
      end

      def initialize(initials:, size:, tone: :other, ring: nil, here: false)
        @initials = initials
        @size = SIZES.fetch(size)
        @tone = TONES.fetch(tone)
        @ring = ring && RINGS.fetch(ring)
        @here = here && HERE
      end

      def call
        tag.span(@initials, aria: { hidden: true },
          class: class_names(LETTERS, @size, @tone, @here, @ring))
      end
    end
  end
end
