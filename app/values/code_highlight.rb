require "rouge"

# Source code cut into the seven colour roles a theme has tokens for (code
# block spec §2), on the server, so a public page needs no script to colour
# code. `lines` answers data, never markup: one array per line of
# [role, text] pairs, the role nil for plain text. The template decides the
# elements and the class names; this decides only what is a keyword.
#
# THE ONE PLACE THAT NAMES ROUGE. Rouge was a development gem (it came with
# Lookbook); a visitor's request runs it now. So it is confined here, and
# nothing here may fail a page: no language, a stored language that is not
# on the list (a list that shrank, a row written around the services) and a
# lexer that raises are all plain text. Rouge's lexers are regular
# expressions, so a crafted input could be slow; the block's limit
# (`MAX_CHARACTERS`) bounds it, an editor is the only author and the result
# is cached, so a slow one is paid once per change. If one is ever found,
# `Regexp.timeout` around the lex, with the same plain answer, is the fix.
#
# WHAT IS CACHED is these lines, not HTML, so a theme's template is never
# inside the cache. The key is the code's digest, the language, Rouge's
# version and `REVISION`: bump `REVISION` when `RULES` changes.
module CodeHighlight
  MAX_CHARACTERS = 20_000
  REVISION = 1

  # Rouge's tag => the label an editor reads (and a visitor, above the code).
  # The list only grows: a stored tag that is no longer here is drawn plain.
  LANGUAGES = {
    "shell" => "Shell", "css" => "CSS", "docker" => "Dockerfile", "erb" => "ERB", "go" => "Go",
    "html" => "HTML", "ini" => "INI", "javascript" => "JavaScript", "json" => "JSON", "markdown" => "Markdown",
    "nginx" => "nginx", "php" => "PHP", "python" => "Python", "ruby" => "Ruby", "rust" => "Rust",
    "sql" => "SQL", "toml" => "TOML", "typescript" => "TypeScript", "xml" => "XML", "yaml" => "YAML"
  }.freeze

  # The seven roles, each a theme token (`--th-syn-<role>`) and a class
  # (`syn-<role>`). Strings, so the cached lines read the same whatever
  # serializer the cache store uses.
  ROLES = %w[comment keyword string constant tag attribute embed].freeze

  # Rouge's token names by prefix, most specific first. `Comment.Preproc` is
  # `embed`, which is what makes ERB's delimiters stand out. Everything that
  # matches none is plain.
  RULES = [
    [ "Comment.Preproc", "embed" ],
    [ "Comment", "comment" ],
    [ "Keyword", "keyword" ],
    [ "Literal.String.Symbol", "constant" ],
    [ "Literal.String", "string" ],
    [ "Literal.Number", "constant" ],
    [ "Name.Variable.Instance", "constant" ],
    [ "Name.Constant", "constant" ],
    [ "Name.Tag", "tag" ],
    [ "Name.Attribute", "attribute" ]
  ].freeze

  module_function

  def label(language) = LANGUAGES[language.to_s]

  # `block_id` is only for the log line of a lexer that raised. Bytes that are
  # not text (invalid UTF-8, a binary-encoded string) are scrubbed to U+FFFD
  # first, so a visitor sees a replacement character where they were and
  # nothing raises. Code over `MAX_CHARACTERS` (a row written around the
  # services) is not lexed and not cached. A failed lex is plain text for this
  # call only: `skip_nil` keeps the failure (nil) out of the cache, so the
  # next call tries again.
  def lines(code, language, block_id: nil)
    code = code.to_s
    code = code.dup.force_encoding(Encoding::UTF_8) if code.encoding == Encoding::BINARY
    code = code.scrub("\uFFFD").gsub(/\r\n?/, "\n")
    lexer = code.length > MAX_CHARACTERS ? nil : lexer_for(language)
    return plain(code) if lexer.nil?

    Rails.cache.fetch(cache_key(code, language), skip_nil: true) { coloured(code, lexer, language, block_id) } || plain(code)
  end

  def cache_key(code, language) = [ "code", Digest::SHA256.hexdigest(code), language.to_s, Rouge.version, REVISION ]

  def lexer_for(language) = LANGUAGES.key?(language.to_s) ? Rouge::Lexer.find(language.to_s) : nil

  # Answers nil for a failure (the caller draws plain text and does not cache it).
  # `map` runs the lexer here, inside the rescue: `lex` alone answers a lazy
  # enumerator. The log line names the block and never the code or the
  # error's message, which can quote it.
  def coloured(code, lexer, language, block_id)
    split_lines(lexer.lex(code).map { |token, text| [ role_of(token), text ] })
  rescue StandardError => error
    Rails.logger.warn("CodeHighlight: the #{language} lexer raised #{error.class} for block #{block_id.inspect}; drawn as plain text")
    nil
  end

  def plain(code) = split_lines([ [ nil, code ] ])

  def role_of(token)
    name = token.qualname
    RULES.find { |prefix, _role| name == prefix || name.start_with?("#{prefix}.") }&.last
  end

  # Pairs cut at line breaks, neighbours of one role joined. The line break
  # after the last line adds no line, and no code is no line at all.
  def split_lines(pairs)
    lines = [ [] ]
    pairs.each do |role, text|
      text.split(/(\n)/).each do |part|
        next if part.empty?
        next lines << [] if part == "\n"

        last = lines.last.last
        last && last[0] == role ? last[1] << part : lines.last << [ role, part ]
      end
    end
    lines.pop if lines.last.empty?
    lines
  end
end
