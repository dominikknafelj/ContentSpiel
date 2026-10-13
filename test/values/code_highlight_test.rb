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

  test "a failed lex is not cached: plain this time, logged, and the next call tries again" do
    was = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    calls = 0
    flaky = Class.new do
      define_singleton_method(:lex) { |code| (calls += 1) == 1 ? raise("boom") : Rouge::Lexers::Ruby.lex(code) }
    end

    log = capture_log do
      with_singleton_override(Rouge::Lexer, :find, ->(_tag) { flaky }) do
        assert_equal [ [ [ nil, "def a" ] ] ], CodeHighlight.lines("def a", "ruby", block_id: 7)
        assert_equal [ [ [ "keyword", "def" ], [ nil, " a" ] ] ], CodeHighlight.lines("def a", "ruby", block_id: 7)
      end
    end
    assert_equal 2, calls
    assert_equal 1, log.scan("CodeHighlight:").size
  ensure
    Rails.cache = was
  end

  test "a lexer that fails partway through gives plain text for all of it, not the part it had lexed" do
    partway = Class.new do
      def self.lex(_code) = Enumerator.new { |y| y << [ Rouge::Token::Tokens::Keyword, "def" ]; raise "boom" }
    end

    with_singleton_override(Rouge::Lexer, :find, ->(_tag) { partway }) do
      assert_equal [ [ [ nil, "def a" ] ] ], CodeHighlight.lines("def a", "ruby")
    end
  end

  test "code over the limit is plain text and is not cached or lexed" do
    was = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    code = "def" + " " * CodeHighlight::MAX_CHARACTERS

    with_singleton_override(Rouge::Lexer, :find, ->(_tag) { RAISING }) do
      assert_equal [ [ [ nil, code ] ] ], CodeHighlight.lines(code, "ruby")
    end
    assert_nil Rails.cache.read(CodeHighlight.cache_key(code, "ruby"))
    assert_equal [ [ [ "keyword", "def" ], [ nil, " " * 5 ] ] ], CodeHighlight.lines("def     ", "ruby"), "the limit itself is allowed"
  ensure
    Rails.cache = was
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
