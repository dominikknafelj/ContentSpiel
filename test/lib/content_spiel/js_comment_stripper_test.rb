require "test_helper"

# `ContentSpiel::JsCommentStripper`, which production's `assets:precompile`
# runs over the app's own JavaScript (`ContentSpiel::JsCommentCompiler`,
# config/initializers/assets.rb). It removes whole-line `//` comments and
# `/* … */` blocks that start a line, nothing else, and keeps every line
# break; inside a string, a template literal or a regex it never acts.
class ContentSpiel::JsCommentStripperTest < ActiveSupport::TestCase
  Stripper = ContentSpiel::JsCommentStripper

  def strip(source)
    result = Stripper.call(source)
    assert result.stripped?, "left untouched: #{result.untouched}"
    assert_equal source.count("\n"), result.output.count("\n"), "every line break is kept"
    result.output
  end

  def assert_untouched(source, reason)
    result = Stripper.call(source)

    assert_not result.stripped?
    assert_match reason, result.untouched
    assert_same source, result.output
  end

  test "a line that is a // comment becomes an empty line, its indentation with it, and the code keeps its own" do
    source = <<~JS
      // A comment.
      export function a() {
          // Indented.
        return 1 // the end of a line of code stays
      }
    JS

    assert_equal "\nexport function a() {\n\n  return 1 // the end of a line of code stays\n}\n", strip(source)
  end

  test "a /* */ block that starts a line is emptied through its last line, one line or several" do
    source = "/* one */\nconst a = 1\n  /**\n   * Several.\n   */  \nconst b = 2\n"

    assert_equal "\nconst a = 1\n\n\n\nconst b = 2\n", strip(source)
  end

  test "a block followed by code on its closing line stays whole, and so does a block after code" do
    source = "/* a\n b */ const a = 1\nconst b = 2 /* kept\n and this */\n/* x */ /* y */\n"

    assert_equal source, strip(source)
  end

  test "a template literal spanning lines keeps its // lines and their indentation" do
    source = <<~JS
      const html = `
        // not a comment
          /* not one either */
      `
      // a comment
    JS

    assert_equal source.sub("// a comment", ""), strip(source)
  end

  test "templates nested in ${} are followed to their end, and the code after them is code again" do
    source = <<~JS
      const a = `x ${b ? `y ${c({ d: `
      // inside the innermost template
      `})}` : "}"} z
      // inside the outer template
      `
      // a comment
      const e = { f: `${g}` }
      // another
    JS

    expected = source.sub("// a comment", "").sub("// another", "")
    assert_equal expected, strip(source)
  end

  test "strings holding // and /* and quotes of the other kind change nothing" do
    source = <<~JS
      const a = "http://example.org/* not a comment */"
      const b = 'it\\'s // "quoted" `tick`'
      // gone
    JS

    assert_equal source.sub("// gone", ""), strip(source)
  end

  test "a regex holding /*, //, quotes and backticks is read as a regex" do
    source = <<~JS
      const a = /\\/\\/|[/*'"`]/g.test(b)
      const c = x.replace(/"/g, "'") // keep
      if (d) return /`/.test(e)
      // gone
      const f = g / h / i
      // gone too
    JS

    assert_equal source.sub("// gone\n", "\n").sub("// gone too", ""), strip(source)
  end

  test "legal comments, source map and source URL lines are kept" do
    source = "/*! MIT licence */\n//# sourceMappingURL=a.js.map\n//# sourceURL=a.js\n//@ sourceMappingURL=old.map\n/*# sourceMappingURL=b.map */\n// gone\n"

    assert_equal source.sub("// gone", ""), strip(source)
  end

  test "a file with nothing to remove is handed back as it came" do
    source = "export const a = 1\n"

    assert_same source, Stripper.call(source).output
  end

  test "a file whose reading is uncertain is handed back untouched with the reason" do
    assert_untouched "// a\nconst a = `never closed\n", /template literal is never closed/
    assert_untouched "// a\nconst a = 'never closed\n", /string reaches the end of its line/
    assert_untouched "// a\nconst a = b\n/* never closed\n", /never closed/
    # A `/` after punctuation is taken for a regex; one that runs to the end
    # of its line is not read further.
    assert_untouched "// a\nconst a = b++ / 2\n", /regular expression reaches the end of its line/
  end

  test "multi-byte characters and a CRLF file keep their bytes and their line breaks" do
    source = "// Größe\r\nconst a = \"ä // ö\"\r\n"

    assert_equal "\nconst a = \"ä // ö\"\r\n", strip(source)
    assert_equal Encoding::UTF_8, strip(source).encoding
  end

  # The property every served file holds: the same lines, each line either
  # exactly the source's or a comment line made empty, and nothing removed
  # that is not a comment. No file of the app's own is left untouched.
  test "every file under app/javascript keeps its lines, and only its comment lines are emptied" do
    files = Dir[Rails.root.join("app/javascript/**/*.js")]
    assert_operator files.size, :>, 100

    files.each do |file|
      source = File.read(file)
      result = Stripper.call(source)
      assert result.stripped?, "#{file} left untouched: #{result.untouched}"

      source_lines = source.split("\n", -1)
      output_lines = result.output.split("\n", -1)
      assert_equal source_lines.size, output_lines.size, file

      in_block = false
      source_lines.zip(output_lines).each_with_index do |(before, after), index|
        place = "#{file}:#{index + 1}"
        if in_block
          assert_empty after, "#{place}: a line of a removed block is emptied"
          in_block = !before.include?("*/")
          next
        end
        next if before == after

        line = before.lstrip
        assert line.start_with?("//", "/*") && after.empty?, "#{place} changed a line that is not a comment: #{before.inspect}"
        in_block = line.start_with?("/*") && !line.include?("*/")
      end
    end
  end

  test "only the app's own files and a theme's are stripped, never vendor/javascript, a gem's or a .min.js" do
    own = ContentSpiel::JsCommentCompiler

    assert own.own?(Rails.root.join("app/javascript/site.js"))
    assert own.own?(Rails.root.join("app/javascript/controllers/admin/ui/menu_controller.js"))
    assert_not own.own?(Rails.root.join("vendor/javascript/mermaid.js"))
    assert_not own.own?(Rails.root.join("app/javascript/some.min.js"))
    assert_not own.own?(Rails.root.join("app/javascript_elsewhere/a.js"))
    turbo = Rails.application.assets.load_path.find("turbo.min.js")
    assert_not own.own?(turbo.path)
  end

  test "development and test serve the files as written: the compiler is production's alone" do
    assert_not_includes Rails.application.assets.compilers.registrations["text/javascript"], ContentSpiel::JsCommentCompiler
    assert_equal "1.0", Rails.application.config.assets.version
  end
end
