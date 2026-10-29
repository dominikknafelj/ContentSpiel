require "tmpdir"
require "fileutils"

# The second theme (`test/fixtures/themes/plain`) for the length of a block.
# The test environment ignores THEME_PATH, so this is the one way a test is
# drawn by a theme: `Theme.current` is swapped in this process and put back,
# also when the block raises. A system test's server runs in this process
# too, so the swap reaches it.
module ThemeTestHelper
  PLAIN = Rails.root.join("test/fixtures/themes/plain")

  def plain_theme = Theme.load(ThemeFolder.new(PLAIN))

  def with_plain_theme(&block) = Theme.with(plain_theme, &block)

  # A third theme, of two files (`test/fixtures/themes/code`): its own
  # template for the Code block, written from the contract's names alone
  # and the markup the copy script asks for, and a stylesheet that declares
  # the seven syntax tokens again. The second theme deliberately has
  # neither, so every test of it is a test of the default Code block.
  CODE = Rails.root.join("test/fixtures/themes/code")

  def code_theme = Theme.load(ThemeFolder.new(CODE))

  def with_code_theme(&block) = Theme.with(code_theme, &block)

  # A fourth theme, of two files (`test/fixtures/themes/note`): its own
  # template for the Note block, written from the reference's section alone
  # (docs/reference/theming.md, "The Note block"), and a stylesheet for it.
  NOTE = Rails.root.join("test/fixtures/themes/note")

  def note_theme = Theme.load(ThemeFolder.new(NOTE))

  def with_note_theme(&block) = Theme.with(note_theme, &block)

  # A fifth theme, of two files (`test/fixtures/themes/table`): its own
  # template for the Table block, written from the reference's section alone
  # (docs/reference/theming.md, "The Table block"), and a stylesheet for it.
  TABLE = Rails.root.join("test/fixtures/themes/table")

  def table_theme = Theme.load(ThemeFolder.new(TABLE))

  def with_table_theme(&block) = Theme.with(table_theme, &block)

  # A copy of the second theme in a directory of its own, for a test that
  # adds, changes or removes a file. Yields the directory as a Pathname.
  def with_theme_copy
    Dir.mktmpdir("theme") do |dir|
      FileUtils.cp_r("#{PLAIN}/.", dir)
      yield Pathname(dir)
    end
  end
end
