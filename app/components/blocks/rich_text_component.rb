module Blocks
  # Free-form rich text (`BlockTypes::RichText`). Ported verbatim from the old
  # (now deleted) `content_blocks` `_rich_text` partial -- `body` is rendered through `rich_text`
  # (ThemeHelper), which walks `Locales.fallback_chain` for a locale left
  # blank.
  class RichTextComponent < ApplicationComponent
    def initialize(block:, page:)
      @block = block
      @page = page
    end

    private

    attr_reader :block, :page
  end
end
