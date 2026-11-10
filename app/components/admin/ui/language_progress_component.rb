module Admin
  module Ui
    # One target language's translation progress: a 4px bar of complete over
    # total, `ok` on a `sunken` track (3:1, `test/lib/admin_contrast_test.rb`),
    # and under it the counts, outdated first ("↻ 1 outdated", in warn ink,
    # since an outdated item is already on the site), then missing ("12
    # missing", in meta), or "All translated". The Dashboard's "Languages
    # behind" panel and the Translations screen's language tiles both draw it,
    # so a language reads the same on both.
    #
    # Translation states are never red, and "outdated" carries its ↻ and its
    # word, so the colour is never the only cue. The bar's widths are spelled
    # out in 5% steps so Tailwind's scanner sees every class and no inline
    # style is needed.
    #
    # Everything is spans, so it may stand inside a link (a language tile is
    # one). `counts_id:` gives the counts an id, for a caller whose link they
    # describe.
    class LanguageProgressComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "The bar is a progressbar named \"<language> translated\" with its percentage; the counts are text, the ↻ left out of the tree. It takes no focus.",
        motion: :none,
        content_edges: %i[short long],
        widths: :fluid,
        interface: %i[language complete total outdated missing counts_id],
        limits: [
          "It cannot be pressed and takes no focus: inside a link it is part of the link.",
          "It draws the bar in 5% steps.",
          "The counts are outdated, then missing; a zero count is not drawn, and with both zero it reads All translated."
        ],
        states: %i[both outdated missing done empty],
        keys: %w[progress_label all_translated outdated missing],
        slots: [],
        controller: nil,
        keyboard: [ "test/system/admin/translations_test.rb", "a language tile is one stop for the keyboard: its progress takes no focus" ]
      )

      WIDTHS = [ "w-0", "w-[5%]", "w-[10%]", "w-[15%]", "w-[20%]", "w-[25%]", "w-[30%]", "w-[35%]", "w-[40%]", "w-[45%]", "w-[50%]", "w-[55%]", "w-[60%]", "w-[65%]", "w-[70%]", "w-[75%]", "w-[80%]", "w-[85%]", "w-[90%]", "w-[95%]", "w-full" ].freeze

      # Complete over total as a whole percentage; 0 for nothing to translate.
      def self.percent(complete:, total:) = total.zero? ? 0 : (complete * 100.0 / total).round

      # `language` is the language's own name, which names the bar.
      def initialize(language:, complete:, total:, outdated:, missing:, counts_id: nil)
        @language = language
        @complete = complete
        @total = total
        @outdated = outdated
        @missing = missing
        @counts_id = counts_id
      end

      private

      attr_reader :language, :outdated, :missing, :counts_id

      def percent = self.class.percent(complete: @complete, total: @total)

      def width_class = WIDTHS[(percent / 5.0).round]

      def done? = outdated.zero? && missing.zero?
    end
  end
end
