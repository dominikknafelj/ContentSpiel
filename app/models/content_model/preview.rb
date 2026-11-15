module ContentModel
  # What a closed block's tile shows of a block beside its summary line: a
  # heading and a few words, as plain text. It is data and draws nothing (the
  # tile escapes it when it draws it, CS Studio only: no public template or
  # theme reads it). `mono` says the text is code and is set in the
  # monospace face. Both strings are cut here, so no type's callable has to
  # remember the lengths: the text at `PREVIEW_LENGTH`, the heading at
  # `SUMMARY_LENGTH`.
  #
  # `quiet_heading` draws the heading in the meta colour at weight 500, for a
  # heading the CMS supplies where the editor wrote none (the Search block's
  # visitor word under a blank label), so it reads as a default, not as
  # typed words. `line` asks the tile to draw the type's summary line under
  # the heading, in place of a text, where the line is what a reader needs
  # beside the heading (the Search block's "Searches the live site"); a
  # preview that has a text and asks for the line is refused, since the
  # tile describes the face by one of the two.
  Preview = Data.define(:heading, :text, :mono, :quiet_heading, :line) do
    def initialize(heading: nil, text: nil, mono: false, quiet_heading: false, line: false)
      text = Preview.cut(text, BlockTypeDefinition::PREVIEW_LENGTH)
      raise ArgumentError, "a preview that asks for the summary line draws it in place of its text: give one or the other" if line && text

      super(
        heading: Preview.cut(heading, BlockTypeDefinition::SUMMARY_LENGTH),
        text: text,
        mono: mono ? true : false,
        quiet_heading: quiet_heading ? true : false,
        line: line ? true : false
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
