# Rewrites a document Hash built from *outside* input -- Markdown
# (`RichText::Markdown::Loader`), stored ActionText HTML
# (`RichText::HtmlImport`) -- into one that satisfies the editor's content
# model (final fix wave, A), and says what it had to change.
#
# `RichText::Document#validate` refuses anything Tiptap/ProseMirror would
# refuse to load (`RichText::ContentExpression`'s comment). The two
# importers can't simply build such documents by construction: CommonMark
# and HTML both express things the model doesn't allow -- a bold code span
# (`**`x`**`), an empty `>` quote, a list item that opens with an embed, an
# empty fence. Refusing the whole write over those would make MCP brittle
# for no reader's benefit, so this repairs them the one agreed way:
#
# - `code` plus another mark: if a `link`/`internalLink` is among them the
#   link wins and `code` goes (a link is content, a code face is only
#   styling); otherwise `code` stays and the rest go. Warned.
# - the same mark type twice (nested `**a **b** c**`): kept once. Silent --
#   nothing is lost.
# - an empty text node: dropped. Silent.
# - text inside a `codeBlock` carrying marks: marks dropped (can't happen
#   from Markdown; cheap insurance for HTML).
# - a `listItem` whose first child isn't a paragraph (empty, or an embed
#   first): an empty paragraph is put in front. Silent -- it's how the
#   editor itself represents "an item that starts with an embed".
# - an empty `blockquote`/`bulletList`/`orderedList` (after the rules
#   above, so a quote holding only dropped content counts as empty):
#   dropped. Warned.
#
# Anything else invalid (an unknown type, a bad attribute) is left alone
# for `#validate` to report -- each importer already degrades those
# itself, before this runs. Recursive with the same `MAX_DEPTH` ceiling
# the importers build under; past it (which neither produces) a subtree is
# returned untouched rather than walked.
module RichText
  class ContentRepair
    LINK_MARKS = %w[link internalLink].freeze
    DROPPED_WHEN_EMPTY = %w[blockquote bulletList orderedList].freeze

    def self.call(hash) = new.call(hash)

    def initialize
      @warnings = []
    end

    # Returns `[repaired_hash, warnings]`. `hash` isn't modified.
    def call(hash)
      [ repair_node(hash, 0, parent: nil) || RichText::Document::EMPTY_HASH.deep_dup, @warnings.uniq ]
    end

    private

    def repair_node(node, depth, parent:)
      return node unless node.is_a?(Hash)
      return node if depth > RichText::Document::MAX_DEPTH
      return repair_text(node, parent) if node["type"] == "text"

      node = node.merge("marks" => repair_marks(node["marks"])) if node["marks"].is_a?(Array)
      node.delete("marks") if node["marks"] == []
      return node unless node["content"].is_a?(Array)

      content = node["content"].filter_map { |child| repair_node(child, depth + 1, parent: node["type"]) }
      content.unshift({ "type" => "paragraph", "content" => [] }) if node["type"] == "listItem" && content.first&.dig("type") != "paragraph"

      if DROPPED_WHEN_EMPTY.include?(node["type"]) && content.empty?
        @warnings << "dropped an empty #{node["type"]}"
        return nil
      end

      node.merge("content" => content)
    end

    def repair_text(node, parent)
      return nil if node["text"].is_a?(String) && node["text"].empty?
      return node unless node["marks"].is_a?(Array)

      marks = parent == "codeBlock" ? [] : repair_marks(node["marks"])
      marks.empty? ? node.except("marks") : node.merge("marks" => marks)
    end

    def repair_marks(marks)
      marks = marks.uniq { |mark| mark.is_a?(Hash) ? mark["type"] : mark.object_id }
      types = marks.filter_map { |mark| mark["type"] if mark.is_a?(Hash) }
      return marks unless types.include?("code") && types.size > 1

      if types.intersect?(LINK_MARKS)
        @warnings << "dropped code formatting from linked text (a link can't also be code)"
        marks.reject { |mark| mark.is_a?(Hash) && mark["type"] == "code" }
      else
        @warnings << "dropped other formatting from code text (code can't be combined with other marks)"
        marks.select { |mark| mark.is_a?(Hash) && mark["type"] == "code" }
      end
    end
  end
end
