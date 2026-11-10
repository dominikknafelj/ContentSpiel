module Admin
  module Ui
    # A box of the caller's words, in one of four tones: warn (something is
    # unsafe or needs a look), ok (it worked), danger (a refusal or a broken
    # link) and neutral (why something is as it is). The words are the
    # block; a link inside is the caller's.
    #
    # Its role follows the tone: warn and danger are an alert, read out at
    # once; ok is a status, read out when the reader is free; neutral is a
    # note, read where it stands. `role: nil` writes none: for a notice
    # inside a live region, where the region speaks and a role of the
    # notice's own would have it heard twice, and for a box with no live
    # role that is read where it stands (a dialog's line, a list's standing
    # warning). Any other role a caller names is written as
    # given.
    #
    # Warn alone keeps an edge: the tint and its edge are the thing on
    # paper and surface alike, where the other tints read as grounds of their
    # own. Every tone is `rounded-card` and none has a shadow: a notice
    # stands in its card or its page, never above it. Compact is the
    # 13px size for a notice in a narrow column (the sign-in panel's, a
    # card's line). Anything else the caller hands it (`id`, `data`, a
    # class) goes on the box, a class added to the notice's own.
    class NoticeComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "A box of the caller's words whose role follows its tone (alert, status or note), or none inside a live region or for a box read where it stands; it takes no focus.",
        motion: :none,
        content_edges: %i[short long],
        widths: :from_container,
        interface: %i[tone size role],
        limits: [
          "It says only what the caller hands it; a link inside is the caller's.",
          "It offers no dismissal: a notice stays until its cause is gone."
        ],
        states: %i[warn ok danger neutral compact],
        keys: [],
        slots: [],
        controller: nil
      )

      CLASS = "rounded-card".freeze
      TONES = {
        warn: "border border-warn bg-warn-tint text-warn-ink",
        ok: "bg-ok-tint text-ok-ink",
        danger: "bg-danger-tint text-danger-ink",
        neutral: "bg-sunken text-dim"
      }.freeze
      SIZES = { regular: "px-3 py-2 text-sm", compact: "px-3 py-2.5 text-small leading-normal" }.freeze
      ROLES = { warn: "alert", danger: "alert", ok: "status", neutral: "note" }.freeze

      # The box's classes alone, for a box that must stand empty and hidden
      # until a script fills it (a dialog's notes warning): the component
      # draws nothing without words, and such a box gives its role, if any,
      # itself.
      def self.classes(tone, size: :regular)
        raise ArgumentError, "unknown notice tone #{tone.inspect}" unless TONES.key?(tone)
        raise ArgumentError, "unknown notice size #{size.inspect}" unless SIZES.key?(size)

        [ CLASS, TONES.fetch(tone), SIZES.fetch(size) ].join(" ")
      end

      def initialize(tone:, size: :regular, role: :default, **html)
        @classes = self.class.classes(tone, size: size)
        @role = role == :default ? ROLES.fetch(tone) : role
        @html = html
      end

      # A notice with no words would be an empty alert a screen reader still
      # announces, so it draws nothing.
      def render? = content.present?

      def call
        tag.div(content, **@html, role: @role, class: [ @classes, @html[:class] ].compact.join(" "))
      end
    end
  end
end
