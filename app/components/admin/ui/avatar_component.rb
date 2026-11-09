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
    # ink letters); `:empty` is nobody to name, a deleted user or the system
    # (a solid hairline on the surface, no letters and no hue: the dashed edge
    # means only away).
    # `here`: a 1.5px people ring inside the circle, for someone who has the
    # record open now (an inset ring, so the circle keeps its size).
    # There is no ring outside the circle: circles in a stack stand 2px apart
    # and never overlap, since two letters reach about 19px into a 22px
    # circle and a circle over the one before would cover its second letter.
    # The same classes are `app/javascript/ui/avatar.js`'s, which draws the
    # circle in the browser.
    class AvatarComponent < Admin::AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "Decoration hidden from a screen reader, with no role and no focus: whoever draws it names the person beside it.",
        motion: :none,
        content_edges: %i[short],
        widths: :fixed_width,
        interface: %i[initials size tone here],
        limits: [
          "It is told the initials and knows nothing of users.",
          "It draws three sizes and five tones, and anything else is refused.",
          "Its letters are 11px at every size."
        ],
        states: %i[other own away more empty here],
        keys: %w[more many],
        slots: [],
        controller: nil
      )

      SIZES = { lg: "size-7", md: "size-[26px]", sm: "size-[22px]" }.freeze
      TONES = {
        other: "bg-people-tint text-people",
        own: "bg-people text-surface",
        away: "border-[1.5px] border-dashed border-field-line bg-surface text-meta",
        more: "bg-sunken text-ink",
        empty: "border border-field-line bg-surface"
      }.freeze
      HERE = "inset-ring-[1.5px] inset-ring-people"
      LETTERS = "flex shrink-0 items-center justify-center rounded-full text-count font-semibold uppercase leading-none"

      # Above this many the "+N" circle reads "9+": three characters would not
      # stand in it.
      MORE_LIMIT = 9

      # The "+N" circle's letters.
      def self.more_label(count)
        count > MORE_LIMIT ? I18n.t("admin.components.ui.avatar.many") : I18n.t("admin.components.ui.avatar.more", count: count)
      end

      def initialize(initials:, size:, tone: :other, here: false)
        @initials = initials
        @size = SIZES.fetch(size)
        @tone = TONES.fetch(tone)
        @here = here && HERE
      end

      def call
        tag.span(@initials, aria: { hidden: true },
          class: class_names(LETTERS, @size, @tone, @here))
      end
    end
  end
end
