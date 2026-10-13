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

    assert_selector "figure.content-block.content-block--code[data-controller='code-copy'][data-code-copy-label-value='Copy'][data-code-copy-copied-value='Copied'][data-code-copy-failed-value='Not copied']"
    assert_selector ".code-head:not([hidden]):not([data-code-copy-target])", visible: :all
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

  # Design answer C1: a strip with nothing to show is not drawn. The server
  # writes it `hidden`, with the button in it, as the script's `strip` target:
  # the script shows the two together where it can copy, and a page without
  # the script shows the code alone.
  test "with no file name and no language the head is hidden in the markup and is the script's to show, with the button in it describing itself by nothing" do
    draw(code_block({ "filename" => nil, "language" => nil }))

    assert_selector ".code-head[hidden][data-code-copy-target='strip'] button[hidden][data-code-copy-target='button']", visible: :all
    assert_no_selector ".code-head", visible: :visible
    assert_no_selector ".code-file, .code-language, button[aria-describedby]", visible: :all
    assert_empty fragment.css("pre span"), "no language is plain text"
    assert_equal "figure", fragment.at_css("pre").parent.name
    assert_equal CODE, fragment.at_css("pre").text
  end

  test "a file name alone and a language alone each draw the head as it is: not hidden, not the script's, only the button hidden" do
    [ { "language" => nil }, { "filename" => nil }, { "filename" => "  " } ].each do |settings|
      draw(code_block(settings))

      assert_selector ".code-head:not([hidden]):not([data-code-copy-target]) button[hidden]", visible: :all
      assert_selector ".code-head > span:not(.code-status)", count: 1
    end
  end

  # A stored language that is no longer on the list has no label: with no
  # file name beside it there is nothing to show.
  test "a language that is not on the list and no file name is a hidden head" do
    block = code_block({ "filename" => nil })
    block.update_columns(settings: block.settings.merge("language" => "cobol")) # version: none (a test writes the row a list that shrank would leave)

    draw(block.reload)

    assert_selector ".code-head[hidden][data-code-copy-target='strip']", visible: :all
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

  # Fences of Markdown in Markdown, 650 deep: what overflowed a request's
  # thread before the depth was counted (`test/values/code_highlight_test.rb`).
  def nested_fences(levels = 650)
    indents = Array.new(levels) { |index| index.zero? ? "" : index.to_s(2).tr("01", " \t") }
    (indents.map { |indent| "#{indent}```md\n" } + [ "x\n" ] + indents.reverse.map { |indent| "#{indent}```\n" }).join
  end

  # Final re-review C1. Drawn on a thread, as a request draws it: on the main
  # thread the stack is eight times as deep and the text simply lexes.
  test "a Markdown block of fences nested hundreds deep is drawn as its text on a thread, and raises nothing" do
    code = nested_fences
    block = code_block({ "language" => "markdown", "filename" => nil, "code" => code })
    html = nil

    log = capture_log { html = Thread.new { render_inline(Blocks::CodeComponent.new(block: block, page: root_page)).to_html }.value }

    drawn = Nokogiri::HTML5.fragment(html)
    assert_equal code.delete_suffix("\n"), drawn.at_css("pre").text
    assert_empty drawn.css("pre span")
    assert_equal "Markdown", drawn.at_css(".code-language").text
    assert_match(/CodeHighlight: the markdown lexer raised CodeHighlight::TooDeep for block #{block.id}; /, log)
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

  # `string` is on the theming contract, so a theme's template calls it
  # with a key its author typed. A key that is not one of the four never
  # becomes I18n's "Translation missing: …" as a button's word on a public
  # page: where a theme is written it raises and names the four, and in
  # production it is no word at all and one line in the log.
  test "string answers the four words and nothing else: another key raises with the four where a theme is written, and in production is empty and logged once" do
    component = Blocks::CodeComponent.new(block: code_block, page: root_page)

    assert_equal %i[copy copy_code copied failed], Blocks::CodeComponent::STRINGS
    assert_equal Blocks::CodeComponent::STRINGS.map(&:to_s), YAML.load_file(Rails.root.join("config/locales/public.en.yml")).dig("en", "public", "blocks", "code").keys
    assert_equal [ "Copy", "Copy code", "Copied", "Not copied" ], Blocks::CodeComponent::STRINGS.map { |key| component.send(:string, key) }
    assert_equal "Copy", component.send(:string, "copy"), "a key written as a String is the same key"

    error = assert_raises(ArgumentError) { component.send(:string, :copy_all) }
    assert_equal "Blocks::CodeComponent#string has no :copy_all: the Code block's words are :copy, :copy_code, :copied, :failed", error.message

    Blocks::CodeComponent.instance_variable_set(:@unknown_strings, nil)
    with_singleton_override(Rails, :env, -> { ActiveSupport::EnvironmentInquirer.new("production") }) do
      log = capture_log do
        assert_equal [ "", "", "" ], [ component.send(:string, :copy_all), component.send(:string, :copy_all), component.send(:string, "copy_all") ]
        assert_equal "Copy", component.send(:string, :copy)
      end
      assert_equal 1, log.scan("Blocks::CodeComponent#string has no :copy_all").size, "said once, not once per visitor"
      assert_no_match(/ranslation missing/, log)
    end
  ensure
    Blocks::CodeComponent.instance_variable_set(:@unknown_strings, nil)
  end

  # `lines` is on the contract too, and a theme's template may ask twice (a
  # gutter's count, then the lines).
  test "lines is read once however often a template asks" do
    component = Blocks::CodeComponent.new(block: code_block, page: root_page)
    calls = 0
    real = CodeHighlight.method(:lines)

    with_singleton_override(CodeHighlight, :lines, ->(*arguments, **options) { calls += 1; real.call(*arguments, **options) }) do
      first = component.send(:lines)
      assert_same first, component.send(:lines)
      assert_equal 3, first.size
    end
    assert_equal 1, calls
  end

  test "nothing in the component, its template or the highlighter marks a string as safe, and only the highlighter names Rouge" do
    %w[app/components/blocks/code_component.rb app/components/blocks/code_component.html.erb app/values/code_highlight.rb].each do |path|
      assert_no_match(/html_safe|\braw\b|safe_join|Formatters|<%==|SafeBuffer|escape:\s*false/, Rails.root.join(path).read, path)
    end
    naming = Dir[Rails.root.join("app/**/*.{rb,erb,js}")].select { |path| File.read(path).match?(/\bRouge\b/) }
    assert_equal [ Rails.root.join("app/values/code_highlight.rb").to_s ], naming
  end
end
