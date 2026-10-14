require "test_helper"
require "rails/generators/test_case"
require "generators/block_type/block_type_generator"

# `bin/rails generate block_type <name>` (block types spec, "The generator"):
# a built-in type of this repository, which registers, joins the contract
# and the shared samples, and passes the guards as written. The whole suite
# cannot run in a test, so the generated files are written into a temporary
# folder, loaded, registered and put through the derived checks here; the
# whole suite is run once with a generated type by hand (the plan's Task 11).
#
# Every case generates `generated_callout`, never `callout`: the hand run
# generates `callout` into the application, where the generator then refuses
# it as a block type that exists, and an in-process registration of the same
# name would be a duplicate.
class BlockTypeGeneratorTest < Rails::Generators::TestCase
  tests BlockTypeGenerator
  MARKED = %w[config/initializers/types.rb config/locales/public.en.yml config/locales/admin/editor_screen.en.yml].freeze
  NAME = "generated_callout".freeze
  WRITTEN = %w[
    app/models/block_types/generated_callout.rb
    app/components/blocks/generated_callout_component.rb
    app/components/blocks/generated_callout_component.html.erb
    app/assets/tailwind/themes/default/generated_callout.css
    test/components/previews/blocks/generated_callout_component_preview.rb
    test/models/block_types/generated_callout_test.rb
    test/components/blocks/generated_callout_component_test.rb
  ].freeze

  # A folder per process: the parallel workers deal out this class's tests
  # one by one, and `prepare_destination` empties the folder it is given, so
  # a shared one was emptied under another worker's test.
  setup do
    self.destination_root = Rails.root.join("tmp/generators/#{Process.pid}").to_s
    prepare_destination
    MARKED.each { |file| copy_in(file) }
  end

  teardown { FileUtils.rm_rf(destination_root) }

  def copy_in(file)
    FileUtils.mkdir_p(File.dirname(File.join(destination_root, file)))
    FileUtils.cp(Rails.root.join(file), File.join(destination_root, file))
  end

  def contents(files) = files.to_h { |file| [ file, File.read(File.join(destination_root, file)) ] }

  # `debug: true` makes Thor raise a refusal instead of printing it to
  # standard error, which `run_generator` does not capture.
  def refusal(*args, behavior: :invoke) = assert_raises(Thor::Error) { run_generator args, behavior: behavior, debug: true }.message

  test "it writes the definition, its line, the component, the stylesheet, the scopes, a preview and two tests" do
    run_generator [ NAME ]

    assert_file "app/models/block_types/generated_callout.rb", /BlockTypes.register :generated_callout/, /t.theme_methods :block, :page/,
                /t.stylesheet "generated_callout.css"/, /t.sample /, /#{BlockTypeGenerator::GENERATED}/
    assert_file "config/initializers/types.rb", /\n    BlockTypes::GeneratedCallout.register\n    # bin\/rails generate block_type adds/
    assert_file "app/components/blocks/generated_callout_component.rb", /def initialize\(block:, page:\)/, /def render\?/
    assert_file "app/components/blocks/generated_callout_component.html.erb", /content-block content-block--generated_callout/
    assert_file "app/assets/tailwind/themes/default/generated_callout.css", /\.content-block--generated_callout/, /#{BlockTypeGenerator::GENERATED}/
    assert_file "config/locales/public.en.yml", /adds a type's scope below this line.\n\s+generated_callout: \{\}/
    assert_file "config/locales/admin/editor_screen.en.yml", /adds a type's scope below this line.\n\s+generated_callout: \{\}/
    WRITTEN.each { |file| assert_file file }
  end

  test "the markers are the files' own lines, character for character" do
    MARKED.zip([ BlockTypeGenerator::TYPES_MARKER, BlockTypeGenerator::PUBLIC_MARKER, BlockTypeGenerator::TILE_MARKER ]).each do |file, marker|
      assert_equal 1, Rails.root.join(file).read.scan(marker).size, "#{file} holds its marker line once"
    end
  end

  test "a locale file without its marker gets nothing, and the generator says so" do
    File.write(File.join(destination_root, "config/locales/public.en.yml"), "en:\n  public:\n    blocks: {}\n")
    output = run_generator [ NAME ]

    assert_includes output, "config/locales/public.en.yml has no marker line"
    assert_file "config/locales/public.en.yml", "en:\n  public:\n    blocks: {}\n"
  end

  test "a name with an owner, and one that is no type name, are refused" do
    assert_includes refusal("gallery/album"), "an outside type is an engine's"
    assert_no_file "app/models/block_types/album.rb"
    assert_includes refusal("Call-Out"), "lowercase"
    %w[callout_ a__b x_2 _x].each { |name| assert_includes refusal(name), "lowercase words", name }
    assert_includes refusal("on"), "a locale file reads on: as true"
    assert_includes refusal("null"), "as nil"
  end

  # A name is refused for what it would collide with, and nothing is written.
  test "a constant of the application, a block type, a stylesheet of the default theme and files that exist are refused, and nothing is written" do
    before = contents(MARKED)

    assert_includes refusal("post"), "Post is a constant of the application"
    assert_includes refusal("blocks"), "Blocks is a constant of the application"
    assert_includes refusal("content_model"), "ContentModel is a constant of the application"
    assert_includes refusal("code"), "is a block type already"
    assert_includes refusal("tokens"), "tokens.css is a stylesheet of the default theme"
    assert_includes refusal("prose"), "prose.css is a stylesheet of the default theme"

    copy_in("app/components/blocks/code_component.rb")
    FileUtils.mv(File.join(destination_root, "app/components/blocks/code_component.rb"), File.join(destination_root, "app/components/blocks/generated_callout_component.rb"))
    assert_includes refusal(NAME), "these files exist, and a generator writes only new ones: app/components/blocks/generated_callout_component.rb"

    assert_equal before, contents(MARKED)
    (WRITTEN - %w[app/components/blocks/generated_callout_component.rb]).each { |file| assert_no_file file }
  end

  # Destroy takes back exactly what generate wrote: the files and the three
  # lines. Two edges stay as Thor has them (USAGE says so): a scope a person
  # has filled is not `name: {}` any more and stays where it is, and a
  # locale file without its marker gets the same "by hand" line.
  test "destroy takes back every file and every line the generator wrote" do
    before = contents(MARKED)
    run_generator [ NAME ]
    run_generator [ NAME ], behavior: :revoke

    WRITTEN.each { |file| assert_no_file file }
    assert_equal before, contents(MARKED)
  end

  # Destroy removes only what this generator wrote and nobody has taken as
  # theirs: the Code block's definition, a stylesheet of the default theme,
  # and a generated type whose definition lost its line are left whole.
  test "destroy refuses a built-in, a stylesheet of the default theme, a constant and a type that is no longer the generator's, and removes nothing" do
    code = %w[app/models/block_types/code.rb app/components/blocks/code_component.rb app/components/blocks/code_component.html.erb app/assets/tailwind/themes/default/code.css
              app/assets/tailwind/themes/default/tokens.css test/components/blocks/code_component_test.rb]
    code.each { |file| copy_in(file) }
    before = contents(MARKED + code)

    assert_includes refusal("code", behavior: :revoke), "app/models/block_types/code.rb and app/assets/tailwind/themes/default/code.css carry no line"
    assert_includes refusal("tokens", behavior: :revoke), "has no definition this generator wrote"
    assert_includes refusal("blocks", behavior: :revoke), "Blocks is a constant of the application"
    assert_includes refusal("post", behavior: :revoke), "Post is a constant of the application"
    assert_equal before, contents(MARKED + code)

    run_generator [ NAME ]
    definition = File.join(destination_root, WRITTEN.first)
    File.write(definition, File.read(definition).sub(BlockTypeGenerator::GENERATED, "Ours now"))
    assert_includes refusal(NAME, behavior: :revoke), "app/models/block_types/generated_callout.rb carries no line"
    WRITTEN.each { |file| assert_file file }
  end

  # Under a name of its own, not `callout` (see the class's comment), and the
  # ensure removes only what this test defined: taking away a constant
  # Zeitwerk loaded would leave the worker's registries empty.
  test "a generated type registers, joins the contract and the shared samples, and its sample draws its words" do
    ours = []
    run_generator [ NAME ]
    ours << :component unless Blocks.const_defined?(:GeneratedCalloutComponent, false)
    load File.join(destination_root, "app/components/blocks/generated_callout_component.rb")
    ours << :type unless BlockTypes.const_defined?(:GeneratedCallout, false)
    load File.join(destination_root, "app/models/block_types/generated_callout.rb")
    BlockTypes::GeneratedCallout.register

    assert_equal %w[block page], Theme::Contract.components.fetch("blocks/generated_callout_component")
    assert_includes sampled_types.map(&:name), NAME, "every shared test builds the type from its sample"
    page = create_page(title: "Callout")
    block = sample_block(page, NAME)
    render = ApplicationController.render(Blocks::GeneratedCalloutComponent.new(block: block, page: page), layout: false)
    BlockTypes.fetch(NAME).sample.shows.each { |text| assert_includes render, text }
  ensure
    Blocks.send(:remove_const, :GeneratedCalloutComponent) if ours&.include?(:component) && Blocks.const_defined?(:GeneratedCalloutComponent, false)
    BlockTypes.send(:remove_const, :GeneratedCallout) if ours&.include?(:type) && BlockTypes.const_defined?(:GeneratedCallout, false)
    Rails.application.reloader.prepare!
  end
end
