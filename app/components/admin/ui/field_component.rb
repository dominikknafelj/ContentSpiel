module Admin
  module Ui
    # Renders one `ContentModel::Definition::Field` as a labelled input, plus
    # everything around it every field type shares (spec §4.3/§6.2): the
    # reference card with the original-language value (beside the field, or
    # above it when narrow) and its translate slot for a translated field in a
    # non-default locale (an untranslated field isn't rendered there at all: the
    # forms list it read-only under "Shared fields"), and a per-field error slot a Turbo Stream
    # can replace wholesale. The actual `<input>`/`<select>`/... is delegated
    # to one `Admin::Fields::*` class per `field.type` -- this component only
    # owns the chrome around it, so every field type gets that chrome for
    # free instead of re-implementing it once per type.
    #
    # `value`/`original` are the field's *already-read* values (whatever a
    # `ContentModel::FieldSet` reader or a plain Hash yields for `field.name`)
    # -- this component and its dispatched `Fields::*` never touch a FieldSet
    # directly, so the same components work for a block's `settings`, a
    # post's typed `fields`, or a bare in-memory value in a Lookbook preview.
    #
    # `original` deciding whether the read-only column shows up (rather than
    # this component re-deriving "non-default locale and translated" itself)
    # is deliberate: the caller already knows both facts building the field
    # list for a locale, and a field kept translated: true but with nothing
    # to compare against (a brand new translated field, no default-locale
    # value yet) simply passes `original: nil` and gets no column.
    class FieldComponent < AdminComponent
      # Turns a bracketed form name prefix into an id-safe one, e.g.
      # `"post[fields]"` -> `"post_fields"`, `"post[fields][speakers][0]"` ->
      # `"post_fields_speakers_0"`. Shared by every field's input id and its
      # errors container id, so the two always agree without a field having to
      # know the other's naming scheme.
      def self.dom_id_prefix(form_name) = form_name.to_s.gsub(/[\[\]]+/, "_").chomp("_")

      # The id a Turbo Stream replaces to show/clear this field's errors --
      # `prefix` is already a `dom_id_prefix` (a group/groups row builds it
      # with its own row index baked in, e.g. `"post_fields_speakers_0"`), so
      # this is pure string formatting, not another id-safety pass.
      def self.error_id(prefix, name) = "#{prefix}-#{name}-errors"

      # `id_prefix:` overrides the id-derivation `dom_id_prefix(form_name)`
      # otherwise falls back to -- needed the moment a single literal
      # `form_name` (e.g. block cards all naming their schema fields
      # `"block[settings]"`, cs-studio spec §5.1/Task 5) is shared by more
      # than one instance of the same form on one screen: the submitted field
      # *name* has to stay that one literal string (so the server-side split
      # in `Admin::ContentBlocksController` sees a plain `params[:block]`
      # regardless of which card posted it), but the rendered *ids* still have
      # to be document-unique, or a Turbo Stream error-slot replace (and a
      # `label for=`/`id=` pairing) for one card could silently land on
      # another card's identically-named field instead. Defaulting to nil
      # (falling back to the old `dom_id_prefix(form_name)` behaviour) keeps
      # every existing single-instance-per-page caller (the post/group fields
      # this component already serves) unchanged.
      #
      # `translation_state:`/`translation_confirm:` drive the "Original
      # changed" note beside the original -- the same contract
      # `Admin::Columns::Base` gives every column field.
      def initialize(field:, form_name:, value:, original: nil, locale:, errors: [], id_prefix: nil,
        translation_state: nil, translation_confirm: nil, translation_record: nil)
        @field = field
        @form_name = form_name
        @value = value
        @original = original
        @locale = locale
        @errors = errors
        @id_prefix = id_prefix || self.class.dom_id_prefix(form_name)
        @translation_state = translation_state
        @translation_confirm = translation_confirm
        @translation_record = translation_record
      end

      # The field's own label where its type gives one (`label: "File name"`),
      # its name humanised otherwise (`ContentModel::Definition::Field#label`).
      def label_text = field.label

      def input_id = "#{id_prefix}-#{field.name}"

      def errors_id = self.class.error_id(id_prefix, field.name)

      # The nested `Admin::Fields::*` component this field's type dispatches
      # to -- `"#{type}_field.rb"`'s class name, by the same
      # underscore/camelize convention every other autoloaded file in this app
      # already follows (`content_type` -> `ContentTypeField`, `groups` ->
      # `GroupsField`), so adding a field type later means adding one file,
      # not also editing a hand-kept dispatch table here.
      def input_component
        "Admin::Fields::#{field.type.to_s.camelize}Field".constantize.new(
          field: field, form_name: form_name, value: value, original: original, locale: locale, errors: errors, id_prefix: id_prefix
        )
      end

      # True once the caller has handed over something to compare against --
      # see the class comment for why that's the caller's call, not this
      # component re-deriving "non-default locale and translated" itself.
      def show_original? = original.present?

      # The card showing the primary-language original beside (or above) the
      # input -- see `Admin::Columns::Base#reference_card`.
      def reference_card
        Admin::EditorScreen::ReferenceCardComponent.new(
          field: field.name, locale: locale, original: original, state: translation_state, confirm: translation_confirm, record: translation_record, suggest: suggest_update_button
        )
      end

      # Text types only get the AI **Translate** button (translation helpers
      # spec §6.4): a group's original is a nested value no provider is
      # handed (`AI::Translate` skips it), and no other scalar type is
      # translated prose. See `Admin::Columns::Base#translate_button`.
      TRANSLATABLE_TYPES = %i[string text].freeze

      # Only on an empty field -- see `Admin::Columns::Base#translate_button`.
      def translate_button
        return unless translation_confirm && TRANSLATABLE_TYPES.include?(field.type) && value.blank?

        Admin::TranslationScreen::TranslateButtonComponent.new(confirm: translation_confirm, input_id: input_id, characters: original.to_s.length)
      end

      # **Suggest update** for an outdated text field -- see
      # `Admin::Columns::Base#suggest_update_button`.
      def suggest_update_button
        return unless translation_state == :outdated && translation_confirm && TRANSLATABLE_TYPES.include?(field.type)

        Admin::TranslationScreen::TranslateButtonComponent.new(
          confirm: translation_confirm, input_id: input_id, characters: original.to_s.length, mode: :update
        )
      end

      private

      attr_reader :field, :form_name, :value, :original, :locale, :errors, :id_prefix, :translation_state, :translation_confirm, :translation_record
    end
  end
end
