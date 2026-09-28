# A registered node type (`RichText::Schema.register_node`) -- `paragraph`,
# `heading`, `youtube`, ... A node is the kind of Tiptap document element
# that nests inside another node's `"content"` array (as opposed to a mark,
# which decorates a `"text"` node's `"marks"` array -- see `MarkType`). The
# shared DSL (`attribute`, `html`, `markdown_out`, `markdown_in`,
# `directive`) lives in `RichText::Schema::TypeDefinition`, shared with
# `MarkType`; the content model below is node-only.
#
# `group`/`content` (final fix wave, A) are ProseMirror's own node-spec
# fields of the same names, restated for the server so
# `RichText::Document#validate` enforces the exact content model the
# editor does (`RichText::ContentExpression`'s comment has the why):
# - `group` -- which group name a parent's content expression can use to
#   admit this node. Defaults to `"block"`, what every embed-like plugin
#   node will be; the two inline built-ins (`text`, `hardBreak`) say
#   `"inline"`.
# - `content(expression, marks: true)` -- which children this node takes.
#   No declaration means a leaf (ProseMirror's own default: no content
#   allowed), which is what `youtube`/`image`/`horizontalRule`/`hardBreak`
#   and a directive-only plugin node are. `marks: false` is ProseMirror's
#   `marks: ""` -- the children may carry no marks (`codeBlock`).
module RichText
  class NodeType
    include Schema::TypeDefinition

    def group(name = nil)
      return @group || "block" unless name

      @group = name.to_s
    end

    def content(expression = nil, marks: true)
      return @content unless expression

      @content = RichText::ContentExpression.parse(expression)
      @children_marks = marks
      @content
    end

    # Whether a child of this node may carry marks: only inline content
    # (ProseMirror gives a block container an empty mark set), and not when
    # `content(..., marks: false)` said so.
    def allows_child_marks? = @content&.inline? && @children_marks != false
  end
end
