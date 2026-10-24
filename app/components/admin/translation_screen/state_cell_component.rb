module Admin
  module TranslationScreen
    # A Translations cell (layout points spec, decision 7): the state as a
    # mark and a word; the column's header names the language. The marks are
    # the chip's own (`Ui::TranslationChipComponent::STYLES`), so the two cannot
    # drift; the chip stays as it is in the posts list.
    class StateCellComponent < Admin::AdminComponent
      TEXT = { complete: "text-ink", missing: "text-meta", outdated: "text-warn-ink" }.freeze

      def initialize(state:, locale:)
        @state = state.to_sym
        @style = Admin::Ui::TranslationChipComponent::STYLES.fetch(@state)
        @locale = locale.to_s
      end

      def call
        mark = if @style[:mark]
          tag.span("", class: "inline-block shrink-0 #{@style[:mark]}", aria: { hidden: true }, data: { translation_mark: @state })
        else
          tag.span(@style[:glyph], aria: { hidden: true }, data: { translation_mark: @state })
        end
        tag.span(safe_join([ mark, t(".#{@state}") ]),
          class: "admin-translation-state inline-flex items-center gap-1.5 text-sm #{TEXT.fetch(@state)}",
          data: { locale: @locale, translation_state: @state })
      end
    end
  end
end
