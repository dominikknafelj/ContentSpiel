module ContentModel
  # What a closed block's tile shows of a block beside its summary line: a
  # heading and a few words, as plain text. It is data and draws nothing (the
  # tile escapes it when it draws it, CS Studio only: no public template or
  # theme reads it). `mono` says the text is code and is set in the
  # monospace face. Both strings are cut here, so no type's callable has to
  # remember the lengths: the text at `PREVIEW_LENGTH`, the heading at
  # `SUMMARY_LENGTH`.
  Preview = Data.define(:heading, :text, :mono) do
    def initialize(heading: nil, text: nil, mono: false)
      super(
        heading: Preview.cut(heading, BlockTypeDefinition::SUMMARY_LENGTH),
        text: Preview.cut(text, BlockTypeDefinition::PREVIEW_LENGTH),
        mono: mono ? true : false
      )
    end

    # Cuts at `length` grapheme clusters, the ellipsis included, so a cut
    # never splits an emoji sequence or a letter and its accent.
    def self.cut(value, length)
      graphemes = value.to_s.strip.scan(/\X/)
      return graphemes.join.presence if graphemes.size <= length

      graphemes.first(length - 1).join.rstrip + "…"
    end

    def blank? = heading.blank? && text.blank?
  end
end
