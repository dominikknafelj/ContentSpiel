# A node type's allowed children (final fix wave, A) -- the same
# content-expression language ProseMirror's own schema uses (`"block+"`,
# `"inline*"`, `"paragraph block*"`), cut down to the subset this schema
# actually needs: a space-separated *sequence* of terms, each a node type
# name or a group name (`block`, `inline`) with an optional `+`/`*`/`?`
# quantifier. No alternation (`a | b`), no parentheses, no `{n,m}` ranges
# -- none of the built-ins use them, and a plugin that needs one can
# register a group instead.
#
# Why a mirror of ProseMirror's rule, not a looser server-only one: the
# editor loads a stored document with `enableContentCheck`, which runs
# ProseMirror's own `Node#check` and refuses the whole document on any
# mismatch (CS Studio then shows it read-only, `admin--rich-text--editor
# #handleInvalidContent`). Everything `RichText::Document#validate`
# accepts must therefore be something the editor accepts too, or a body
# written through MCP/Markdown becomes uneditable -- the final review's
# Important #1. The vendored extensions' specs are the source of truth
# (`vendor/javascript/@tiptap--extension-*.js`, plus `rich_text/*.js`), and
# `RichText::BuiltIns` restates each one next to its registration.
#
# Matching is greedy and never backtracks, which is exact for sequences
# without alternation as long as no term can also match what the *next*
# term needs after a `+`/`*` ran out -- true for every expression here
# (`"paragraph block*"`: the one `paragraph` term takes exactly one child
# before `block*` takes the rest).
module RichText
  class ContentExpression
    Term = Data.define(:name, :min, :max)

    TERM_FORMAT = /\A([a-z][A-Za-z0-9]*(?:\/[a-z][A-Za-z0-9_]*)?)([+*?]?)\z/

    attr_reader :source, :terms

    def self.parse(source)
      terms = source.to_s.split.map do |part|
        match = TERM_FORMAT.match(part)
        raise ArgumentError, "invalid content expression #{source.inspect} (term #{part.inspect})" unless match

        min, max = { "" => [ 1, 1 ], "?" => [ 0, 1 ], "*" => [ 0, nil ], "+" => [ 1, nil ] }.fetch(match[2])
        Term.new(name: match[1], min: min, max: max)
      end
      new(source.to_s, terms)
    end

    def initialize(source, terms)
      @source = source
      @terms = terms.freeze
      freeze
    end

    # Whether `types` (the children's registered `RichText::NodeType`s, in
    # order) satisfies this expression -- every child consumed, every term's
    # minimum met.
    def match?(types)
      index = 0
      terms.each do |term|
        count = 0
        while index < types.size && (term.max.nil? || count < term.max) && term_matches?(term, types[index])
          index += 1
          count += 1
        end
        return false if count < term.min
      end
      index == types.size
    end

    # ProseMirror's `inlineContent`: a node whose children are inline (text,
    # hardBreak) rather than blocks. Only such a node's children may carry
    # marks at all (ProseMirror gives every other node an empty mark set).
    def inline? = terms.any? { |term| term.name == "inline" || term.name == "text" }

    private

    def term_matches?(term, type) = type.name == term.name || type.group == term.name
  end
end
