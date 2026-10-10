require "test_helper"

# Where a screen's parts live (docs/superpowers/specs/2026-10-10-source-layout-cleanup-design.md).
# A Stimulus identifier follows its controller's path, and a name left behind
# by a move does not raise: the control is just dead. So every identifier the
# app writes must have a controller file.
class SourceLayoutTest < ActiveSupport::TestCase
  ROOT = Rails.root
  CONTROLLERS = ROOT.join("app/javascript/controllers")
  SOURCES = %w[app/components app/views app/helpers app/javascript app/assets/tailwind
               app/controllers app/models app/queries app/services test].freeze
  # Files that hold made-up identifiers on purpose.
  LEFT_OUT = %w[
    test/lib/source_layout_test.rb
    test/lib/admin_i18n_test.rb
  ].freeze # admin_i18n_test: sample markup (admin--x-target, admin--a) fed to the i18n scanner
  # An identifier, also after "data-" (a target, value, param or class attribute).
  TOKEN = /(?:(?<=data-)|(?<![a-z0-9-]))admin--[a-z0-9]+(?:-{1,2}[a-z0-9]+)*/
  # The Ruby hash-key spelling: `data: { admin__notes_live_unread_url_value: }`.
  UNDERSCORE_TOKEN = /(?<![A-Za-z0-9_])admin__[a-z0-9]+(?:_{1,2}[a-z0-9]+)*/

  # Prose in a comment may wrap an identifier across lines; only code is scanned.
  # Comment syntax is per language: a CSS line may begin with "#id".
  COMMENT_LINES = { ".rb" => /^\s*#.*$/, ".erb" => /^\s*#.*$/, ".js" => %r{^\s*//.*$} }.freeze

  def self.code_of(path)
    File.read(path).gsub(COMMENT_LINES.fetch(File.extname(path), /\A\z/), "")
  end

  def self.written_in(path)
    code = code_of(path)
    code.scan(TOKEN) + code.scan(UNDERSCORE_TOKEN).map { |token| token.tr("_", "-") }
  end

  def self.identifiers
    Dir[CONTROLLERS.join("**/*_controller.js")].map do |path|
      Pathname(path).relative_path_from(CONTROLLERS).to_s.delete_suffix("_controller.js").gsub("/", "--").tr("_", "-")
    end
  end

  # The identifier a token belongs to: the longest one it equals or extends with "-".
  def self.owner(token, identifiers)
    identifiers.select { |id| token == id || token.start_with?("#{id}-") }.max_by(&:length)
  end

  test "every admin identifier written in the app has a controller file" do
    identifiers = self.class.identifiers
    paths = SOURCES.flat_map { |dir| Dir[ROOT.join(dir, "**/*.{rb,erb,js,css}")] }
    paths.reject! { |path| LEFT_OUT.include?(Pathname(path).relative_path_from(ROOT).to_s) }
    orphans = paths.flat_map do |path|
      self.class.written_in(path).uniq.reject { |token| self.class.owner(token, identifiers) }.map { |token| "#{Pathname(path).relative_path_from(ROOT)}: #{token}" }
    end
    assert_empty orphans, "identifiers with no controller file:\n#{orphans.join("\n")}"
  end

  test "the guard's own matching: an identifier, its targets and values, and a stranger" do
    ids = %w[admin--notes admin--notes-live]
    assert_equal "admin--notes-live", self.class.owner("admin--notes-live-unread-url-value", ids)
    assert_equal "admin--notes", self.class.owner("admin--notes-target", ids)
    assert_nil self.class.owner("admin--nothing", ids)
  end

  test "the guard sees data attributes and the underscore spelling, and not a CSS id line as a comment" do
    Dir.mktmpdir do |dir|
      write = ->(name, text) { Pathname(dir).join(name).tap { |p| p.write(text) } }
      assert_equal %w[admin--x-y-target], self.class.written_in(write.("a.erb", 'data-admin--x-y-target="1"'))
      assert_equal %w[admin--x-y-value], self.class.written_in(write.("b.rb", "data: { admin__x_y_value: 1 }"))
      assert_equal %w[admin--x], self.class.written_in(write.("c.css", "#a [data-controller~=\"admin--x\"] {}"))
      assert_empty self.class.written_in(write.("d.rb", "# admin--x"))
      assert_empty self.class.written_in(write.("e.rb", "my_admin__x_y"))
    end
  end

  test "every relative translation key an admin component reads exists" do
    missing = Dir[ROOT.join("app/components/admin/**/*.{rb,erb}")].flat_map do |path|
      relative = Pathname(path).relative_path_from(ROOT.join("app/components/admin")).to_s
      next [] if relative == "admin_component.rb" # the base class only shows `t(".cancel")` in its doc comment; it reads no key itself
      scope = relative.sub(/_component(\.html)?\.(rb|erb)\z/, "").sub(/\.(rb|html\.erb)\z/, "").tr("/", ".")
      File.read(path).scan(/\bt\(\s*["']\.([a-z0-9_.]+)["']/).flatten.uniq.reject { |key| I18n.exists?("admin.components.#{scope}.#{key}", :en) }.map { |key| "#{relative}: .#{key}" }
    end
    assert_empty missing, "keys read but not defined:\n#{missing.join("\n")}"
  end

  test "nothing is loose in app/components/admin but the base class" do
    loose = Dir[ROOT.join("app/components/admin/*.{rb,erb}")].map { |path| File.basename(path) }
    assert_equal %w[admin_component.rb], loose
  end

  # One locale file per component folder: `config/locales/admin/<folder>.en.yml`
  # holds exactly `en.admin.components.<folder>`, so a screen's strings are found
  # from its folder and a scope is in one file.
  #
  # `notes.en.yml` is the one exception. Besides notes' own keys it holds notes'
  # wording on other screens (the block card's and the tile's "Add note", the
  # tree node's and the legend's markers), merged into those screens' scopes by
  # Rails; moving them into the screens' files would put notes' strings in core files.
  LOCALE_EXCEPTIONS = %w[notes].freeze

  # Every locale file of the folder, whatever its language: `<folder>.<locale>.yml` holds
  # exactly `<locale>.admin.components.<folder>` (German will add `ui.de.yml` and the rest).
  # Returns [folder name, locale, path] and checks the file's top-level key is its locale.
  def self.locale_files
    Dir[ROOT.join("config/locales/admin/*.yml")].map do |path|
      name, locale = File.basename(path, ".yml").split(".", 2)
      [ name, locale, path ]
    end
  end

  def self.components_of(path, locale)
    (YAML.load_file(path).dig(locale, "admin", "components") || {}).keys
  end

  test "a locale file of admin components holds one folder's scope, in its own language" do
    files = self.class.locale_files
    assert_includes files.map(&:second), "en"
    files.each do |name, locale, path|
      assert_equal [ locale ], YAML.load_file(path).keys, "#{File.basename(path)} must hold the top-level key #{locale.inspect} only"
      next if LOCALE_EXCEPTIONS.include?(name)
      scopes = self.class.components_of(path, locale)
      next if scopes.empty?
      assert_equal [ name ], scopes, "#{File.basename(path)} holds #{scopes.inspect}"
    end
  end

  test "a component scope has keys in one locale file per language, except where an exception names it, and names a folder" do
    holders = Hash.new { |hash, scope| hash[scope] = [] }
    self.class.locale_files.each do |name, locale, path|
      self.class.components_of(path, locale).each { |scope| holders[[ scope, locale ]] << "#{name}.#{locale}.yml" }
    end
    # The exception files are left out of the duplicate check only: their scopes are merged
    # with other files' on purpose.
    exceptions = LOCALE_EXCEPTIONS.flat_map { |name| holders.keys.map(&:last).uniq.map { |locale| "#{name}.#{locale}.yml" } }
    twice = holders.map { |key, files| [ key, files - exceptions ] }
                   .select { |_, files| files.size > 1 }.map { |(scope, locale), files| "#{locale} #{scope}: #{files.join(', ')}" }
    assert_empty twice, "a scope's keys are in two files:\n#{twice.join("\n")}"
    # Every file counts for this one, the exception included: a scope with no folder is dead.
    folders = Dir[ROOT.join("app/components/admin/*")].select { |p| File.directory?(p) }.map { |p| File.basename(p) }
    nameless = holders.reject { |(scope, _), _| folders.include?(scope) }.map { |(scope, locale), files| "#{locale} #{scope}: #{files.join(', ')}" }
    assert_empty nameless, "a locale file names a scope with no component folder:\n#{nameless.join("\n")}"
  end

  # The names CS Studio's controllers had before the layout cleanup: 55 identifiers of
  # one level, all loose in app/javascript/controllers/admin. Each one now has two levels
  # (`admin--topic--name`), and a name left behind is a dead control that raises nothing.
  ORIGINAL = %w[
    admin--ai-settings admin--auto-submit admin--autosave admin--blocks admin--branch-picker
    admin--bulk-select admin--busy admin--char-count admin--chip-input admin--clipboard
    admin--command-palette admin--dialog admin--drawer admin--file-drop-guard admin--fragment-links
    admin--group-hint admin--groups admin--media-drop admin--media-field admin--media-panel
    admin--media-picker admin--media-select admin--media-upload admin--menu admin--mind-graph
    admin--new-record admin--note-composer admin--note-gif admin--note-reactions admin--note-refusal
    admin--note-unsaved admin--notes-alert admin--notes admin--notes-live admin--notes-permission
    admin--override-field admin--password-answer admin--password-disclosure admin--pending-lock
    admin--permission-matrix admin--queue-hold admin--quick-create admin--repeat-rows admin--rich-text
    admin--rich-text-dialog admin--save-bar admin--section admin--settings-tabs admin--slug-preview
    admin--sortable-rows admin--tag-dialogs admin--toast admin--token-reveal admin--translate
    admin--tree
  ].freeze

  # Not scanned for old names: this file (it lists them) and admin_i18n_test.rb (made-up
  # sample markup).
  #
  # The documents are scanned too, because that is where an old name is most likely to be typed
  # again from memory. docs/superpowers, docs/product and docs/architecture are left out: dated
  # records of what was true when they were written (the plan and spec of this very cleanup
  # name every old identifier).
  OLD_NAMES_LEFT_OUT = %w[
    test/lib/source_layout_test.rb
    test/lib/admin_i18n_test.rb
  ].freeze

  # Reads a data-controller value from markup or Ruby, as far as a regex honestly can:
  # `data-controller="a b"`, `controller: "a b"`, `"data-controller" => "a b"`. A value built
  # at run time (`<%` or `#{`) comes back in the first list (the second holds the rest), unread.
  CONTROLLER_VALUE = /(?:data-controller=|(?<![-\w])controller:\s*|["']data-controller["']\s*(?:=>|:)\s*)(["'])(.*?)\1/m

  def self.controller_values(text)
    found = text.scan(CONTROLLER_VALUE).map(&:last)
    found.partition { |value| value.match?(/<%|%>|\#\{/) }
  end

  test "nothing is loose in app/javascript/controllers/admin" do
    assert_empty Dir[CONTROLLERS.join("admin/*.js")].map { |path| File.basename(path) }, "controllers loose in controllers/admin: move each into its topic's folder"
  end

  # The module folders under app/javascript hold what a topic's controllers import, so each is
  # named after its topic. i18n, live and search are the named exceptions.
  SHARED_MODULE_FOLDERS = {
    "i18n" => "the script messages every screen reads (messages(element).t), no one topic's",
    "live" => "the cable connection, shared by the notes and presence topics",
    "search" => "the title and tag search every picker shares, no one topic's"
  }.freeze

  test "a topic's plain modules are in the folder of the same name" do
    topics = Dir[CONTROLLERS.join("admin/*/")].map { |path| File.basename(path) }
    modules = Dir[ROOT.join("app/javascript/*/")].map { |path| File.basename(path) } - %w[controllers]
    strangers = modules - topics - SHARED_MODULE_FOLDERS.keys
    assert_empty strangers, "module folders with no topic of that name (#{SHARED_MODULE_FOLDERS.keys.to_sentence} are shared helpers): #{strangers.inspect}"
  end

  test "no identifier of the old one-level form is left" do
    identifiers = self.class.identifiers
    known = ORIGINAL | identifiers
    paths = SOURCES.flat_map { |dir| Dir[ROOT.join(dir, "**/*.{rb,erb,js,css}")] }
    paths += Dir[ROOT.join("config/**/*.{rb,yml,js,css}")] + Dir[ROOT.join("docs/reference/*.md")] + [ ROOT.join("CLAUDE.md").to_s ]
    paths.reject! { |path| OLD_NAMES_LEFT_OUT.include?(Pathname(path).relative_path_from(ROOT).to_s) }
    left = paths.flat_map do |path|
      # Whole text, comments too: a comment that names a dead identifier misleads as much.
      text = File.read(path)
      tokens = text.scan(TOKEN) + text.scan(UNDERSCORE_TOKEN).map { |token| token.tr("_", "-") }
      tokens.uniq.select { |token| ORIGINAL.include?(self.class.owner(token, known)) }.map { |token| "#{Pathname(path).relative_path_from(ROOT)}: #{token}" }
    end
    assert_empty left, "old one-level identifiers (see ORIGINAL):\n#{left.join("\n")}"
  end

  test "every data-controller value that names an admin controller names a controller file exactly" do
    identifiers = self.class.identifiers
    skipped = 0
    wrong = %w[app/components app/views app/helpers].flat_map { |dir| Dir[ROOT.join(dir, "**/*.{rb,erb}")] }.flat_map do |path|
      dynamic, static = self.class.controller_values(File.read(path))
      skipped += dynamic.size
      static.flat_map(&:split).select { |name| name.start_with?("admin--") && !identifiers.include?(name) }.map { |name| "#{Pathname(path).relative_path_from(ROOT)}: #{name}" }
    end
    assert_empty wrong, "data-controller names no controller file exactly (#{skipped} values built at run time were skipped):\n#{wrong.join("\n")}"
  end

  test "the data-controller reader sees markup and Ruby spellings, and sets run-time values aside" do
    text = %(<div data-controller="admin--a admin--b" class="x"> <%= tag.div data: { controller: "admin--c" } %> ) +
           %(h = { "data-controller" => "admin--d", controller: "admin/posts" } ) +
           %(<i data-controller="admin--e <%= more %>"> x(controller: "admin--f-\#{kind}"))
    dynamic, static = self.class.controller_values(text)
    assert_equal [ "admin--a admin--b", "admin--c", "admin--d", "admin/posts" ], static
    assert_equal 2, dynamic.size
  end
end
