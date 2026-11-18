# The app's own JavaScript without its comments, as production serves it
# (`ContentSpiel::JsCommentCompiler`, registered by
# config/initializers/assets.rb in production only). The comments stay in the
# source: they are long and load-bearing on purpose, and only the files a
# visitor's browser downloads go without them.
#
# Deliberately narrow, so it can never change what the code does:
#
# - A line whose first non-blank characters are `//` becomes an empty line.
# - A `/* … */` block whose `/*` is a line's first non-blank characters
#   becomes empty lines through the line holding its `*/`, but only when
#   nothing but blanks follows that `*/`; otherwise the block stays whole.
# - Nothing else changes: not a comment at the end of a line of code, not a
#   block that starts after code, not the indentation, not one other byte.
#   Every line break stays, so a line of a production stack trace is the
#   same line of the source and no source map is needed.
# - Kept whatever they are: `/*! … */` (a legal comment), `//# …` and
#   `//@ …` (`sourceMappingURL`, `sourceURL`) and `/*# … */`.
# - Only at the top level of the code: a line inside a string, a template
#   literal (a template's text, and the code of a `${…}` within it) or a
#   comment that started on an earlier line is never looked at, so a
#   template spanning lines whose line starts with `//` stays exactly as is.
#
# To know where the top level is, the scan follows `'…'`, `"…"` and
# `` `…` `` with `${…}` nested to any depth, comments, and regular-expression
# literals (a `/` after a value is division, anywhere else it starts a
# regex, read through its escapes and `[…]` classes). Where that reading is
# uncertain (a string or a regex that reaches the end of its line, a comment
# or template never closed, a `}` with no `${` to close) the file is handed
# back untouched and the result says why: a file served with its comments
# is only larger, while one misread could be broken.
#
# Plain Ruby, in lib/ and required from config/application.rb: the
# initializer hands the compiler to Propshaft, which keeps it for the life
# of the process.
module ContentSpiel
  class JsCommentStripper
    # Part of the assets' version in production (config/initializers/assets.rb),
    # so every digest changes when what this class writes changes: Propshaft
    # digests a file's source, and a new rule over the same source would
    # otherwise be served under the old, cached-for-a-year address.
    REVISION = "1"

    Result = Data.define(:output, :untouched) do
      def stripped? = untouched.nil?
    end

    class Uncertain < StandardError; end

    def self.call(source) = new(source).call

    # Words after which a `/` starts a regex, not a division.
    EXPRESSION_KEYWORDS = %w[
      return typeof instanceof in of new delete void throw case do else yield await
    ].freeze

    NEWLINE = 0x0A
    SLASH = 0x2F
    STAR = 0x2A
    BACKSLASH = 0x5C
    BACKTICK = 0x60
    DOLLAR = 0x24
    OPEN_BRACE = 0x7B
    CLOSE_BRACE = 0x7D
    OPEN_BRACKET = 0x5B
    CLOSE_BRACKET = 0x5D
    CLOSE_PAREN = 0x29
    QUOTES = [ 0x22, 0x27 ].freeze
    BLANKS = [ 0x20, 0x09, 0x0D, 0x0B, 0x0C ].freeze
    KEPT_AFTER_SLASHES = [ 0x23, 0x40 ].freeze # `//#`, `//@`
    KEPT_AFTER_STAR = [ 0x21, 0x23 ].freeze    # `/*!`, `/*#`

    def initialize(source)
      @source = source
      @bytes = source.b
    end

    def call
      removed = scan
      Result.new(output: removed.empty? ? @source : rebuild(removed), untouched: nil)
    rescue Uncertain => e
      Result.new(output: @source, untouched: e.message)
    end

    private
      # The byte ranges to empty, each from a line's start to the end of its
      # last line (its line break excluded).
      def scan
        b = @bytes
        n = b.bytesize
        removed = []
        # One frame per open template (`:template`) and per `${` inside one
        # (`[:code, braces]`); empty at the top level.
        stack = []
        # Whether a `/` here starts a regex: true after punctuation or a
        # keyword, false after a value.
        regex_ok = true
        i = 0

        while i < n
          if stack.empty? && (i.zero? || b.getbyte(i - 1) == NEWLINE)
            j = i
            j += 1 while j < n && BLANKS.include?(b.getbyte(j))
            if b.getbyte(j) == SLASH && b.getbyte(j + 1) == SLASH && !KEPT_AFTER_SLASHES.include?(b.getbyte(j + 2))
              eol = b.index("\n", j) || n
              removed << (i...eol)
              i = eol
              next
            elsif b.getbyte(j) == SLASH && b.getbyte(j + 1) == STAR && !KEPT_AFTER_STAR.include?(b.getbyte(j + 2))
              close = b.index("*/", j + 2) or raise Uncertain, "a /* comment is never closed"
              eol = b.index("\n", close + 2) || n
              if b.byteslice(close + 2, eol - close - 2).bytes.all? { |c| BLANKS.include?(c) }
                removed << (i...eol)
                i = eol
                next
              end
            end
          end

          c = b.getbyte(i)

          if stack.last == :template
            if c == BACKSLASH
              i += 2
            elsif c == BACKTICK
              stack.pop
              regex_ok = false
              i += 1
            elsif c == DOLLAR && b.getbyte(i + 1) == OPEN_BRACE
              stack.push([ :code, 0 ])
              regex_ok = true
              i += 2
            else
              i += 1
            end
            next
          end

          if c == NEWLINE || BLANKS.include?(c)
            i += 1
          elsif c == SLASH
            following = b.getbyte(i + 1)
            if following == SLASH
              i = b.index("\n", i) || n
            elsif following == STAR
              close = b.index("*/", i + 2) or raise Uncertain, "a /* comment is never closed"
              i = close + 2
            elsif regex_ok
              i = skip_regex(i)
              regex_ok = false
            else
              regex_ok = true
              i += 1
            end
          elsif QUOTES.include?(c)
            i = skip_string(i, c)
            regex_ok = false
          elsif c == BACKTICK
            stack.push(:template)
            i += 1
          elsif c == OPEN_BRACE
            stack.last[1] += 1 if stack.last
            regex_ok = true
            i += 1
          elsif c == CLOSE_BRACE
            frame = stack.last
            if frame && frame[1].zero?
              stack.pop # back in the template's text
            elsif frame
              frame[1] -= 1
            end
            # After a block's `}` a statement, and so a regex, may start.
            regex_ok = true
            i += 1
          elsif c == CLOSE_PAREN || c == CLOSE_BRACKET
            regex_ok = false
            i += 1
          elsif word_byte?(c)
            start = i
            i += 1 while i < n && word_byte?(b.getbyte(i))
            regex_ok = EXPRESSION_KEYWORDS.include?(b.byteslice(start, i - start))
          else
            regex_ok = true
            i += 1
          end
        end

        raise Uncertain, "a template literal is never closed" unless stack.empty?

        removed
      end

      def skip_string(i, quote)
        b = @bytes
        i += 1
        loop do
          c = b.getbyte(i)
          raise Uncertain, "a string reaches the end of the file" if c.nil?
          raise Uncertain, "a string reaches the end of its line" if c == NEWLINE
          return i + 1 if c == quote

          i += c == BACKSLASH ? 2 : 1
        end
      end

      def skip_regex(i)
        b = @bytes
        i += 1
        in_class = false
        loop do
          c = b.getbyte(i)
          raise Uncertain, "a regular expression reaches the end of its line" if c.nil? || c == NEWLINE

          if c == BACKSLASH
            i += 2
            next
          end
          if in_class
            in_class = false if c == CLOSE_BRACKET
          elsif c == OPEN_BRACKET
            in_class = true
          elsif c == SLASH
            return i + 1
          end
          i += 1
        end
      end

      # Identifier and number bytes; any byte of a multi-byte character too.
      def word_byte?(c)
        (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) ||
          c == 0x5F || c == DOLLAR || c >= 0x80 || c == 0x2E
      end

      # The source with each removed range replaced by its line breaks alone.
      def rebuild(removed)
        out = +""
        at = 0
        removed.each do |range|
          out << @bytes.byteslice(at, range.begin - at)
          out << ("\n" * @bytes.byteslice(range.begin, range.size).count("\n"))
          at = range.end
        end
        out << @bytes.byteslice(at, @bytes.bytesize - at)
        out.force_encoding(@source.encoding)
      end
  end
end
