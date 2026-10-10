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
    test/lib/layout_tools_test.rb
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

  test "a locale file of admin components holds one folder's scope" do
    Dir[ROOT.join("config/locales/admin/*.en.yml")].each do |path|
      name = File.basename(path, ".en.yml")
      next if LOCALE_EXCEPTIONS.include?(name)
      scopes = (YAML.load_file(path).dig("en", "admin", "components") || {}).keys
      next if scopes.empty?
      assert_equal [ name ], scopes, "#{File.basename(path)} holds #{scopes.inspect}"
    end
  end

  test "a component scope has keys in one locale file, except where an exception names it" do
    holders = Hash.new { |hash, scope| hash[scope] = [] }
    Dir[ROOT.join("config/locales/admin/*.en.yml")].each do |path|
      name = File.basename(path, ".en.yml")
      next if LOCALE_EXCEPTIONS.include?(name)
      (YAML.load_file(path).dig("en", "admin", "components") || {}).each_key { |scope| holders[scope] << name }
    end
    assert_empty holders.select { |_, files| files.size > 1 }, "a scope's keys are in two files"
    assert_empty holders.keys - Dir[ROOT.join("app/components/admin/*")].select { |p| File.directory?(p) }.map { |p| File.basename(p) },
      "a locale file names a scope with no component folder"
  end
end
