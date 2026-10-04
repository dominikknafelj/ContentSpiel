module Admin
  module TranslationScreen
    # One AI suggestion under a field's original (translation helpers spec
    # §6.4): the suggested text -- or, for rich text, the suggested
    # document rendered as a preview -- with **Use** and **Discard**, plus
    # any warnings (a rich-text body's Markdown repairs). With `error:` it's
    # the inline error variant instead: the message and a Dismiss.
    #
    # `Admin::TranslationsController#suggest` streams it (`update`) into the
    # empty box `TranslateButtonComponent` rendered, `.dom_id(input_id)`.
    #
    # A plain suggestion sits in an editable `<textarea>` (no `name`, so it
    # never feeds the form's autosave or the save bar's change count) that
    # **Use** reads at click time; a rich-text one stays a rendered preview
    # (it is edited in the editor, after Use). The box lives under the
    # field's own input (`admin/shared/_translation_box`), in the `.admin-
    # translation-suggestion` class that stops the textarea turning red with
    # the field's error. Its `input`/`change`/`focusout` are stopped at the
    # box (`admin--translate#contain`): the box sits inside the autosave
    # `<form>`, whose listeners would otherwise save on every edit of text
    # that is not a field yet.
    #
    # Nothing here saves anything: **Use** is `admin--translate#use`, which
    # fills the input named by `data-translate-input-id` (a plain field's
    # value plus a bubbling `input` event; a rich-text body through a
    # `translate:use` event its `admin--rich-text` handles) and lets that
    # form's own autosave write it, as an ordinary edit (Review Focus 4).
    #
    # The suggestion only ever reaches the page escaped: plain text as a
    # text node and a `data-` attribute (the tag helper escapes both), rich
    # text as its document JSON in a `data-` attribute plus the preview,
    # which goes through the same scrubbed `RichText::Document#to_html` the
    # original beside it uses -- AI output is untrusted input like any other.
    # The rich-text Use also carries what the editor needs to *show* the
    # document's images and internal links (`assets`/`link_titles`, the
    # same lookups `Admin::Columns::RichTextColumnComponent` hands the
    # editor on page load), since the target language's document may not
    # reference them yet.
    class SuggestionComponent < Admin::AdminComponent
      def self.dom_id(input_id) = "translation-suggestion-#{input_id}"

      BUTTON_CLASS = "cursor-pointer rounded-cs border border-line-strong bg-surface px-2 py-0.5 text-ink hover:bg-sunken".freeze

      def initialize(input_id:, locale:, suggestion: nil, warnings: [], error: nil, provider: nil, model: nil)
        @input_id = input_id.to_s
        @provider = provider.presence
        @model = model.presence
        @locale = locale.to_s
        @suggestion = suggestion
        @warnings = Array(warnings)
        @error = error
      end

      def error? = error.present?

      def rich? = suggestion.is_a?(RichText::Document)

      def preview_html = suggestion.to_html(locale: locale, urls: PublicSite::Urls.new(preview: true))

      # The header line: names the model when the controller knew it (it is
      # configuration -- `AI.model`, the default when none is set -- never
      # anything about the key), else just says what this is.
      def heading = model ? "Suggested by #{model}" : "Suggested translation"

      def rows = [ suggestion.to_s.lines.count, 2 ].max

      # A plain suggestion's text is NOT carried on Use: Use reads the
      # editable textarea's current value (`admin--translate#use`), so what
      # the editor changed by hand is what gets applied.
      def use_data
        data = { action: "admin--translate#use", translate_use: true, translate_kind: rich? ? "rich" : "plain", translate_input_id: input_id }
        return data unless rich?

        lookups = Admin::Columns::RichTextColumnComponent.new(name: "body", value: suggestion, locale: locale)
        data.merge(translate_document: suggestion.to_h.to_json, translate_assets: lookups.assets_json, translate_link_titles: lookups.link_titles_json)
      end

      private

      attr_reader :input_id, :locale, :suggestion, :warnings, :error, :provider, :model
    end
  end
end
