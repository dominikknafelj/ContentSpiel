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
    # the translation screens find the original through the first. When the
    # card knows its `record` it also has a stable DOM id (`.dom_id`), which is
    # what the "Still correct — mark up to date" Turbo Stream replaces
    # (`Admin::TranslationConfirmationsController`).
    #
    # The body is a `<details open>`: when the pair stacks (narrower than
    # 880px of container, `.admin-translation-pair` in the stylesheet) the
    # reader can fold the original away to get the field itself under their
    # hands. Side by side the summary is made inert by that same CSS, so the
    # original never folds when there is room for both.
    #
    # The outdated variant (handoff §4.1 "Outdated field", §10 A4). The border
    # turns `warn`, the header adds "↻ CHANGED <time ago>" (only when the
    # record knows when the original changed, `translation_original_changed_at
    # _for`), and the body is one of four, in this order:
    #
    # 1. the word diff, when the translation stored the text it was made from
    #    AND that text was in the site's CURRENT primary language
    #    (`Translations::Source#comparable?` -- after the default language
    #    changes, the stored text is in the old one and must never be diffed
    #    against the new);
    # 2. "Formatting changed" (the texts are equal, the digests are not: a
    #    bold toggled, a link added) over the current original;
    # 3. "The text is too long to compare word by word." over the current
    #    original (`SourceDiff#too_long?`);
    # 4. no usable stored text (a translation saved before sources kept text,
    #    another primary language, or a card without a record): the current
    #    original and "<name> changed since this was translated.".
    #
    # The diff is built with `content_tag` over the segments -- user text is
    # only ever an escaped child of `del`/`ins`/`span`, never `html_safe`.
    # `del` is the one place red marks removed text, per the handoff; `ins` keeps
    # its underline (colour is never the only cue) and each carries a
    # visually hidden "Removed: "/"Added: " cue so a screen reader hears what changed.
    # Rich text is diffed as plain text per paragraph
    # (`RichText::Document#plain_paragraphs`) and shown one `<p>` per
    # paragraph (a `"\n"` segment ends one).
    #
    # Actions, in a row under the body: **Suggest update** (`suggest:`, a
    # `TranslateButtonComponent` in `mode: :update` the caller builds -- it
    # knows the input the suggestion fills -- which renders only with AI set
    # up and `ai.translate`) and **Still correct — mark up to date**, a
    # submit button owned by the layout's confirm form through `form=`
    # (`FORM_ID`; forms can't nest, and the card sits inside the editor's own
    # form), naming its record in `formaction`'s query. Without JavaScript
    # that is an ordinary POST and redirect; with Turbo the answer replaces
    # this card with its `:current` variant (`.current_for`).
    #
    # The per-field **Translate** button is not here: it renders under the
    # input, on the field's own side of the pair, next to the suggestion box
    # it streams into.
    class ReferenceCardComponent < Admin::AdminComponent
      # The one empty confirm form the admin layout renders outside every
      # editor form (`app/views/layouts/admin.html.erb`).
      FORM_ID = "translation-confirm-form".freeze

      STATES = %i[current outdated unknown missing].freeze

      CONFIRM_LABEL = "Still correct — mark up to date".freeze
      FORMATTING_NOTE = "Formatting changed".freeze
      TOO_LONG_NOTE = "The text is too long to compare word by word.".freeze

      def self.dom_id(record, field)
        "reference-card-#{record.class.name.underscore.tr("/_", "--")}-#{record.id}-#{field}"
      end

      # The `translation_state:`/`translation_confirm:`/`translation_record:`
      # trio an editor hands the renderer of `record`'s `field`, splatted into
      # its constructor: nothing in the primary language (the original
      # itself), for a record not saved yet, or for a field that isn't tracked
      # (a slug, an untranslated schema field). `confirmable:` is whether the
      # viewer may edit the record -- the editor's own `editable?`; the
      # service decides again on submit. The record rides along for the
      # outdated card's diff and change time -- it is not rendered.
      def self.options_for(record, field, locale:, confirmable:)
        field = field.to_s
        locale = locale.to_s
        return {} if locale == ::Locales.default || !record.persisted?
        return {} unless record.class.translation_tracked_fields(record).include?(field)

        confirm = { record_type: record.class.name, record_id: record.id, field: field, locale: locale } if confirmable
        { translation_state: record.translation_state(field, locale), translation_confirm: confirm, translation_record: record }
      end

      # The `:current`-state card for `record`'s `field` as it reads now --
      # what a confirmation streams in place of the outdated one. The original
      # is the record's own primary-language value (a rich body is a
      # `RichText::Document`, so it renders as rich); a schema group's raw Hash
      # is handed over as it is, exactly as `Admin::FieldComponent` does, so the
      # card never vanishes on confirm.
      def self.current_for(record, field, locale:)
        original = record.translation_value(field, ::Locales.default)
        kind = original.is_a?(RichText::Document) ? :rich : :plain
        new(field: field, locale: locale, original: original, kind: kind, state: record.translation_state(field, locale), record: record)
      end

      # `record:` is whatever the field belongs to (nil where the caller has
      # no record, e.g. a column outside any tracked record); the outdated
      # card reads its stored source and change time.
      def initialize(field:, locale:, original:, kind: :plain, state: nil, confirm: nil, record: nil, suggest: nil)
        @record = record
        @field = field
        @locale = locale
        @original = original
        @kind = kind
        @state = (state || :current).to_sym
        @confirm = confirm&.to_h&.symbolize_keys
        @suggest = suggest
        raise ArgumentError, "unknown translation state #{@state.inspect}" unless STATES.include?(@state)
      end

      attr_reader :record, :field, :locale, :original, :kind, :state, :confirm, :suggest

      def rich? = kind == :rich

      def outdated? = state == :outdated

      def language_name = ::Locales.name(::Locales.default, native: true)

      def card_id = record&.persisted? ? self.class.dom_id(record, field) : nil

      def card_class
        "admin-reference-card min-w-0 rounded-cs border #{outdated? ? "border-warn" : "border-line"} bg-paper p-3"
      end

      # Same renderer and scrubber as the public site, in the primary
      # language, with preview URLs so an internal link to a not-yet-published
      # page still shows as a link here.
      def original_html
        document.to_html(locale: ::Locales.default, urls: PublicSite::Urls.new(preview: true))
      end

      def changed_at
        return unless outdated?

        return @changed_at if defined?(@changed_at)

        @changed_at = record&.translation_original_changed_at_for(field)
      end

      def no_source_note = "#{language_name} changed since this was translated."

      # Which outdated body to show: `:diff`, `:formatting`, `:too_long` or
      # `:no_source` (see the class comment). Nil for any other state.
      def outdated_body
        return unless outdated?

        return @outdated_body if defined?(@outdated_body)

        @outdated_body =
          if diff.nil? then :no_source
          elsif diff.too_long? then :too_long
          elsif diff.formatting_only? then :formatting
          elsif diff.changed? then :diff
          else :no_source
          end
      end

      # The sentence under the body: nil for the diff, which speaks for itself.
      def outdated_note
        case outdated_body
        when :formatting then FORMATTING_NOTE
        when :too_long then TOO_LONG_NOTE
        when :no_source then no_source_note
        end
      end

      # One `[kind, text]` list per paragraph (a plain value is one
      # paragraph, its own newlines kept by `whitespace-pre-line`).
      def paragraphs
        paragraphs = [ [] ]
        diff.segments.each do |segment_kind, text|
          if segment_kind == :equal && text == "\n" && rich?
            paragraphs << []
          else
            paragraphs.last << [ segment_kind, text ]
          end
        end
        paragraphs
      end

      def diff_html(segments)
        safe_join(segments.map { |segment_kind, text| segment_tag(segment_kind, text) })
      end

      def confirmable? = confirm.present?

      def confirm_url = helpers.admin_translation_confirmation_path(**confirm.slice(:record_type, :record_id, :field, :locale))

      private

      def document
        original.is_a?(RichText::Document) ? original : RichText::Document.new(original || {})
      end

      # Only a stored text taken in the current primary language is diffed.
      def diff
        return @diff if defined?(@diff)

        source = record&.translation_source(field, locale)
        current = Translations.source_text(rich? ? document : original)
        @diff = (Translations::SourceDiff.call(from: source.text, to: current) if source&.comparable? && !current.nil?)
      end

      # A screen-reader-only cue inside the element: `aria-label` on `del`/`ins`
      # (name-prohibited roles) is unreliable and may replace the word itself.
      def cue(label) = content_tag(:span, label, class: "sr-only")

      def segment_tag(segment_kind, text)
        case segment_kind
        when :delete then content_tag(:del, safe_join([ cue("Removed: "), text ]), class: "text-danger-ink bg-danger-tint")
        when :insert then content_tag(:ins, safe_join([ cue("Added: "), text ]), class: "text-ok-ink bg-ok-tint underline decoration-ok-ink")
        else content_tag(:span, text)
        end
      end
    end
  end
end
