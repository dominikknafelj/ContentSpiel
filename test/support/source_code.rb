require "ripper"

# A source file's code with its comments blanked, for the guards that read the
# app's files: prose in a comment may name anything, and only code is held.
module SourceCode
  # A component class by name (`Admin::Ui::DialogComponent`, `BarComponent`),
  # for the guards that refuse one in a layer below the screens.
  COMPONENT = /(?:\b[A-Z]\w*::)*\b[A-Z]\w*Component\b/

  # A comment line per language. A CSS line may begin with "#id", so CSS has none.
  COMMENT_LINES = { ".rb" => /^\s*#.*$/, ".erb" => /^\s*#.*$/, ".js" => %r{^\s*//.*$} }.freeze

  # Ruby with every comment (a `#` line or tail, an `=begin` block) blanked and
  # the line breaks kept, so a line number still names the line. Ripper does
  # the lexing, so a `#` inside a string or an interpolation is not mistaken
  # for a comment.
  def self.without_ruby_comments(source)
    Ripper.lex(source).map do |(_position, type, token, _state)|
      type.to_s.match?(/\Aon_(comment|embdoc)/) ? token.gsub(/[^\n]/, "") : token
    end.join
  end

  # A file's code: Ruby's comments by Ripper; ERB's `<%# … %>` blocks, then the
  # `#` lines of its Ruby. Line breaks are kept.
  def self.code_of(path, source = File.read(path))
    case File.extname(path)
    when ".rb" then without_ruby_comments(source)
    when ".erb" then source.gsub(/<%#.*?%>/m) { |comment| comment.gsub(/[^\n]/, "") }.gsub(COMMENT_LINES.fetch(".erb"), "")
    else source
    end
  end
end
