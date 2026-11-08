module Admin
  module SettingsScreen
    # The Languages card's instant actions: the forms and dialogs that can't
    # live inside the Settings form (forms can't nest, and a dialog's own form
    # can't be inside one either) and that the card reaches by `form=` or a
    # dialog trigger. Rendered after the Settings form.
    #
    #   - `#language-add-form` -- Add language: `POST settings/languages`, no
    #     dialog (nothing is lost by it);
    #   - per non-default language, "Make <Name> the default?" (`PATCH
    #     settings/languages/<code>/default`) and "Turn off <Name>?"
    #     (`DELETE settings/languages/<code>`).
    #
    # Both dialogs are NEUTRAL (their confirm is the dialog's primary, never red): the default change
    # re-marks translations but deletes nothing, and turning a language off keeps
    # its translations (`Locales::Disable`). The "(N items)" in the default
    # dialog is `Translations::StateIndex.translated_record_count` -- how many
    # records hold a translation today -- counted once at render.
    class LanguageDialogsComponent < Admin::AdminComponent
      def initialize(site_setting:)
        @site_setting = site_setting
      end

      def add_form = LanguagesCardComponent::ADD_FORM

      def default_code = site_setting.default_locale.to_s

      def others = site_setting.locale_codes - [ default_code ]

      def name(code) = ::Locales.name(code, native: true)

      def default_dialog_id(code) = LanguagesCardComponent.default_dialog_id(code)

      def off_dialog_id(code) = LanguagesCardComponent.off_dialog_id(code)

      def items_phrase
        @items_phrase ||= t(".items", count: ::Translations::StateIndex.translated_record_count)
      end

      private

      attr_reader :site_setting
    end
  end
end
