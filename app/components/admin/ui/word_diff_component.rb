module Admin
  module Ui
    # The segments of a word diff (`Translations::SourceDiff#segments`) as
    # markup -- the one place the del/ins look lives, shared by the translation
    # reference card and the audit event page. A removed word is struck through in
    # the danger tint, an added one underlined in the ok tint (this is the
    # diff style, not an error), and each carries a screen-reader-only cue inside
    # the element: `aria-label` on `del`/`ins` (name-prohibited roles) is
    # unreliable and may replace the word itself, so "Removed: " / "Added: " is
    # real text. Every text is escaped (`content_tag`/`safe_join`), never
    # `html_safe`.
    class WordDiffComponent < AdminComponent
      def initialize(segments:)
        @segments = segments
      end

      def call
        safe_join(@segments.map { |kind, text| segment_tag(kind, text) })
      end

      private

      def cue(label) = content_tag(:span, label, class: "sr-only")

      def segment_tag(kind, text)
        case kind
        when :delete then content_tag(:del, safe_join([ cue("Removed: "), text ]), class: "text-danger-ink bg-danger-tint")
        when :insert then content_tag(:ins, safe_join([ cue("Added: "), text ]), class: "text-ok-ink bg-ok-tint underline decoration-ok-ink")
        else content_tag(:span, text)
        end
      end
    end
  end
end
