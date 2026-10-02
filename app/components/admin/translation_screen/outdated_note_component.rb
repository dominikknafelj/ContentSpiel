module Admin
  # `TranslationScreen`, not `Translations`: an `Admin::Translations` module
  # would shadow the top-level `Translations` (`app/models/translations.rb`,
  # `Translations::Status`, `Translations::Confirm`) for every bare
  # `Translations::` reference lexically nested under `module Admin` -- the
  # same trap `Admin::TrashScreen`'s own comment describes.
  module TranslationScreen
    # The note an outdated translation shows beside its original
    # (translation helpers spec §4): "Original changed since this was
    # translated", plus a **Mark as up to date** button
    # (`Translations::Confirm`) for a viewer who may edit the record.
    # Rendered by the three "original" renderers (`Admin::FieldComponent`,
    # `Admin::Columns::PlainColumnComponent`/`RichTextColumnComponent`) when
    # handed `translation_state: :outdated`; `:unknown` (a translation that
    # predates tracking) shows nothing.
    #
    # `confirm:` is `{ record_type:, record_id:, field:, locale: }`, or nil
    # for a viewer who can't confirm (a view-only editor): the note alone.
    #
    # The button can't be a `button_to`: every one of these fields sits
    # inside its editor's autosave `<form>`, and forms don't nest -- the
    # parser drops an inner `<form>` tag, so its button would submit the
    # autosave form instead. So it's a submit button *owned* by the one
    # empty confirm form the admin layout renders outside every form and
    # frame (`form="#{FORM_ID}"`, the HTML form-owner attribute), naming
    # its record in `formaction`'s query. No JavaScript involved: without
    # Turbo it's an ordinary POST and redirect back; with it, a Turbo
    # Stream removes this note (`.dom_id`, computed the same way by
    # `Admin::TranslationConfirmationsController`).
    class OutdatedNoteComponent < Admin::AdminComponent
      FORM_ID = "translation-confirm-form".freeze

      TEXT = "Original changed since this was translated".freeze

      def self.dom_id(record_type, record_id, field)
        "translation-note-#{record_type.to_s.underscore.tr("/_", "--")}-#{record_id}-#{field}"
      end

      # The `translation_state:`/`translation_confirm:` pair an editor hands
      # the renderer of `record`'s `field`, splatted into its constructor:
      # nothing in the primary language (the original itself), for a record
      # not saved yet, or for a field that isn't tracked (a slug, an
      # untranslated schema field). `confirmable:` is whether the viewer may
      # edit the record -- the editor's own `editable?`; the service decides
      # again on submit.
      def self.options_for(record, field, locale:, confirmable:)
        field = field.to_s
        locale = locale.to_s
        return {} if locale == ::Locales.default || !record.persisted?
        return {} unless record.class.translation_tracked_fields(record).include?(field)

        confirm = { record_type: record.class.name, record_id: record.id, field: field, locale: locale } if confirmable
        { translation_state: record.translation_state(field, locale), translation_confirm: confirm }
      end

      def initialize(confirm: nil)
        @confirm = confirm&.to_h&.symbolize_keys
      end

      def confirmable? = confirm.present?

      def note_id = confirmable? ? self.class.dom_id(confirm[:record_type], confirm[:record_id], confirm[:field]) : nil

      def confirm_url = helpers.admin_translation_confirmation_path(**confirm.slice(:record_type, :record_id, :field, :locale))

      private

      attr_reader :confirm
    end
  end
end
