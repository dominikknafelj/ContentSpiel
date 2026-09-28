# A registered node type (`RichText::Schema.register_node`) -- `paragraph`,
# `heading`, `youtube`, ... A node is the kind of Tiptap document element
# that nests inside another node's `"content"` array (as opposed to a mark,
# which decorates a `"text"` node's `"marks"` array -- see `MarkType`). All
# of the actual DSL (`attribute`, `html`, `markdown_out`, `markdown_in`,
# `directive`) lives in `RichText::Schema::TypeDefinition`, shared with
# `MarkType`; this class exists so `RichText::Schema` has a distinct
# constant to instantiate for `register_node`, keeping node and mark types
# as different Ruby classes even though they behave identically.
module RichText
  class NodeType
    include Schema::TypeDefinition
  end
end
