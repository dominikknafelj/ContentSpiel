require "test_helper"

class Blocks::CodeComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper
  include LogCapture

  CODE = "def hi\n  1\nend".freeze
  HOSTILE = %(</pre></code><script>alert(1)</script>\n<%= @x %> & <b>bold</b>).freeze

  def code_block(settings = {}, **attributes)
    root_page.content_blocks.create!(block_type: :code, position: 0,
      settings: { "language" => "ruby", "filename" => "app/hi.rb", "code" => CODE }.merge(settings).compact, **attributes)
  end

  def draw(block) = render_inline(Blocks::CodeComponent.new(block: block, page: root_page))

  # The markup as a browser parses it.
  def fragment = Nokogiri::HTML5.fragment(rendered_content)

  test "a figure with the file name and language above the code, a hidden Copy button, a status line and the code coloured" do
    block = code_block
    draw(block)

    assert_selector "figure.content-block.content-block--code[data-controller='code-copy'][data-code-copy-copied-value='Copied'][data-code-copy-failed-value='Not copied']"
    assert_selector ".code-head .code-file#code-#{block.id}-file", text: "app/hi.rb"
    assert_selector ".code-head .code-language", text: "Ruby"
    assert_selector ".code-head button[type='button'][hidden][data-code-copy-target='button'][data-action='code-copy#copy'][aria-label='Copy code'][aria-describedby='code-#{block.id}-file']",
      text: "Copy", visible: :all
    assert_selector ".code-head [role='status'].code-status[data-code-copy-target='status']", visible: :all
    assert_no_selector ".sr-only", visible: :all # the block hides its status line by its own stylesheet's class, not by a scanned utility
    assert_selector "pre[tabindex='0'][data-code-copy-target='source'] > code span.syn-keyword", text: "def"
    assert_equal CODE, fragment.at_css("pre").text, "the code's text is the stored code, to the character"
    assert_no_selector "figcaption"
  end

  test "a block with no code draws nothing" do
    draw(code_block({ "code" => nil, "filename" => "empty.rb" }))

    assert_equal "", rendered_content.strip
  end

  test "the head is drawn without a file name or a language: it holds the button, which then describes itself by nothing" do
    draw(code_block({ "filename" => nil, "language" => nil }))

    assert_selector ".code-head button[data-code-copy-target='button']", visible: :all
    assert_no_selector ".code-file, .code-language, button[aria-describedby]", visible: :all
    assert_empty fragment.css("pre span"), "no language is plain text"
  end

  test "source, file name and caption that look like markup are text: one pre, no script, no element the template did not write" do
    [ "erb", "html", nil ].each do |language|
      draw(code_block({ "language" => language, "filename" => "<i>x</i>.rb", "code" => HOSTILE }, caption: "<b>cap</b>"))

      assert_equal 1, fragment.css("pre").size, language.inspect
      assert_empty fragment.css("script, b, i"), language.inspect
      assert_equal HOSTILE, fragment.at_css("pre").text, language.inspect
      assert_empty fragment.css("pre *").map(&:name).uniq - %w[code span], language.inspect
      spans = fragment.css("pre span")
      assert_empty spans.flat_map { |span| span.attributes.keys }.uniq - %w[class], "a span carries a class and nothing else"
      assert_empty spans.map { |span| span["class"] }.uniq - CodeHighlight::ROLES.map { |role| "syn-#{role}" }, "a class is one of the seven roles'"
      assert_equal "<i>x</i>.rb", fragment.at_css(".code-file").text
      assert_equal "<b>cap</b>", fragment.at_css("figcaption").text.strip
    end
  end

  # White space is the content. The template's own part of it is the join: a
  # line break between lines and nothing else between the `pre`'s tags.
  test "the first line's indentation, tabs and blank inner lines are drawn as stored, coloured or plain" do
    source = "\t  first = 1\n\n    second = 2\n\t\n\n  third\t= 3"

    [ "ruby", "erb", nil ].each do |language|
      draw(code_block({ "language" => language, "code" => source }))

      assert_equal source, fragment.at_css("pre").text, language.inspect
    end
  end

  # `ContentModel::FieldSet#cast_code` (Task 2) runs on read as on write: lines
  # of only white space before the first line and after the last are not
  # content. So a source that BEGINS with a line break cannot reach the
  # component, even from a row written around the services, and the one thing
  # `CodeHighlight.split_lines` drops (a final line break) is never handed over.
  test "blank lines before the first line and after the last are not content, even on a row written around the services" do
    block = code_block
    block.update_columns(settings: block.settings.merge("code" => "\n  \n  indented\n\nlast\n\n")) # version: none (a test writes the row a script could leave)

    draw(block.reload)

    assert_equal "  indented\n\nlast", fragment.at_css("pre").text
  end

  test "a stored language that is not on the list is plain text and names no language" do
    block = code_block
    block.update_columns(settings: block.settings.merge("language" => %(cobol"><script>))) # version: none (a test writes the row a list that shrank would leave)

    draw(block.reload)

    assert_no_selector ".code-language"
    assert_empty fragment.css("pre span, script")
    assert_equal CODE, fragment.at_css("pre").text
  end

  test "a lexer that raises still draws the code" do
    raising = Class.new { def self.lex(_code) = raise("boom") }

    block = code_block

    log = capture_log { with_singleton_override(Rouge::Lexer, :find, ->(_tag) { raising }) { draw(block) } }

    assert_match(/CodeHighlight: the ruby lexer raised RuntimeError for block #{block.id}; /, log, "the log names THIS block")
    assert_not_includes log, "def hi"
    assert_equal CODE, fragment.at_css("pre").text
    assert_selector ".code-language", text: "Ruby"
    assert_empty fragment.css("pre span")
  end

  test "the caption is the visitor's language with fallback, and the four public strings fall back to English" do
    with_locales(%w[en de], default: "en") do
      block = code_block({}, caption: "A sample")

      I18n.with_locale(:de) { draw(block) }
      assert_selector "figcaption", text: "A sample"
      assert_selector "button[aria-label='Copy code']", text: "Copy", visible: :all
      assert_selector "figure[data-code-copy-copied-value='Copied'][data-code-copy-failed-value='Not copied']"

      Mobility.with_locale(:de) { block.update!(caption: "Ein Beispiel") }
      I18n.with_locale(:de) { draw(block) }
      assert_selector "figcaption", text: "Ein Beispiel"
    end
  end

  test "nothing in the component, its template or the highlighter marks a string as safe, and only the highlighter names Rouge" do
    %w[app/components/blocks/code_component.rb app/components/blocks/code_component.html.erb app/values/code_highlight.rb].each do |path|
      assert_no_match(/html_safe|\braw\b|safe_join|Formatters|<%==|SafeBuffer|escape:\s*false/, Rails.root.join(path).read, path)
    end
    naming = Dir[Rails.root.join("app/**/*.{rb,erb,js}")].select { |path| File.read(path).match?(/\bRouge\b/) }
    assert_equal [ Rails.root.join("app/values/code_highlight.rb").to_s ], naming
  end
end
