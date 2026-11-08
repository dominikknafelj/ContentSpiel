module Admin
  module Ui
    # A system's state, in a dot and a word: mail, the AI key, Test
    # connection's result, a system check. Not a record's state: a page's or
    # a post's is `StatusChipComponent`, whose Live and Scheduled fills belong
    # to publishing.
    #
    # ok, warn and danger are the role's tint with its dot and its ink; off
    # has no ground, a field-line edge, a hollow ring and dim words. Every
    # tone keeps a 1px edge (transparent but off's) so the four stand at one
    # height in a row. On the rail's ground a tint is no shape, so the dot
    # and the word carry the state there, and the word alone says it.
    #
    # `label:` and `detail:` are the caller's words. The detail is not part
    # of the chip: it follows it on the same line as small meta text after a
    # middle dot ("· added 2 Oct"), and the two stand in one plain inline
    # wrapper, so the state and its detail read as one phrase ("Key saved ·
    # added 2 Oct"), to a screen reader and in the page's text alike. A flex
    # wrapper would read them as separate lines. Anything else the caller
    # hands it (`data`, `id`, a class) goes on the root: the wrapper with a
    # detail, the chip without.
    class StateChipComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "Inline text: its word says the state; the dot is hidden. It has no role and takes no focus.",
        motion: :none,
        content_edges: %i[short long],
        widths: :fluid,
        interface: %i[tone label detail],
        limits: [
          "It cannot be pressed and takes no focus.",
          "It draws four tones; the word, never the colour, says the state.",
          "A detail is small meta text after the chip, never inside it.",
          "Anything else the caller hands it (data, id, a class) goes on its root: the wrapper with a detail, the chip without."
        ],
        states: %i[ok warn danger off],
        keys: [],
        slots: [],
        controller: nil,
        keyboard: [ "test/system/admin/settings_test.rb", "the rail's states are words a keyboard passes over: each row is one link, and no chip takes the focus" ]
      )

      TONES = %i[ok warn danger off].freeze

      CLASS = "admin-state-chip inline-flex shrink-0 items-center gap-1.5 rounded-cs border px-2 py-0.5 text-label".freeze
      GROUNDS = {
        ok: "border-transparent bg-ok-tint text-ok-ink",
        warn: "border-transparent bg-warn-tint text-warn-ink",
        danger: "border-transparent bg-danger-tint text-danger-ink",
        off: "border-field-line text-dim"
      }.freeze
      DOT = "size-1.5 shrink-0 rounded-full".freeze
      WRAPPER = "inline".freeze
      DETAIL = "text-small text-meta".freeze
      DOTS = { ok: "bg-ok", warn: "bg-warn", danger: "bg-danger", off: "border border-field-line" }.freeze

      def initialize(tone:, label:, detail: nil, **html)
        raise ArgumentError, "unknown state chip tone #{tone.inspect}" unless TONES.include?(tone)

        @tone = tone
        @label = label
        @detail = detail
        @html = html
      end

      def call
        return chip(**@html) if @detail.blank?

        tag.span(**@html, class: [ WRAPPER, @html[:class] ].compact.join(" ")) do
          safe_join([ chip, " ", tag.span("· #{@detail}", class: DETAIL) ])
        end
      end

      private

      def chip(**html)
        tag.span(**html, class: [ CLASS, GROUNDS.fetch(@tone), html[:class] ].compact.join(" "), data: { **html.fetch(:data, {}), state_tone: @tone }) do
          safe_join([ tag.span(class: "#{DOT} #{DOTS.fetch(@tone)}", aria: { hidden: true }), @label ])
        end
      end
    end
  end
end
