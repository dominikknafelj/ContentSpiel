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
# on the list (a list that shrank, a row written around the services), a
# lexer that raises and a lex that takes too long are all plain text.
#
# WHAT BOUNDS THE TIME. Rouge's lexers are regular expressions, so a crafted
# input can be slow, and three things bound it, none of them alone:
# - the block's limit (`MAX_CHARACTERS`): longer code is never lexed;
# - Rails' `Regexp.timeout`, one second for ONE match (`load_defaults 8.1`
#   sets it), which raises `Regexp::TimeoutError`: plain text. It says
#   nothing about a lex of many matches that each stay under it;
# - `LEX_SECONDS`, the deadline for one WHOLE lex, on the monotonic clock.
#   It is checked before every step of every Rouge regex lexer (`EachStep`,
#   prepended once to `Rouge::RegexLexer`) and again for every token that
#   reaches `coloured`, never by `Timeout.timeout`, which interrupts
#   anywhere. The check has to be inside Rouge: `Lexer#continue_lex` joins
#   neighbouring tokens of one type before it yields them, so a text of one
#   token type yields once, at the end, and a check between yielded tokens
#   would never run in time.
# So one lex costs at most `LEX_SECONDS` plus the one match that was running
# when the deadline passed (under a second, by the timeout above).
#
# The honest cost is far below it: 20,000 characters lex in 2 to 120 ms in
# each of the twenty languages (measured on a laptop, 2026-10-12), so
# `LEX_SECONDS` is four times the slowest and still a wait a visitor
# forgives once.
#
# ROUGE'S LEXERS CALL EACH OTHER, so the code that runs is not only the
# twenty listed lexers': HTML hands a script to JavaScript and a style to
# CSS, ERB and PHP hand what is around them to HTML, a Dockerfile hands its
# commands to the shell lexer, and Markdown hands a fenced block to WHATEVER
# lexer its first line names (` ```elixir `), with Rouge's own guess for a
# fence that names none. That is accepted, not closed (closing it means a
# copy of Markdown's fence rule here): such a block is coloured by that
# lexer, its tokens go through `RULES` like any other, so a role is still
# one of the seven, and it runs inside the same lex under the same deadline,
# because the check is in every regex lexer and not in the listed ones.
#
# WHAT IS CACHED is these lines, not HTML, so a theme's template is never
# inside the cache. The key is the code's digest, the language, Rouge's
# version and `REVISION`: bump `REVISION` when `RULES` changes. A FAILURE is
# cached too, under a key of its own and for `FAILURE_TTL` only: the same
# code fails the same way on the next request, and a public page is rendered
# for every request that brings no ETag, so an uncached failure is paid by
# every visitor (final review I1). While that entry lives the block is drawn
# plain without a lex; it heals when the entry lapses (a failure of one bad
# moment), or at once when the code, the language, Rouge or the revision
# changes, since each is in the key. With a cache that stores nothing
# (development's default) every request lexes and logs again.
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
  ROLES = %w[comment keyword string constant tag attribute embed].map(&:freeze).freeze

  # Rouge's token names by prefix, most specific first. `Comment.Preproc` is
  # `embed`, which is what makes ERB's delimiters stand out. Everything that
  # matches none is plain. The strings are frozen: a role is handed out by
  # reference, and a template must not be able to write to the table.
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
  ].map { |prefix, role| [ prefix.freeze, role.freeze ].freeze }.freeze

  module_function

  def label(language) = LANGUAGES[language.to_s]

  # The deadline of one whole lex, in seconds, and how long a failure is
  # remembered. A test shortens the first through `budget` and moves the
  # clock through `now`.
  LEX_SECONDS = 0.5
  FAILURE_TTL = 5.minutes

  TooSlow = Class.new(StandardError)

  # Where the running lex's deadline check is kept: for this fiber only, and
  # only while `within_budget` runs.
  CHECK = :code_highlight_check

  # The check inside Rouge (see the top of the file). It names nothing of
  # this module but the key, on purpose: in development this file is
  # reloaded and Rouge is not, so the module prepended first stays the one
  # that runs. A change to it needs a restart.
  module EachStep
    def step(state, stream)
      Thread.current[:code_highlight_check]&.call
      super
    end
  end
  # `Module#prepend` by name: `Rouge::RegexLexer.prepend` is Rouge's own
  # method for adding rules to a state.
  unless Rouge::RegexLexer.ancestors.any? { |ancestor| ancestor.name == "CodeHighlight::EachStep" }
    Module.instance_method(:prepend).bind_call(Rouge::RegexLexer, EachStep)
  end

  # `block_id` is only for the log line of a lex that failed. Code over
  # `MAX_CHARACTERS` (a row written around the services) is not lexed and
  # not cached. One read answers both keys: the lines of a lex that worked,
  # or the mark of one that failed, which is plain text without a lex.
  def lines(code, language, block_id: nil)
    code = text(code)
    lexer = code.length > MAX_CHARACTERS ? nil : lexer_for(language)
    return plain(code) if lexer.nil?

    key = cache_key(code, language)
    failed = failure_key(code, language)
    found = Rails.cache.read_multi(key, failed)
    return found[key] if found[key]
    return plain(code) if found[failed]

    begin
      lines = coloured(code, lexer)
    rescue StandardError => error
      fail_for_a_while(failed, language, block_id, error)
      return plain(code)
    end
    Rails.cache.write(key, lines)
    lines
  end

  # Any string as UTF-8 text with Unix line breaks, and never an error:
  # bytes that are not text (invalid UTF-8, a binary string) become U+FFFD,
  # so a visitor sees a replacement character where they were, and a string
  # in another encoding is transcoded, its bad bytes replaced the same way
  # (`scrub` alone raises `Encoding::CompatibilityError` there). An encoding
  # Ruby cannot convert from (UTF-16 without a byte order, UTF-7) is read as
  # the bytes it is.
  def text(code)
    code = code.to_s
    code = code.dup.force_encoding(Encoding::UTF_8) if code.encoding == Encoding::BINARY
    code = transcoded(code) unless code.encoding == Encoding::UTF_8
    code.scrub("\uFFFD").gsub(/\r\n?/, "\n")
  end

  def transcoded(code)
    code.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "\uFFFD")
  rescue EncodingError
    code.b.force_encoding(Encoding::UTF_8)
  end

  def cache_key(code, language) = [ "code", Digest::SHA256.hexdigest(code), language.to_s, Rouge.version, REVISION ]

  # The same four parts under another first word, so a failure is never read
  # as lines and a success never as a failure.
  def failure_key(code, language) = [ "code-failed", *cache_key(code, language).drop(1) ]

  def lexer_for(language) = LANGUAGES.key?(language.to_s) ? Rouge::Lexer.find(language.to_s) : nil

  # Raises for a failure of any kind: a lexer that raises, one match past
  # `Regexp.timeout`, the whole lex past its deadline. `each` runs the lexer
  # here, inside the budget: `lex` alone answers a lazy enumerator. Nothing
  # of a lex that failed partway is kept.
  def coloured(code, lexer)
    pairs = []
    within_budget do |check|
      lexer.lex(code).each do |token, text|
        check.call
        pairs << [ role_of(token), text ]
      end
    end
    split_lines(pairs)
  end

  def within_budget
    deadline = now + budget
    check = -> { raise TooSlow if now > deadline }
    Thread.current[CHECK] = check
    yield check
  ensure
    Thread.current[CHECK] = nil
  end

  def budget = LEX_SECONDS

  def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  # One entry and one log line per failure and `FAILURE_TTL`. The line names
  # the block and the error's class, never the code or the error's message,
  # which can quote it.
  def fail_for_a_while(key, language, block_id, error)
    Rails.cache.write(key, true, expires_in: FAILURE_TTL)
    Rails.logger.warn("CodeHighlight: the #{language} lexer raised #{error.class} for block #{block_id.inspect}; drawn as plain text for #{FAILURE_TTL.inspect}")
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
