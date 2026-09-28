# A registered mark type (`RichText::Schema.register_mark`) -- `bold`,
# `link`, `internalLink`, ... A mark decorates a `"text"` node via that
# node's `"marks"` array, rather than nesting like a node does (see
# `NodeType`). See `RichText::Schema::TypeDefinition` for the shared DSL.
#
# `excludes` (final fix wave, A) is ProseMirror's mark-spec field of the
# same name and meaning: which other mark types can't sit on the same text
# as this one. Not given, a mark excludes only itself (a text run is bold
# once, and links to one place); `"_"` excludes every mark (Tiptap's `code`:
# nothing else applies inside a code span); otherwise a space-separated
# list of names. ProseMirror refuses a mark set where *either* mark of a
# pair excludes the other, and so does `RichText::Document#validate`
# (`#excludes?` below, checked both ways).
module RichText
  class MarkType
    include Schema::TypeDefinition

    def excludes(expression = nil)
      return @excludes unless expression

      @excludes = expression.to_s
    end

    def excludes?(other)
      case @excludes
      when nil then other.name == name
      when "_" then true
      else @excludes.split.include?(other.name)
      end
    end
  end
end
