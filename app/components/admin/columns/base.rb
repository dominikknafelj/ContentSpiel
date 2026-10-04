module Admin
  module Columns
    # Shared shape for the "opted-in column" field components (spec §4.3):
    # unlike `Admin::Fields::*`, which render a schema field named under a
    # `form_name` prefix supplied by `FieldComponent`, a column field edits
    # an existing AR column directly (`page.title`, `post.body`, a block's
    # `caption`) and is named by that bare column name -- there's no prefix
    # to compute, since the record's own `update`/save endpoint reads
    # `params[name]` straight off the top level. `original`/`errors` follow
    # the same convention `FieldComponent` gives every schema field, so a
    # page/post editor can lay out its typed fields and its column fields
    # side by side with identical read-only-original and error-slot
    # behaviour.
    class Base < Admin::AdminComponent
      # `id:`/`html_name:` exist for exactly one caller so far
      # (`Admin::PageSettingsFormComponent`, cs-studio spec §5.1/Task 4): a
      # page/post editor's own top-level form needs its inputs named with
      # bracket notation (`page[title]`) so the params it PATCHes arrive
      # nested the way `Admin::PagesController#update` expects, but the
      # *id* every Turbo Stream error-slot replace targets has to be
      # bracket-free to agree with `Admin::FieldComponent.error_id`'s
      # dash-joined `"#{prefix}-#{field}"` format -- Turbo resolves a
      # stream's `target` with `getElementById`, which tolerates brackets
      # just fine, but a *mismatched* id between what this renders and what
      # `Admin::AutosaveResponses` computes would silently no-op every
      # replace instead of raising. `name:` alone still drives the label
      # text and `data-field-name` exactly as before, so every existing
      # caller (a bare column name, no brackets in sight) is unaffected --
      # `id`/`html_name` default to it.
      #
      # `translation_state:` is this field's `Translations::Tracker
      # #translation_state` in the locale being edited, and
      # `translation_confirm:` what its "Mark as up to date" button posts
      # (nil for a viewer who can't) -- see `#reference_card`. Both are the
      # caller's to work out: only it knows the record behind the value.
      #
      # `**html` is the same "anything else passes through" escape hatch
      # `Admin::ButtonComponent` already uses, needed here so a caller can
      # wire a Stimulus target/action onto the actual `<input>` (the live
      # slug-preview controller, Task 4) without this component knowing
      # anything about that controller.
      def initialize(name:, value:, original: nil, errors: [], locale: nil, id: nil, html_name: nil,
        translation_state: nil, translation_confirm: nil, translation_record: nil, **html)
        @name = name
        @value = value
        @original = original
        @errors = errors
        @locale = locale
        @id = id || name
        @html_name = html_name || name
        @html = html
        @translation_state = translation_state
        @translation_record = translation_record
        @translation_confirm = translation_confirm
      end

      def show_original? = original.present?

      def errors_id = "#{id}-errors"

      # The card showing the primary-language original beside (or, in a
      # narrow column, above) the field (`Admin::EditorScreen
      # ::ReferenceCardComponent`). An `:outdated` card carries the "Original
      # changed" note (translation helpers spec §4) and its "Mark as up to
      # date" button; `:unknown` (a translation older than tracking) and
      # `:current` show nothing extra.
      def reference_card
        Admin::EditorScreen::ReferenceCardComponent.new(
          field: name, locale: locale, original: card_original, kind: card_kind,
          state: translation_state, confirm: translation_confirm, record: translation_record, suggest: suggest_update_button
        )
      end

      # The AI **Translate** button in the original's box (translation
      # helpers spec §6.4) -- it renders only for a viewer who may edit the
      # record (`translation_confirm` is handed over only then), with AI
      # set up and `ai.translate`; see `Admin::TranslationScreen
      # ::TranslateButtonComponent`. Nil when there's no confirm at all (the
      # primary language, an untracked column, a view-only viewer).
      def translate_button
        return unless translation_confirm

        Admin::TranslationScreen::TranslateButtonComponent.new(confirm: translation_confirm, **translate_target)
      end

      # **Suggest update** in an outdated card (same wrapper as Translate,
      # `mode: :update`); the card draws it only when it is outdated, and the
      # button itself only with AI set up and `ai.translate`.
      def suggest_update_button
        return unless translation_state == :outdated && translation_confirm

        Admin::TranslationScreen::TranslateButtonComponent.new(confirm: translation_confirm, mode: :update, **translate_target)
      end

      private

      def card_original = original

      def card_kind = :plain

      # The input's own invalid state (design pass spec §4). The danger BORDER
      # is not a server-rendered class: an autosave Turbo Stream replaces the
      # error slot alone, never the input, so a class would go stale. It comes
      # from CSS keyed on the slot's content instead (`.admin-column:has(
      # [id$="-errors"] > p)`, content-spiel.tailwind.css). `aria-invalid` /
      # `aria-describedby` stay server-rendered only (initial load).
      def input_class = setup_input_class

      def invalid_attrs
        errors.any? ? { aria: { invalid: "true", describedby: errors_id } } : {}
      end

      # What Use fills and how (`TranslateButtonComponent`): a plain column
      # its own input, measured as the text it is.
      def translate_target = { input_id: id, kind: :plain, characters: original.to_s.length }

      attr_reader :name, :value, :original, :errors, :locale, :id, :html_name, :html, :translation_state, :translation_confirm, :translation_record
    end
  end
end
