# A registered mark type (`RichText::Schema.register_mark`) -- `bold`,
# `link`, `internalLink`, ... A mark decorates a `"text"` node via that
# node's `"marks"` array, rather than nesting like a node does (see
# `NodeType`). See `RichText::Schema::TypeDefinition` for the actual DSL;
# this class exists only to give `RichText::Schema` a distinct constant to
# instantiate for `register_mark`.
module RichText
  class MarkType
    include Schema::TypeDefinition
  end
end
