module Admin
  module HistoryScreen
    # The History screen's comparison (the StudioHistory card, "The
    # comparison"): one card, named by its heading "Version 5", then "compared
    # with" and the choice of the other side (the version before it, the
    # working version, or another version by number), under it the language
    # and the languages that differ, then the overview of what differs in
    # that language (`Admin::Ui::ChangesOverviewComponent`, `detail: :diffs`).
    #
    # The two selects are ONE GET form that submits as either changes
    # (`admin--ui--auto-submit`, `Admin::FilterHelper#filter_form_options`),
    # carrying the chosen version and the versions' page as hidden values, so
    # a choice keeps the rest of the address. The language is the admin's own
    # `locale` parameter, so the editor linked from the screen opens in it.
    #
    # `restore` is the slot of the one primary action, "Restore version 5…",
    # drawn only when `restore_offered` (the viewer may restore and the
    # version differs from the working version): the caller fills it.
    #
    # A record never published has no version: `.empty(record:)` draws the
    # empty state in the comparison's place ("No versions yet").
    class ComparisonComponent < Admin::AdminComponent
      renders_one :restore

      def self.empty(record:) = new(record: record, version: nil, previous: nil, with: nil, numbers: [], changes: nil, locale: ::Locales.default, form_url: nil)

      # `with`: "previous", "working" or another version's number, as a String.
      def initialize(record:, version:, previous:, with:, numbers:, changes:, locale:, form_url:, hidden: {}, restore_offered: false)
        @record = record
        @version = version
        @previous = previous
        @with = with
        @numbers = numbers
        @changes = changes
        @locale = locale.to_s
        @form_url = form_url
        @hidden = hidden
        @restore_offered = restore_offered
      end

      attr_reader :record, :version, :changes, :locale

      def heading_id = "history-comparison-heading"

      def empty? = version.nil?

      def empty_body = t(".empty_body.#{record.is_a?(::Page) ? "page" : "post"}")

      def form_options = helpers.filter_form_options(@form_url, bar: false).merge(class: "flex flex-col gap-3")

      def hidden_values = @hidden.compact_blank

      def restore_shown? = @restore_offered && restore?

      def with_options
        options = []
        options << [ t(".before_it", number: @previous.number), "previous" ] if @previous
        options << [ t(".working_option"), "working" ]
        # The chosen version is not compared with itself, and the one before
        # it is already its own option.
        options + (@numbers - [ version.number, @previous&.number ]).map { |number| [ t(".version", number: number), number.to_s ] }
      end

      def with_value = @with

      # The default language first, then the others in the site's order;
      # each that differs between the two sides says so.
      def languages = [ ::Locales.default, *(::Locales.enabled - [ ::Locales.default ]) ]

      def several_languages? = languages.size > 1

      def language_options
        languages.map { |code| [ differs?(code) ? t(".differs", language: name(code)) : name(code), code ] }
      end

      # The other languages, in words: those that differ, then those that
      # are the same.
      def others_line
        others = languages - [ locale ]
        differing, same = others.partition { |code| differs?(code) }
        parts = []
        if differing.any?
          parts << t(differs?(locale) ? ".others_differ_too" : ".others_differ", languages: names(differing), count: differing.size)
        end
        parts << t(".others_same", languages: names(same), count: same.size) if same.any?
        t(".line", parts: parts.join(t(".separator"))) if parts.any?
      end

      private

      def differs?(code) = changed_locales.include?(code.to_s)

      def changed_locales = @changed_locales ||= changes.locales.map(&:to_s)

      def name(code) = ::Locales.name(code, native: true)

      def names(codes) = codes.map { |code| name(code) }.to_sentence # i18n-ok: to_sentence joins with the locale's support.array words
    end
  end
end
