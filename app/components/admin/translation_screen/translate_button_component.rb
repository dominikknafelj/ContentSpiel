module Admin
  module TranslationScreen
    # The **Translate** button under a translated field's own input, on the
    # field's side of the translation pair (translation helpers spec §6.4),
    # rendered into its `data-translate-slot` by the three field renderers
    # (`Admin::FieldComponent`, `Admin::Columns::PlainColumnComponent`/
    # `RichTextColumnComponent`). The empty box a suggestion streams into
    # (`SuggestionComponent.dom_id(input_id)`, `box_id`) is NOT part of this
    # component: the renderers put it right beside the button, under the
    # field's own input (`admin/shared/_translation_box`), so a suggestion
    # appears inside the field rather than in the reference card beside it.
    #
    # `confirm:` is the same `{ record_type:, record_id:, field:, locale: }`
    # the "Still correct" button gets (`ReferenceCardComponent
    # .options_for`), handed over only for a viewer who may edit the
    # record -- so a view-only editor, or the primary language (which has
    # no `confirm` at all), never gets a button. On top of that the button
    # needs AI set up (`AI.configured?`) and `ai.translate`; asking for a
    # suggestion is then decided again, for real, by `AI::Translate`.
    #
    # Everything the `admin--translate` controller needs to ask for this
    # field is on the wrapper as plain `data-translate-*` attributes rather
    # than Stimulus values, because the header's "Translate empty fields"
    # (`TranslateAllComponent`, another instance of the same controller)
    # reads them off every field on the screen:
    # - `input-id` is the input **Use** fills -- for rich text the editor's
    #   hidden JSON input (`"#{id}-json"`), which the `translate:use` event
    #   is dispatched on so it bubbles to that editor's `admin--rich-text`;
    # - `kind` (`plain`/`rich`) is how Use fills it;
    # - `characters` is the original's size as `AI::Translate` counts it
    #   (rich text as its Markdown), so the bulk request can split itself
    #   by `AI::Translate::MAX_CHARACTERS` before the server would refuse.
    #
    # The button is `type="button"` and does its request with `fetch`: it
    # sits inside the field's autosave `<form>`, and a submit button there
    # would submit that form instead.
    class TranslateButtonComponent < Admin::AdminComponent
      LABEL = "Translate".freeze

      # Shared with `TranslateAllComponent`'s buttons.
      BUTTON_CLASS = "inline-flex cursor-pointer items-center gap-1.5 rounded-cs border border-line-strong bg-surface px-2 py-0.5 text-sm text-ink " \
        "hover:bg-sunken disabled:cursor-wait disabled:opacity-70".freeze
      SPINNER_CLASS = "inline-block size-3 animate-spin rounded-full border-2 border-current border-t-transparent".freeze

      UPDATE_LABEL = "Suggest update".freeze
      MODES = %i[translate update].freeze

      # `mode: :update` is the outdated reference card's **Suggest update**
      # (`Admin::EditorScreen::ReferenceCardComponent`): the same wrapper and
      # the same single-field request as **Translate**, carrying
      # `data-translate-mode="update"` so `admin--translate` sends `mode=update`
      # and the suggestion that comes back also shows the field's current
      # translation (`SuggestionComponent` `mode: :update`). The header's bulk
      # run skips it (`admin--translate`'s `emptyFields`): its field already has
      # a translation.
      #
      # **Translate** itself only renders on an empty field; the renderers
      # (`Admin::Columns::Base#translate_button`, `Admin::FieldComponent`) decide
      # that, and put the suggestion box under the input for either mode.
      def initialize(confirm:, input_id:, kind: :plain, characters: 0, mode: :translate)
        raise ArgumentError, "unknown translate mode #{mode.inspect}" unless MODES.include?(mode.to_sym)

        @mode = mode.to_sym
        @confirm = confirm&.to_h&.symbolize_keys
        @input_id = input_id.to_s
        @kind = kind.to_s
        @characters = characters.to_i
      end

      def render? = confirm.present? && AI.configured? && can?("ai.translate")

      def label = @mode == :update ? UPDATE_LABEL : LABEL

      def box_id = SuggestionComponent.dom_id(input_id)

      def wrapper_data
        {
          controller: "admin--translate",
          "admin--translate-url-value": helpers.admin_translation_suggestions_path,
          "admin--translate-locale-value": confirm[:locale],
          translate_record_type: confirm[:record_type],
          translate_record_id: confirm[:record_id],
          translate_field: confirm[:field],
          translate_input_id: input_id,
          translate_kind: kind,
          translate_characters: characters,
          translate_mode: @mode
        }
      end

      private

      attr_reader :confirm, :input_id, :kind, :characters
    end
  end
end
