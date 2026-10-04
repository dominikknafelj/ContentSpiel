module Admin
  module EditorScreen
    # The primary-language original shown beside (or, in a narrow column,
    # above) a translated field (handoff §4.1 "Side-by-side translation"):
    # the language's own name as an uppercase mono label, then the original --
    # a `<p>` for a plain value, the rendered (and scrubbed) HTML for a rich
    # one. It replaces the old sunken "original" panel `Admin::Columns::*` and
    # `Admin::FieldComponent` each rendered by hand.
    #
    # The root carries `data-original-for` (the field) and
    # `data-translation-state` (`:current` / `:outdated` / `:unknown` /
    # `:missing`, nil meaning an untracked field, read as current). Tests and
    # the translation screens find the original through the first.
    #
    # The body is a `<details open>`: when the pair stacks (narrower than
    # 880px of container, `.admin-translation-pair` in the stylesheet) the
    # reader can fold the original away to get the field itself under their
    # hands. Side by side the summary is made inert by that same CSS, so the
    # original never folds when there is room for both.
    #
    # `header_note` and `actions` are the slots the outdated state fills
    # (Task 8: the "original changed" line with the diff, and its buttons).
    # Until a caller fills them, an outdated card keeps today's
    # `OutdatedNoteComponent` -- the note and its "Mark as up to date" button,
    # which posts the layout's separate confirm form through `form=` (forms
    # can't nest, and the card sits inside the editor's own form).
    #
    # The per-field **Translate** button is not here: it renders under the
    # input, on the field's own side of the pair, next to the suggestion box
    # it streams into.
    class ReferenceCardComponent < Admin::AdminComponent
      renders_one :header_note
      renders_one :actions

      STATES = %i[current outdated unknown missing].freeze

      # `record:` is whatever the field belongs to (nil where the caller has
      # no record, e.g. the site settings' columns); it is carried for Task
      # 8's diff, which reads its stored source.
      def initialize(field:, locale:, original:, kind: :plain, state: nil, confirm: nil, record: nil)
        @record = record
        @field = field
        @locale = locale
        @original = original
        @kind = kind
        @state = (state || :current).to_sym
        @confirm = confirm
        raise ArgumentError, "unknown translation state #{@state.inspect}" unless STATES.include?(@state)
      end

      attr_reader :record, :field, :locale, :original, :kind, :state, :confirm

      def rich? = kind == :rich

      def language_name = ::Locales.name(::Locales.default, native: true)

      # Same renderer and scrubber as the public site, in the primary
      # language, with preview URLs so an internal link to a not-yet-published
      # page still shows as a link here.
      def original_html
        document = original.is_a?(RichText::Document) ? original : RichText::Document.new(original || {})
        document.to_html(locale: ::Locales.default, urls: PublicSite::Urls.new(preview: true))
      end

      # The default outdated note, until a caller fills the slots.
      def default_note
        return unless state == :outdated && !header_note? && !actions?

        Admin::TranslationScreen::OutdatedNoteComponent.new(confirm: confirm)
      end
    end
  end
end
