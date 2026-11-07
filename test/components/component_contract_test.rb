require "test_helper"
require "open3"

# The common declaration (`ComponentContract`) refuses a declaration it
# cannot read, at the class's load, naming the keyword and the class.
class ComponentContractTest < ActiveSupport::TestCase
  VALID = {
    accessibility: "A sample: no role, no name, no keyboard.",
    motion: :none, content_edges: %i[long short], widths: :fluid, interface: %i[a], limits: [ "A sample." ]
  }.freeze

  def declare(**changes)
    klass = Class.new { include ComponentContract }
    klass.define_singleton_method(:name) { "SampleComponent" }
    klass.contract(**VALID, **changes)
    klass
  end

  test "a declaration with an unknown edge, width or motion, or no limit, is refused by name" do
    assert_equal :fluid, declare.contract.widths
    assert_predicate declare.contract, :frozen?

    {
      { content_edges: %i[long sideways] } => "content_edges",
      { widths: :wide } => "widths",
      { motion: :bouncy } => "motion",
      { limits: [] } => "limits",
      { accessibility: "" } => "accessibility",
      { interface: [ "a" ] } => "interface"
    }.each do |changes, keyword|
      error = assert_raises(ArgumentError) { declare(**changes) }
      assert_match keyword, error.message
      assert_match "SampleComponent", error.message
    end

    error = assert_raises(ArgumentError) { declare(colour: :red) }
    assert_match "colour", error.message
    error = assert_raises(ArgumentError) { Class.new { include ComponentContract }.tap { |k| k.define_singleton_method(:name) { "SampleComponent" } }.contract(**VALID.except(:limits)) }
    assert_match "limits", error.message
  end

  test "a class without a declaration answers nil" do
    assert_nil Class.new { include ComponentContract }.contract
  end

  # A stylesheet's build scans a component's file whole, the declaration
  # included, and builds a utility for every word in it that Tailwind knows:
  # a width named `container`, or "no filter" in a limit, added `.container`
  # and `.filter` to the public stylesheet. A declaration may still name a
  # method its own file defines (`block`, a keyword `ring`), since the file
  # already brings that word. So the rule: no word of a declaration that
  # Tailwind builds a utility from is missing from the rest of its file and
  # its templates. Tailwind itself says which words those are, by building
  # every declaration's text with each entry stylesheet as it is but for its
  # sources, against the same build of no text; the guard keeps no list of
  # utility names.
  ENTRIES = {
    "CS Studio's" => "app/assets/tailwind/application.css",
    "the default theme's" => "app/assets/tailwind/themes/default/theme.css"
  }.freeze

  def declaring_files
    Dir[Rails.root.join("app/components/**/*.rb")].sort.filter_map do |file|
      source = File.read(file)
      declaration = UiContract.contract_text(source)
      next if declaration.empty?

      templates = Dir["#{file.delete_suffix('.rb')}.*"].reject { |path| path == file }.map { |path| File.read(path) }
      own = [ UiContract.outside_contract(source).map { |_, _, text| text }.join, *templates ].join("\n")
      [ file.delete_prefix("#{Rails.root}/"), declaration, own ]
    end
  end

  # The selectors each entry stylesheet builds from `text` and not from
  # nothing, by the entry's name.
  def utilities_from(text)
    Dir.mktmpdir do |dir|
      ENTRIES.to_h { |name, entry| [ name, built_selectors(dir, entry, text) - built_selectors(dir, entry, "") ] }
    end
  end

  def built_selectors(dir, entry, text)
    path = Rails.root.join(entry)
    key = "#{entry.hash.abs}-#{text.hash.abs}"
    source = File.join(dir, "source-#{key}.txt")
    File.write(source, text)
    css = path.read.gsub(/^@source .*$/, "")
      .sub('@import "tailwindcss" source(none);') { |line| "#{line}\n@source \"#{source}\";" }
      .gsub(%r{@import "\./([^"]+)"}) { "@import \"#{path.dirname.join(Regexp.last_match(1))}\"" }
    input = File.join(dir, "entry-#{key}.css")
    File.write(input, css)
    output, status = Open3.capture2e(Tailwindcss::Ruby.executable, "-i", input, "-o", "#{input}.out")
    assert status.success?, "the Tailwind build of #{entry} for the declarations failed: #{output}"
    File.read("#{input}.out").scan(/^\s*([.][^{]*?)\s*\{/).flatten.to_set
  end

  def utility_words(text) = utilities_from(text).values.reduce(:|).map { |selector| selector.delete_prefix(".").delete("\\") }

  # The words of `words` that `declaration` holds and `own` does not, each
  # read as Tailwind reads a candidate: bounded by anything but a letter, a
  # digit, `_` and `-`.
  def leaked_words(declaration, own, words)
    token = ->(text, word) { text.match?(/(?<![\w-])#{Regexp.escape(word)}(?![\w-])/) }
    words.select { |word| token.(declaration, word) && !token.(own, word) }
  end

  test "a declaration adds no utility to a stylesheet: each word Tailwind builds from it is its file's already" do
    files = declaring_files
    assert_operator files.size, :>=, 60, "the declarations were not found"
    words = utility_words(files.map { |_, declaration, _| declaration }.join("\n"))
    assert_includes words, "block", "the build of the declarations found none of their words"

    leaks = files.to_h { |file, declaration, own| [ file, leaked_words(declaration, own, words) ] }.reject { |_, found| found.empty? }
    assert_empty leaks, "these declarations add a utility to a stylesheet that their files do not already build: " \
      "#{leaks.map { |file, found| "#{file} (#{found.join(', ')})" }.join('; ')}. Reword the sentence or rename the value"
  end

  test "the utility guard can fail: a declaration's container, hidden and filter are built and named" do
    words = utility_words('contract(widths: :from_container, limits: [ "It fills its container and has no filter at all; it is hidden from view" ])')
    %w[container hidden filter].each { |word| assert_includes words, word }
    assert_not_includes words, "from_container"

    assert_equal %w[container filter], leaked_words('limits: [ "It fills its container and has no filter at all; it is hidden from view" ]', '<div hidden class="block">', words).sort
    assert_empty leaked_words("interface: %i[block page]", "def block = @block", %w[block])
  end
end
