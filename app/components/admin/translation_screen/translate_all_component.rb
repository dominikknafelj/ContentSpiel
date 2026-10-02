module Admin
  module TranslationScreen
    # **Translate empty fields** and, once its suggestions are in, **Use
    # all** (translation helpers spec §6.4), in the header of the page,
    # post and settings editors in a non-default language.
    #
    # It asks for every field on the screen that has a Translate button
    # (`TranslateButtonComponent` -- so exactly the fields this viewer may
    # translate, the record's and, on a page, its blocks') and whose input
    # is empty *right now*, which is what `:missing` means at the moment
    # the button is pressed (an input typed into, or filled by Use, since
    # the page loaded no longer counts). The requests are split per record
    # and by `AI::Translate::MAX_FIELDS`/`MAX_CHARACTERS`, and sent one
    # after another rather than as one long server request: each must fit
    # the provider's 60 s timeout on its own, and a sequence of short
    # requests also shows progress and keeps what earlier parts returned if
    # a later one fails.
    #
    # **Use all** presses every Use on the screen, plain fields first, then
    # rich text, so each form's autosave queues them as ordinary edits.
    #
    # `editable:` is the editor's own "may this viewer edit the record"
    # answer; together with `AI.configured?` and `ai.translate` it decides
    # whether the button shows at all (the per-field buttons follow the
    # same rule, so there'd be nothing to ask for otherwise).
    class TranslateAllComponent < Admin::AdminComponent
      def initialize(locale:, editable:)
        @locale = locale.to_s
        @editable = editable
      end

      def render? = editable && locale != ::Locales.default && AI.configured? && can?("ai.translate")

      def wrapper_data
        {
          controller: "admin--translate",
          "admin--translate-url-value": helpers.admin_translation_suggestions_path,
          "admin--translate-locale-value": locale,
          "admin--translate-max-fields-value": AI::Translate::MAX_FIELDS,
          "admin--translate-max-characters-value": AI::Translate::MAX_CHARACTERS
        }
      end

      private

      attr_reader :locale, :editable
    end
  end
end
