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
        heading: heading.to_s.strip.truncate(BlockTypeDefinition::SUMMARY_LENGTH).presence,
        text: text.to_s.strip.truncate(BlockTypeDefinition::PREVIEW_LENGTH).presence,
        mono: mono ? true : false
      )
    end

    def blank? = heading.blank? && text.blank?
  end
end
