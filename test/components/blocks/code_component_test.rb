require "test_helper"

class Blocks::CodeComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper

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
    assert_selector ".code-head [role='status'].sr-only[data-code-copy-target='status']", visible: :all
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

    with_singleton_override(Rouge::Lexer, :find, ->(_tag) { raising }) { draw(code_block) }

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
      assert_no_match(/html_safe|\braw\b|safe_join|Formatters/, Rails.root.join(path).read, path)
    end
    naming = Dir[Rails.root.join("app/**/*.{rb,erb,js}")].select { |path| File.read(path).match?(/\bRouge\b/) }
    assert_equal [ Rails.root.join("app/values/code_highlight.rb").to_s ], naming
  end
end
