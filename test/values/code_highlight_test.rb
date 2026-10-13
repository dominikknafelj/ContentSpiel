require "test_helper"

# `CodeHighlight` cuts source into lines of [role, text] pairs (code block spec
# §2). The pairs asserted here were read off Rouge 5.1.0; a Rouge upgrade that
# changes one fails here, and the answer is a look at the page and a bump of
# `CodeHighlight::REVISION` if the role table changes.
class CodeHighlightTest < ActiveSupport::TestCase
  include LogCapture

  # Rouge is required by CodeHighlight alone; touch it so a test that names Rouge first finds it.
  setup { CodeHighlight }

  RAISING = Class.new { def self.lex(_code) = raise("boom SECRET-CODE") }

  test "the twenty languages are the listed ones, each with a Rouge lexer, and a label is read by tag" do
    assert_equal %w[Shell CSS Dockerfile ERB Go HTML INI JavaScript JSON Markdown nginx PHP Python Ruby Rust SQL TOML TypeScript XML YAML],
      CodeHighlight::LANGUAGES.values
    CodeHighlight::LANGUAGES.each_key { |tag| assert Rouge::Lexer.find(tag), "Rouge has no lexer for #{tag}" }
    assert_equal "YAML", CodeHighlight.label("yaml")
    assert_equal "Dockerfile", CodeHighlight.label("docker")
    assert_nil CodeHighlight.label("xojo")
    assert_nil CodeHighlight.label("")
    assert_nil CodeHighlight.label(nil)
    assert_predicate CodeHighlight::LANGUAGES, :frozen?
    assert_equal 20_000, CodeHighlight::MAX_CHARACTERS
  end

  test "Ruby: a comment, keywords, a string, and an instance variable, a symbol, a number and a constant as constant" do
    lines = CodeHighlight.lines(%(# note\ndef hi\n  @a = :sym + 1 + "s"\n  Foo\nend), "ruby")

    assert_equal [
      [ [ "comment", "# note" ] ],
      [ [ "keyword", "def" ], [ nil, " hi" ] ],
      [ [ nil, "  " ], [ "constant", "@a" ], [ nil, " = " ], [ "constant", ":sym" ], [ nil, " + " ], [ "constant", "1" ], [ nil, " + " ], [ "string", %("s") ] ],
      [ [ nil, "  " ], [ "constant", "Foo" ] ],
      [ [ "keyword", "end" ] ]
    ], lines
  end

  test "ERB: tags, an attribute, a string, and the template delimiters as embed" do
    assert_equal [ [
      [ "tag", "<p" ], [ nil, " " ], [ "attribute", "class=" ], [ "string", %("a") ], [ "tag", ">" ],
      [ "embed", "<%=" ], [ nil, " " ], [ "constant", "@x" ], [ nil, " " ], [ "embed", "%>" ], [ "tag", "</p>" ]
    ] ], CodeHighlight.lines(%(<p class="a"><%= @x %></p>), "erb")
  end

  test "HTML, YAML and shell: a markup comment, a key as attribute, a shell string and comment" do
    assert_equal [ [ [ "tag", "<a" ], [ nil, " " ], [ "attribute", "href=" ], [ "string", %("x") ], [ "tag", ">" ], [ nil, "t" ], [ "tag", "</a>" ], [ "comment", "<!-- c -->" ] ] ],
      CodeHighlight.lines(%(<a href="x">t</a><!-- c -->), "html")
    assert_equal [ [ [ "attribute", "key" ], [ nil, ": " ], [ "string", "value" ], [ nil, " " ], [ "comment", "# c" ] ] ],
      CodeHighlight.lines("key: value # c", "yaml")
    assert_equal [ [ [ nil, "echo " ], [ "string", %("hi") ], [ nil, " " ], [ "comment", "# c" ] ] ],
      CodeHighlight.lines(%(echo "hi" # c), "shell")
  end

  test "every role a line can carry is one of the seven, whatever the language" do
    sample = %(# c\nclass A < B\n  def x = "s" + :y.to_s + 1.to_s\nend\n<a href="x"><%= 1 %></a>\nkey: value\n)
    CodeHighlight::LANGUAGES.each_key do |tag|
      roles = CodeHighlight.lines(sample, tag).flatten(1).map(&:first).compact.uniq
      assert_empty roles - CodeHighlight::ROLES, "#{tag} answered a role that is not one of the seven"
    end
  end

  test "no language, a blank one and a language that is not on the list are plain text, tabs and angle brackets as they are" do
    plain = [ [ [ nil, "a < b" ] ], [ [ nil, "\tc" ] ] ]

    assert_equal plain, CodeHighlight.lines("a < b\n\tc", nil)
    assert_equal plain, CodeHighlight.lines("a < b\n\tc", "")
    assert_equal plain, CodeHighlight.lines("a < b\n\tc", "xojo"), "Rouge has a lexer for it, the list does not"
  end

  test "a lexer that raises is plain text, and the log names the block and holds no code" do
    log = capture_log do
      with_singleton_override(Rouge::Lexer, :find, ->(_tag) { RAISING }) do
        assert_equal [ [ [ nil, "SECRET-CODE = 1" ] ] ], CodeHighlight.lines("SECRET-CODE = 1", "ruby", block_id: 812)
      end
    end

    assert_match(/CodeHighlight: the ruby lexer raised RuntimeError for block 812/, log)
    assert_not_includes log, "SECRET-CODE"
  end

  test "lines: an empty line keeps its place, a last line break adds none, no code is no line, and a carriage return is a line break" do
    assert_equal [ [ [ nil, "a" ] ], [], [ [ nil, "b" ] ] ], CodeHighlight.lines("a\n\nb", nil)
    assert_equal [ [ [ nil, "a" ] ] ], CodeHighlight.lines("a\n", nil)
    assert_equal [], CodeHighlight.lines("", nil)
    assert_equal [], CodeHighlight.lines(nil, "ruby")
    assert_equal [ [ [ nil, "a" ] ], [ [ nil, "b" ] ], [ [ nil, "c" ] ] ], CodeHighlight.lines("a\r\nb\rc", nil)
  end

  test "the coloured lines are cached by the code, the language, Rouge's version and the revision" do
    was = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    first = CodeHighlight.lines("def a; end", "ruby")
    assert_equal [ [ [ "keyword", "def" ], [ nil, " a; " ], [ "keyword", "end" ] ] ], first

    with_singleton_override(Rouge::Lexer, :find, ->(_tag) { RAISING }) do
      assert_equal first, CodeHighlight.lines("def a; end", "ruby"), "the second read is the cache's: the lexer was not asked"
      assert_equal [ [ [ nil, "def b; end" ] ] ], CodeHighlight.lines("def b; end", "ruby"), "other code is another key"
    end
    assert_equal [ "code", Digest::SHA256.hexdigest("x"), "ruby", Rouge.version, CodeHighlight::REVISION ], CodeHighlight.cache_key("x", "ruby")
  ensure
    Rails.cache = was
  end

  test "bytes that are not text never raise: invalid UTF-8 and a binary string are scrubbed, with or without a language" do
    bad = "a\xffb\nc"
    expected = [ [ [ nil, "a\uFFFDb" ] ], [ [ nil, "c" ] ] ]

    assert_equal expected, CodeHighlight.lines(bad, nil)
    assert_equal expected, CodeHighlight.lines(bad, "ruby")
    assert_equal [ [ [ nil, "ab" ] ] ], CodeHighlight.lines("ab".b, "xojo")
    assert_equal [ [ [ "keyword", "def" ] ] ], CodeHighlight.lines("def".b, "ruby")
    assert_equal [ [ [ nil, "a\uFFFD" ] ] ], CodeHighlight.lines("a\xff".b, "ruby")
  end

  # A clock that moves `step` seconds every time it is read, so a deadline
  # passes without anyone waiting for it.
  def with_clock(step:)
    at = 0.0
    with_singleton_override(CodeHighlight, :now, -> { at += step }) { yield }
  end

  def with_memory_cache
    was = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = was
  end

  test "a lexer that never finishes is cut at the deadline and drawn plain, and nothing of the deadline is left behind" do
    tokens = 0
    endless = Class.new do
      define_singleton_method(:lex) { |_code| Enumerator.new { |y| loop { tokens += 1; y << [ Rouge::Token::Tokens::Keyword, "def" ] } } }
    end

    log = capture_log do
      with_clock(step: 0.01) do
        with_singleton_override(Rouge::Lexer, :find, ->(_tag) { endless }) do
          assert_equal [ [ [ nil, "def SECRET-CODE" ] ] ], CodeHighlight.lines("def SECRET-CODE", "ruby", block_id: 812)
        end
      end
    end

    assert_operator tokens, :<=, (CodeHighlight::LEX_SECONDS / 0.01).ceil + 1, "cut when the clock passed the budget, not later"
    assert_match(/CodeHighlight: the ruby lexer raised CodeHighlight::TooSlow for block 812; drawn as plain text for 5 minutes/, log)
    assert_not_includes log, "SECRET-CODE"
    assert_nil Thread.current[CodeHighlight::CHECK], "the check does not outlive its lex"
    assert_equal [ [ [ "keyword", "def" ] ] ], CodeHighlight.lines("def", "ruby"), "and the next lex has its own budget"
  end

  test "a shortened budget cuts sooner, and the budget is half a second" do
    tokens = 0
    endless = Class.new do
      define_singleton_method(:lex) { |_code| Enumerator.new { |y| loop { tokens += 1; y << [ Rouge::Token::Tokens::Keyword, "def" ] } } }
    end

    with_clock(step: 0.01) do
      with_singleton_override(CodeHighlight, :budget, -> { 0.03 }) do
        with_singleton_override(Rouge::Lexer, :find, ->(_tag) { endless }) { CodeHighlight.lines("def", "ruby") }
      end
    end

    assert_operator tokens, :<=, 4
    assert_equal 0.5, CodeHighlight::LEX_SECONDS
    assert_equal CodeHighlight::LEX_SECONDS, CodeHighlight.budget
  end

  # Rouge joins neighbouring tokens of one type before it yields them, so
  # this text reaches `coloured` as ONE token, after the last step: only a
  # check inside Rouge's own loop can cut it. It fails when a Rouge upgrade
  # renames `RegexLexer#step`.
  test "the deadline is checked inside Rouge, step by step: a text of one token type is cut although it yields once" do
    code = "word and word\n" * 200
    assert_equal 1, Rouge::Lexer.find("markdown").lex(code).to_a.size, "the sample is one token for Rouge"

    with_memory_cache do
      log = capture_log do
        with_clock(step: 0.01) { assert_equal CodeHighlight.lines(code, nil), CodeHighlight.lines(code, "markdown", block_id: 3) }
      end

      assert_match(/raised CodeHighlight::TooSlow for block 3/, log)
      assert Rails.cache.read(CodeHighlight.failure_key(code, "markdown"))
      assert_nil Rails.cache.read(CodeHighlight.cache_key(code, "markdown"))
    end
  end

  test "a lexer Markdown hands a fenced block to is under the same deadline, listed or not" do
    code = "```elixir\n" + "x = 1 # c\n" * 300 + "```\n"

    with_memory_cache do
      coloured = CodeHighlight.lines(code, "markdown")
      assert_includes coloured[1], [ "comment", "# c" ], "a fence that names an unlisted language is coloured by that lexer"
      assert_empty coloured.flatten(1).map(&:first).compact.uniq - CodeHighlight::ROLES, "and its roles are among the seven"
    end

    with_memory_cache do
      log = capture_log do
        with_clock(step: 0.01) { assert_equal CodeHighlight.lines(code, nil), CodeHighlight.lines(code, "markdown") }
      end
      assert_match(/raised CodeHighlight::TooSlow/, log)
    end
  end

  test "one match past Regexp.timeout is a failure like any other: plain, remembered, and Rails sets that timeout" do
    assert_equal 1.0, Regexp.timeout, "load_defaults 8.1 sets it; the file's comment counts on it"
    slow = Class.new { def self.lex(_code) = raise(Regexp::TimeoutError, "regexp match timeout") }

    with_memory_cache do
      log = capture_log do
        with_singleton_override(Rouge::Lexer, :find, ->(_tag) { slow }) { assert_equal [ [ [ nil, "def a" ] ] ], CodeHighlight.lines("def a", "ruby") }
      end
      assert_match(/raised Regexp::TimeoutError/, log)
      assert Rails.cache.read(CodeHighlight.failure_key("def a", "ruby"))
    end
  end

  test "a failure is remembered for five minutes: no second lex, one log line, and then it tries again" do
    calls = 0
    flaky = Class.new do
      define_singleton_method(:lex) { |code| (calls += 1) == 1 ? raise("boom secret_code") : Rouge::Lexers::Ruby.lex(code) }
    end
    plain = [ [ [ nil, "def secret_code" ] ] ]

    with_memory_cache do
      log = capture_log do
        with_singleton_override(Rouge::Lexer, :find, ->(_tag) { flaky }) do
          assert_equal plain, CodeHighlight.lines("def secret_code", "ruby", block_id: 7)
          assert_equal plain, CodeHighlight.lines("def secret_code", "ruby", block_id: 7), "plain from the entry"
          assert_equal 1, calls, "the second call did not lex"
          assert_equal true, Rails.cache.read(CodeHighlight.failure_key("def secret_code", "ruby"))
          assert_nil Rails.cache.read(CodeHighlight.cache_key("def secret_code", "ruby")), "a failure is never stored as lines"

          travel CodeHighlight::FAILURE_TTL - 1.second
          assert_equal plain, CodeHighlight.lines("def secret_code", "ruby", block_id: 7)
          assert_equal 1, calls, "still inside the entry's life"

          travel 2.seconds
          assert_equal [ [ [ "keyword", "def" ], [ nil, " secret_code" ] ] ], CodeHighlight.lines("def secret_code", "ruby", block_id: 7)
          assert_equal 2, calls, "the entry lapsed and the lexer was asked once more"
        end
      end

      assert_equal 5.minutes, CodeHighlight::FAILURE_TTL
      assert_equal 1, log.scan("CodeHighlight:").size, "one line for the one entry"
      assert_not_includes log, "secret_code"
    end
  end

  test "a failure's entry is for that code and that language only, and a success is cached without an end" do
    with_memory_cache do
      with_singleton_override(Rouge::Lexer, :find, ->(_tag) { RAISING }) { CodeHighlight.lines("def a", "ruby") }

      assert_equal [ [ [ "keyword", "def" ], [ nil, " b" ] ] ], CodeHighlight.lines("def b", "ruby"), "other code heals at once"
      assert_equal [ [ [ nil, "def a" ] ] ], CodeHighlight.lines("def a", "ruby"), "the failed code is still plain"
      assert_not_equal [ [ [ nil, "def a" ] ] ], CodeHighlight.lines("def a", "python"), "another language is another entry"
      assert_equal [ "code-failed", Digest::SHA256.hexdigest("x"), "ruby", Rouge.version, CodeHighlight::REVISION ], CodeHighlight.failure_key("x", "ruby")

      travel 1.year
      with_singleton_override(Rouge::Lexer, :find, ->(_tag) { RAISING }) do
        assert_equal [ [ [ "keyword", "def" ], [ nil, " b" ] ] ], CodeHighlight.lines("def b", "ruby"), "a success does not lapse"
      end
    end
  end

  test "a lexer that fails partway through gives plain text for all of it, not the part it had lexed" do
    partway = Class.new do
      def self.lex(_code) = Enumerator.new { |y| y << [ Rouge::Token::Tokens::Keyword, "def" ]; raise "boom" }
    end

    with_singleton_override(Rouge::Lexer, :find, ->(_tag) { partway }) do
      assert_equal [ [ [ nil, "def a" ] ] ], CodeHighlight.lines("def a", "ruby")
    end
  end

  # A lexer that would be seen if it were asked: the earlier form of this
  # test used one that raises, which is rescued to the same plain text, so it
  # passed without the cap, and its "limit itself" was eight characters.
  test "code over the limit is plain text and is not cached or lexed, and code of exactly the limit is lexed" do
    asked = []
    seen = Class.new { define_singleton_method(:lex) { |code| asked << code.length; Rouge::Lexers::Ruby.lex(code) } }
    at = "def" + " " * (CodeHighlight::MAX_CHARACTERS - 3)
    over = "#{at} "
    assert_equal [ CodeHighlight::MAX_CHARACTERS, CodeHighlight::MAX_CHARACTERS + 1 ], [ at.length, over.length ]

    with_memory_cache do
      with_singleton_override(Rouge::Lexer, :find, ->(_tag) { seen }) do
        assert_equal [ [ [ "keyword", "def" ], [ nil, " " * (CodeHighlight::MAX_CHARACTERS - 3) ] ] ], CodeHighlight.lines(at, "ruby")
        assert_equal [ CodeHighlight::MAX_CHARACTERS ], asked, "the limit itself is lexed"

        assert_equal [ [ [ nil, over ] ] ], CodeHighlight.lines(over, "ruby")
        assert_equal [ CodeHighlight::MAX_CHARACTERS ], asked, "one character more is not handed to the lexer"
      end

      assert Rails.cache.read(CodeHighlight.cache_key(at, "ruby"))
      assert_nil Rails.cache.read(CodeHighlight.cache_key(over, "ruby"))
      assert_nil Rails.cache.read(CodeHighlight.failure_key(over, "ruby")), "and it is no failure either"
    end
  end

  # Task 1's re-review, N1: `scrub` alone raises Encoding::CompatibilityError
  # for a string in another encoding that holds bytes its encoding does not.
  test "a string in another encoding never raises, with bad bytes or without: US-ASCII, Shift_JIS, UTF-16LE and one Ruby cannot convert" do
    assert_equal [ [ [ nil, "a\uFFFDb" ] ] ], CodeHighlight.lines("a\xffb".dup.force_encoding(Encoding::US_ASCII), nil)
    assert_equal [ [ [ "keyword", "def" ], [ nil, " \uFFFD" ] ] ], CodeHighlight.lines("def \xff".dup.force_encoding(Encoding::US_ASCII), "ruby")

    japanese = "日本".encode(Encoding::Shift_JIS)
    assert_equal [ [ [ nil, "日本" ] ] ], CodeHighlight.lines(japanese, nil), "a valid string is transcoded, not mangled"
    assert_equal [ [ [ nil, "日本\uFFFD" ] ] ], CodeHighlight.lines((japanese.b + "\x81".b).force_encoding(Encoding::Shift_JIS), "ruby")

    wide = "def a".encode(Encoding::UTF_16LE)
    assert_equal [ [ [ "keyword", "def" ], [ nil, " a" ] ] ], CodeHighlight.lines(wide, "ruby")
    assert_equal [ [ [ nil, "def a\uFFFD" ] ] ], CodeHighlight.lines((wide.b + "\x00".b).force_encoding(Encoding::UTF_16LE), nil), "half a character at the end"
    assert_equal [ [ [ nil, "a" ] ], [ [ nil, "b" ] ] ], CodeHighlight.lines("a\r\nb".encode(Encoding::UTF_16LE), nil), "line breaks are read after the transcoding"

    assert_nothing_raised { CodeHighlight.lines("ab".dup.force_encoding(Encoding::UTF_7), "ruby") }
    [ Encoding::US_ASCII, Encoding::Shift_JIS, Encoding::UTF_16LE, Encoding::UTF_7 ].each do |encoding|
      answered = CodeHighlight.lines("a\xff\xfe\x81".dup.force_encoding(encoding), "ruby").flatten(1).map(&:last).join
      assert_equal Encoding::UTF_8, answered.encoding
      assert_predicate answered, :valid_encoding?
    end
  end

  test "a very long single line and a leading line break are kept as they are" do
    long = "x" * 5_000
    assert_equal [ [ [ nil, long ] ] ], CodeHighlight.lines(long, nil)
    assert_equal [ [], [ [ nil, "a" ] ] ], CodeHighlight.lines("\na", nil)
    assert_equal [ [] ], CodeHighlight.lines("\n", nil)
    assert_equal [ [ [ "keyword", "def" ] ] ], CodeHighlight.lines("def", "ruby")
    assert_equal [ [], [ [ "keyword", "def" ] ] ], CodeHighlight.lines("\ndef", "ruby")
  end
end
