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

  # A tenth theme, of two files (`test/fixtures/themes/diagram`): its own
  # template for the Diagram block, written from the reference's section
  # alone (docs/reference/theming.md, "The Diagram block"), and a stylesheet
  # that re-colours the diagram's tokens for both schemes.
  DIAGRAM = Rails.root.join("test/fixtures/themes/diagram")

  def diagram_theme = Theme.load(ThemeFolder.new(DIAGRAM))

  def with_diagram_theme(&block) = Theme.with(diagram_theme, &block)

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

  # An eighth theme (`test/fixtures/themes/card`): its own template for the
  # Card block, written from the reference's section alone
  # (docs/reference/theming.md, "The Card block"), one icon of its own that
  # is drawn with classes, a filled shape, its own size and a gradient its
  # layout defines, and a stylesheet that declares the Card's tokens again
  # for both schemes.
  CARD = Rails.root.join("test/fixtures/themes/card")

  def card_theme = Theme.load(ThemeFolder.new(CARD))

  def with_card_theme(&block) = Theme.with(card_theme, &block)

  # A ninth theme (`test/fixtures/themes/form`): its own template for the
  # Form block and for a short text answer, written from the reference's
  # section alone (docs/reference/theming.md, "The Form block"), and a
  # stylesheet for them.
  FORM = Rails.root.join("test/fixtures/themes/form")

  def form_theme = Theme.load(ThemeFolder.new(FORM))

  def with_form_theme(&block) = Theme.with(form_theme, &block)

  # A sixth theme (`test/fixtures/themes/choices`): a theme.yml declaring two
  # section styles (the second labelled in en and de), the two page
  # templates, and one icon of its own (`brush`, labelled Design, a 24-unit
  # outline in currentColor under assets/images/icons).
  CHOICES = Rails.root.join("test/fixtures/themes/choices")

  def choices_theme = Theme.load(ThemeFolder.new(CHOICES))

  def with_choices_theme(&block) = Theme.with(choices_theme, &block)

  # A seventh theme (`test/fixtures/themes/section_grid`): a theme.yml declaring
  # the section style `grid_six`, and its own template for the Section, written
  # from the reference's Section row alone: with that style it draws the
  # section's blocks in reading order in a grid of its own.
  SECTION_GRID = Rails.root.join("test/fixtures/themes/section_grid")

  def section_grid_theme = Theme.load(ThemeFolder.new(SECTION_GRID))

  def with_section_grid_theme(&block) = Theme.with(section_grid_theme, &block)

  # The default theme with its page templates replaced by `names` (no fields,
  # no files), for the length of a block: a theme that dropped a template a
  # page stores, or one that offers another. Every other list is the default's.
  def with_page_templates(*names, &block)
    templates = names.map { |name| Theme::Choice.new(list: "page_templates", name: name, labels: { "en" => name.humanize }, fields: [], file: nil, from: :theme) }
    Theme.with(Theme.new(declarations: Theme::Declarations.default.merge("page_templates" => templates)), &block)
  end

  # A copy of the second theme in a directory of its own, for a test that
  # adds, changes or removes a file. Yields the directory as a Pathname.
  def with_theme_copy
    Dir.mktmpdir("theme") do |dir|
      FileUtils.cp_r("#{PLAIN}/.", dir)
      yield Pathname(dir)
    end
  end
end
