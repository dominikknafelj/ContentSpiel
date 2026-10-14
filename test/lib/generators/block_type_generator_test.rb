require "test_helper"
require "rails/generators/test_case"
require "generators/block_type/block_type_generator"

# `bin/rails generate block_type <name>` (block types spec, "The generator"):
# a built-in type of this repository, which registers, joins the contract
# and every shared test, and passes the guards as written. The whole suite
# cannot run in a test, so the generated files are written into a temporary
# folder, loaded, registered and put through the derived checks here; the
# whole suite is run once with a generated type by hand (the plan's Task 11).
class BlockTypeGeneratorTest < Rails::Generators::TestCase
  tests BlockTypeGenerator
  MARKED = %w[config/initializers/types.rb config/locales/public.en.yml config/locales/admin/editor_screen.en.yml].freeze

  # A folder per process: the parallel workers deal out this class's tests
  # one by one, and `prepare_destination` empties the folder it is given, so
  # a shared one was emptied under another worker's test.
  setup do
    self.destination_root = Rails.root.join("tmp/generators/#{Process.pid}").to_s
    prepare_destination
    MARKED.each { |file| FileUtils.mkdir_p(File.dirname(File.join(destination_root, file))); FileUtils.cp(Rails.root.join(file), File.join(destination_root, file)) }
  end

  teardown { FileUtils.rm_rf(destination_root) }

  test "it writes the definition, its line, the component, the stylesheet, the scopes, a preview and two tests" do
    run_generator %w[callout]

    assert_file "app/models/block_types/callout.rb", /BlockTypes.register :callout/, /t.theme_methods :block, :page/, /t.stylesheet "callout.css"/, /t.sample /
    assert_file "config/initializers/types.rb", /BlockTypes::Section.register\n    BlockTypes::Callout.register\n    # bin\/rails generate block_type adds/
    assert_file "app/components/blocks/callout_component.rb", /def initialize\(block:, page:\)/, /def render\?/
    assert_file "app/components/blocks/callout_component.html.erb", /content-block content-block--callout/
    assert_file "app/assets/tailwind/themes/default/callout.css", /\.content-block--callout/
    assert_file "config/locales/public.en.yml", /adds a type's scope below this line.\n\s+callout: \{\}/
    assert_file "config/locales/admin/editor_screen.en.yml", /adds a type's scope below this line.\n\s+callout: \{\}/
    assert_file "test/components/previews/blocks/callout_component_preview.rb"
    assert_file "test/models/block_types/callout_test.rb"
    assert_file "test/components/blocks/callout_component_test.rb"
  end

  test "the markers are the files' own lines, character for character" do
    MARKED.zip([ BlockTypeGenerator::TYPES_MARKER, BlockTypeGenerator::PUBLIC_MARKER, BlockTypeGenerator::TILE_MARKER ]).each do |file, marker|
      assert_equal 1, Rails.root.join(file).read.scan(marker).size, "#{file} holds its marker line once"
    end
  end

  test "a locale file without its marker gets nothing, and the generator says so" do
    File.write(File.join(destination_root, "config/locales/public.en.yml"), "en:\n  public:\n    blocks: {}\n")
    output = run_generator %w[callout]

    assert_includes output, "config/locales/public.en.yml has no marker line"
    assert_file "config/locales/public.en.yml", "en:\n  public:\n    blocks: {}\n"
  end

  # `debug: true` makes Thor raise the refusal instead of printing it to
  # standard error, which `run_generator` does not capture.
  test "a name with an owner, and one that is no type name, are refused" do
    assert_includes assert_raises(Thor::Error) { run_generator %w[gallery/album], debug: true }.message, "an outside type is an engine's"
    assert_no_file "app/models/block_types/album.rb"
    assert_includes assert_raises(Thor::Error) { run_generator %w[Call-Out], debug: true }.message, "lowercase"
  end

  # Under a name of its own, not `callout`: the plan's hand run generates
  # `callout` into the application and runs the whole suite with it, and a
  # second `callout` here would be a duplicate registration, and taking away
  # the constant Zeitwerk loaded would leave the worker's registries empty.
  # So the ensure removes only what this test defined.
  test "a generated type registers, joins the contract and every shared test, and its sample draws its words" do
    ours = []
    run_generator %w[generated_callout]
    ours << :component unless Blocks.const_defined?(:GeneratedCalloutComponent, false)
    load File.join(destination_root, "app/components/blocks/generated_callout_component.rb")
    ours << :type unless BlockTypes.const_defined?(:GeneratedCallout, false)
    load File.join(destination_root, "app/models/block_types/generated_callout.rb")
    BlockTypes::GeneratedCallout.register

    assert_equal %w[block page], Theme::Contract.components.fetch("blocks/generated_callout_component")
    page = create_page(title: "Callout")
    block = sample_block(page, "generated_callout")
    render = ApplicationController.render(Blocks::GeneratedCalloutComponent.new(block: block, page: page), layout: false)
    BlockTypes.fetch(:generated_callout).sample.shows.each { |text| assert_includes render, text }
    assert_includes Admin::EditorScreen::HeldFields.allowed_actions, "admin--ui--menu#close"
  ensure
    Blocks.send(:remove_const, :GeneratedCalloutComponent) if ours&.include?(:component) && Blocks.const_defined?(:GeneratedCalloutComponent, false)
    BlockTypes.send(:remove_const, :GeneratedCallout) if ours&.include?(:type) && BlockTypes.const_defined?(:GeneratedCallout, false)
    Rails.application.reloader.prepare!
  end
end
