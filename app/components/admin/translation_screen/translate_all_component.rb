module Admin
  module TranslationScreen
    # **Suggest translations for N empty fields**, and the two states after it
    # (translation helpers spec §6.4, design pass round 2 handoff §4.1/§10), in
    # the header of the page, post and settings editors in a non-default
    # language.
    #
    # Three states in one element, flipped by `admin--translation--translate` with `hidden`:
    # - **idle**: the button, with the real N (`count`, below), hidden when N is
    #   0 -- the whole component is not rendered at 0;
    # - **running**: "Suggesting i of n fields", a 4px progress bar and Cancel;
    # - **ready**: "N suggestions ready · Use all · Discard all".
    #
    # N is counted here, server-side, over the record's tracked fields and, on
    # a page, its blocks': every text field (a string or a rich-text body -- a
    # schema group's raw Hash is never handed to a provider, `AI::Translate`
    # skips it) that is blank in `locale` and has a non-blank original. It is
    # what pressing the button will ask for, give or take a field the screen
    # has no input for; the client recounts from the page after every run, Use
    # and Discard (`admin--translation--translate#refresh`).
    #
    # Pressing it asks for every field on the screen that has a Translate
    # button (`TranslateButtonComponent` -- so exactly the fields this viewer
    # may translate, the record's and, on a page, its blocks') and whose input
    # is empty *right now*, which is what `:missing` means at the moment the
    # button is pressed (an input typed into, or filled by Use, since the page
    # loaded no longer counts). The requests are split per record and by
    # `AI::Translate::MAX_FIELDS`/`MAX_CHARACTERS`, and sent one after another
    # rather than as one long server request: each must fit the provider's 25 s
    # timeout on its own, and a sequence of short requests also shows progress
    # and keeps what earlier parts returned if a later one fails or the editor
    # cancels.
    #
    # **Use all** presses every Use on the screen, plain fields first, then
    # rich text, so each form's autosave queues them as ordinary edits;
    # **Discard all** empties every suggestion box.
    #
    # `editable:` is the editor's own "may this viewer edit the record"
    # answer; together with `AI.configured?` and `ai.translate` it decides
    # whether the button shows at all (the per-field buttons follow the same
    # rule, so there'd be nothing to ask for otherwise).
    class TranslateAllComponent < Admin::AdminComponent
      def self.label(count) = "Suggest translations for #{count} empty #{"field".pluralize(count)}"

      def initialize(record:, locale:, editable:, holds: nil)
        @record = record
        @holds = holds
        @locale = locale.to_s
        @editable = editable
      end

      def render? = editable && locale != ::Locales.default && AI.configured? && can?("ai.translate") && count.positive?

      # Memoised: `render?` and the template both read it.
      def count
        @count ||= owners.sum { |owner| held?(owner) ? 0 : empty_fields(owner) }
      end

      def label = self.class.label(count)

      def wrapper_data
        {
          controller: "admin--translation--translate",
          "admin--translation--translate-url-value": helpers.admin_translation_suggestions_path,
          "admin--translation--translate-locale-value": locale,
          "admin--translation--translate-max-fields-value": AI::Translate::MAX_FIELDS,
          "admin--translation--translate-max-characters-value": AI::Translate::MAX_CHARACTERS
        }
      end

      private

      attr_reader :record, :locale, :editable

      # The record and, for a page, its blocks (each tracks its own fields).
      # A page's settings or a block that someone else holds (live editing,
      # `Editing::Holds`) is read-only: its fields are neither counted nor
      # filled by the bulk run (the script skips them on screen the same way).
      # A WHOLE record held (a post) is not offered at all: the post form
      # hands `editable: false`.
      def held?(owner) = @holds&.other(owner).present?

      def owners = [ record, *(record.content_blocks if record.respond_to?(:content_blocks)) ]

      def empty_fields(owner)
        return 0 unless owner.class.respond_to?(:translation_tracked_fields)

        owner.class.translation_tracked_fields(owner).count do |field|
          original = owner.translation_value(field, ::Locales.default)
          (original.is_a?(String) || original.is_a?(RichText::Document)) && original.present? &&
            owner.translation_value(field, locale).blank?
        end
      end
    end
  end
end
