module Admin
  module Ui
    # CS Studio's one segmented control: a row of choices in one framed
    # track, the chosen one on the accent tint with an accent edge and accent
    # words at 600. It has one look in two modes, and only the markup and the
    # ARIA differ:
    #
    # - `mode: :links` is navigation (the Trash screen's types, a form's
    #   Form | Submissions, Waiting for you's and the Notes screen's filters):
    #   a `<nav>` named by `label`, each segment a link, the chosen one
    #   `aria-current="page"`. Pressing one is a visit; every link is a Tab stop.
    # - `mode: :radios` is a choice inside a form (the posts list's scope, the
    #   media library's and the picker's segments, the Translations type, a
    #   `control: :segmented` select, a Settings or form-builder choice): a
    #   `<fieldset>` whose legend is `label` (`legend: :hidden` sr-only, as in
    #   a filter bar, or `:visible`, a field's label), each segment a `<label>`
    #   around its sr-only radio named `name`. The group is one Tab stop and
    #   the arrows move the choice, a change bubbles to the form (its
    #   auto-submit or autosave) as a select's would, and the chosen look
    #   follows `:checked`, so it moves with the arrows before any answer.
    #   A radio that is disabled (`disabled:`, or a held form's freeze, which
    #   disables the radios itself) is never faded: its words go meta with
    #   no hover, and a chosen one keeps the chosen look.
    #
    # The chosen look is behind each mode's own variant (`aria-[current=page]:`
    # or `has-[:checked]:`), and the focus ring (2px accent, 2px outside the
    # segment) behind `focus-visible:` or `has-[:focus-visible]:`, because the
    # link takes the focus and the label does not. The count turns accent with
    # its segment through the named group `segment`, never a bare `group`:
    # a bare one would answer to any `.group` around the control, and the form
    # around a radio track holds a checked radio.
    #
    # The track is 38px (`--cs-control-compact`: 1 + 2 + 32 + 2 + 1), the
    # filter bar's height, so a filter bar sets nothing on it. At a narrow width
    # it wraps whole segments and never scrolls sideways.
    #
    # `segments` is a list of Hashes, each read into a `Segment`: `label:`,
    # `current:` (the chosen one), `count:` (nil draws none; 0 is drawn) and,
    # for links, `href:`; for radios `value:` and `id:` (the radio's, which the
    # label is `for`), with `count_id:` (the count span's id, for an answer
    # that rewrites it), `disabled:` and `data:` (the radio's). `control_data`
    # goes on every link or radio, a segment's own `data:` merged over it.
    class SegmentedComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "Links mode is a navigation named by its label, of links with the chosen one aria-current=page, each a Tab stop; radios mode is a fieldset whose legend is its label, of radios that are one Tab stop the arrows move along.",
        motion: :none,
        content_edges: %i[many short none],
        widths: :fluid,
        interface: %i[mode label segments name legend required id describedby control_data],
        limits: [
          "It draws links or radios, never a tablist: a link is a visit and a radio is a form's value, and what follows is the caller's (its form's auto-submit or autosave).",
          "With no segments it renders nothing.",
          "Every segment stays on the track: there is no overflow menu, and a narrow width wraps the track instead."
        ],
        states: %i[links radios no_counts narrow disabled hover focus],
        keys: [],
        slots: [],
        controller: nil,
        keyboard: [ "test/system/admin/keyboard_navigation_test.rb", "the segmented control: in links mode each segment is a Tab stop that Enter follows, and in radios mode the group is one Tab stop whose arrows choose and apply" ]
      )

      MODES = %i[links radios].freeze
      LEGENDS = %i[hidden visible].freeze

      Segment = Data.define(:label, :current, :count, :href, :value, :id, :count_id, :disabled, :data) do
        def initialize(label:, current: false, count: nil, href: nil, value: nil, id: nil, count_id: nil, disabled: false, data: {}) = super
      end

      # The frame. No dividers: the segments stand 2px apart on the surface.
      # `admin-segmented` is what the filter bar's height rules leave out
      # (`.admin-filter-bar` in content-spiel.tailwind.css): the track is the
      # bar's height by itself.
      TRACK_CLASS = "admin-segmented inline-flex flex-wrap gap-0.5 rounded-button border border-field-line bg-surface p-0.5".freeze

      # A segment at rest and under the pointer, either mode's.
      SEGMENT_BASE_CLASS = "group/segment inline-flex min-h-8 cursor-pointer items-center gap-1.5 whitespace-nowrap rounded-field px-3 text-sm text-dim hover:bg-sunken hover:text-ink".freeze

      # The chosen look and the focus ring, behind the link's own variants. The
      # chosen one does not change under the pointer.
      LINK_SEGMENT_CLASS = "#{SEGMENT_BASE_CLASS} " \
                   "aria-[current=page]:bg-accent-tint aria-[current=page]:font-semibold aria-[current=page]:text-accent aria-[current=page]:inset-ring aria-[current=page]:inset-ring-accent " \
                   "aria-[current=page]:hover:bg-accent-tint aria-[current=page]:hover:text-accent " \
                   "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent".freeze

      # The same, behind the radio's: the label is drawn from the radio inside
      # it. A disabled one keeps its colour (never an opacity): meta words, no
      # hover, the chosen look kept.
      RADIO_SEGMENT_CLASS = "#{SEGMENT_BASE_CLASS} " \
                    "has-[:checked]:bg-accent-tint has-[:checked]:font-semibold has-[:checked]:text-accent has-[:checked]:inset-ring has-[:checked]:inset-ring-accent " \
                    "has-[:checked]:hover:bg-accent-tint has-[:checked]:hover:text-accent " \
                    "has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-2 has-[:focus-visible]:outline-accent " \
                    "has-[:disabled]:cursor-not-allowed has-[:disabled]:not-has-[:checked]:text-meta " \
                    "has-[:disabled]:not-has-[:checked]:hover:bg-transparent has-[:disabled]:not-has-[:checked]:hover:text-meta".freeze

      # Always drawn when given, 0 included; accent on the chosen segment.
      COUNT_CLASS = "text-count text-meta tabular-nums group-aria-[current=page]/segment:text-accent group-has-[:checked]/segment:text-accent".freeze

      def initialize(mode:, label:, segments:, name: nil, legend: :hidden, required: false, id: nil, describedby: nil, control_data: {})
        raise ArgumentError, "unknown mode #{mode.inspect}" unless MODES.include?(mode)
        raise ArgumentError, "unknown legend #{legend.inspect}" unless LEGENDS.include?(legend)
        raise ArgumentError, "radios need a name" if mode == :radios && name.blank?
        if mode == :links && (name || required || describedby || legend != :hidden)
          raise ArgumentError, "links take no name, required, describedby or legend: they are a radio group's"
        end

        @mode = mode
        @label = label
        @segments = segments.map { |segment| Segment.new(**check(segment)) }
        @name = name
        @legend = legend
        @required = required
        @id = id
        @describedby = describedby
        @control_data = control_data
      end

      def render? = segments.any?

      private

      attr_reader :mode, :label, :segments, :name, :legend, :required, :id, :describedby, :control_data

      def links? = mode == :links

      def legend_class = legend == :hidden ? "sr-only" : "#{helpers.setup_label_class} mb-1"

      def data_for(segment) = control_data.merge(segment.data)

      # A link needs its address, a radio its value and its id (the label's
      # `for`); a key of the other mode is refused rather than dropped. A
      # radio's value is asked for by its key, not by its being set: `""` is
      # a value (Media's All), and a forgotten `value:` would otherwise
      # submit one silently. Handed back for `Segment.new`, which refuses an
      # unknown key.
      def check(segment)
        wanted, foreign = @mode == :links ? [ %i[href], %i[value id count_id disabled] ] : [ %i[value id], %i[href] ]
        missing = wanted.reject { |key| segment.key?(key) }
        stray = foreign.select { |key| segment.key?(key) }
        raise ArgumentError, "a #{@mode} segment needs #{missing.join(", ")}" if missing.any?
        raise ArgumentError, "a #{@mode} segment takes no #{stray.join(", ")}" if stray.any?

        segment
      end
    end
  end
end
