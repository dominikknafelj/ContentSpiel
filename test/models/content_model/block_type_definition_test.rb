require "test_helper"

# What a block type declares beside its fields (block types spec, decision 1):
# the names a theme may call, its tokens, its stylesheet, its tile line, its
# editor script's read-only actions and one filled sample. Each is read by a
# list that used to be written by hand; here only their shapes are held.
class ContentModel::BlockTypeDefinitionTest < ActiveSupport::TestCase
  def definition(name = "test_shape") = ContentModel::BlockTypeDefinition.new(name)

  test "the six declarations are read back as they were given, and are empty or nil when not given" do
    summary = ->(_block, locale:) { [ [ :text, locale ] ] }
    d = definition
    assert_nil d.theme_methods
    assert_equal [], d.themed_tokens
    assert_equal [], d.fixed_tokens
    assert_nil d.stylesheet
    assert_nil d.summary
    assert_equal [], d.read_only_actions
    assert_nil d.sample

    d.theme_methods :block, :page, :titled?
    d.tokens themed: %w[shape-ground], fixed: %w[shape-gap]
    d.stylesheet "shape.css"
    d.summary summary
    d.read_only_actions "admin--ui--char-count#update"
    d.sample settings: { language: "ruby" }, translations: { "en" => { caption: "A caption" } }, body: "Some **words**", image: true, shows: [ "A caption" ]

    assert_equal %w[block page titled?], d.theme_methods
    assert_predicate d.theme_methods, :frozen?
    assert_equal %w[shape-ground], d.themed_tokens
    assert_equal %w[shape-gap], d.fixed_tokens
    assert_equal "shape.css", d.stylesheet
    assert_same summary, d.summary
    assert_equal %w[admin--ui--char-count#update], d.read_only_actions
    assert_equal({ "language" => "ruby" }, d.sample.settings)
    assert_equal({ "en" => { caption: "A caption" } }, d.sample.translations)
    assert_equal "Some **words**", d.sample.body
    assert_equal true, d.sample.image
    assert_equal [ "A caption" ], d.sample.shows
  end

  test "a declaration of the wrong shape is refused when it is written, and the message says the shape" do
    assert_match(/a method's name/, assert_raises(ArgumentError) { definition.theme_methods "Block" }.message)
    assert_match(/without the --th- prefix/, assert_raises(ArgumentError) { definition.tokens themed: %w[--th-x] }.message)
    assert_match(/without the --th- prefix/, assert_raises(ArgumentError) { definition.tokens fixed: %w[Shape_gap] }.message)
    assert_match(/identifier#method/, assert_raises(ArgumentError) { definition.read_only_actions "update" }.message)
    assert_match(/callable/, assert_raises(ArgumentError) { definition.summary "words" }.message)
    assert_match(/settings, translations, body, image, shows/, assert_raises(ArgumentError) { definition.sample shows: [ "x" ], blocks: [] }.message)
    assert_match(/at least one text/, assert_raises(ArgumentError) { definition.sample settings: {} }.message)
    assert_match(/at least one text/, assert_raises(ArgumentError) { definition.sample shows: [] }.message)
    assert_match(/"en" at least/, assert_raises(ArgumentError) { definition.sample translations: { "de" => { caption: "x" } }, shows: [ "x" ] }.message)
  end

  test "every refusal starts with the type's name, also when the type is registered" do
    messages = [
      -> { definition.theme_methods "Block" }, -> { definition.tokens themed: %w[--th-x] },
      -> { definition.read_only_actions "update" }, -> { definition.summary "words" },
      -> { definition.sample shows: [], settings: {} }, -> { definition.stylesheet "" },
      -> { definition.uses :subtitle }
    ].map { |call| assert_raises(ArgumentError, &call).message }
    messages.each { |message| assert_match(/\Atest_shape: /, message) }

    error = assert_raises(ArgumentError) { BlockTypes.register("gem_owner/cta") { |t| t.tokens themed: %w[Frame] } }
    assert_match(/\Agem_owner\/cta: /, error.message)
    assert_not_includes BlockTypes.all.map(&:name), "gem_owner/cta"
  end

  test "shapes the first test did not reach are refused too" do
    assert_match(/none of them blank/, assert_raises(ArgumentError) { definition.sample shows: [ " " ] }.message)
    assert_match(/image is true or false/, assert_raises(ArgumentError) { definition.sample image: "yes", shows: [ "x" ] }.message)
    assert_match(/settings are a Hash/, assert_raises(ArgumentError) { definition.sample settings: [], shows: [ "x" ] }.message)
    assert_match(/body is a Markdown String/, assert_raises(ArgumentError) { definition.sample body: 1, shows: [ "x" ] }.message)
    assert_match(/Hash of locale/, assert_raises(ArgumentError) { definition.sample translations: { "en" => "x" }, shows: [ "x" ] }.message)
    assert_match(/declared once/, assert_raises(ArgumentError) { definition.tokens themed: %w[a], fixed: %w[a] }.message)
    assert_match(/declared once/, assert_raises(ArgumentError) { definition.tokens themed: %w[a a] }.message)
    assert_match(/arrays/, assert_raises(ArgumentError) { definition.tokens themed: "a" }.message)
    assert_match(/declared once/, assert_raises(ArgumentError) { definition.read_only_actions "a--b#c", "a--b#c" }.message)
    assert_match(/\.css file/, assert_raises(ArgumentError) { definition.stylesheet :code }.message)
    assert_match(/\.css file/, assert_raises(ArgumentError) { definition.stylesheet "code.scss" }.message)
    assert_match(/callable/, assert_raises(ArgumentError) { definition.summary ->(block) { block } }.message)
    assert_match(/callable/, assert_raises(ArgumentError) { definition.summary ->(locale:) { locale } }.message)
    d = definition
    d.summary ->(block, **) { block }
    d.summary ->(block, locale: "en") { block }
  end

  test "uses outside body, caption, alt and image is refused" do
    d = definition
    d.uses :caption, :alt
    assert_equal %w[caption alt], d.uses_columns

    error = assert_raises(ArgumentError) { definition.uses :caption, :subtitle }
    assert_includes error.message, "subtitle"
    assert_includes error.message, "body, caption, alt, image"
  end

  test "owner is the part of the name before the slash, and a built-in has none" do
    assert_nil definition("code").owner
    assert_equal "gallery", definition("gallery/album").owner
  end

  test "a relative stylesheet is in the default theme's folder, an absolute one is taken as it is" do
    d = definition
    assert_nil d.stylesheet_path
    d.stylesheet "code.css"
    assert_equal Rails.root.join("app/assets/tailwind/themes/default/code.css"), d.stylesheet_path
    d.stylesheet Pathname("/srv/gem/album.css")
    assert_equal Pathname("/srv/gem/album.css"), d.stylesheet_path
  end

  test "a component's template is the file beside its source" do
    assert_equal Rails.root.join("app/components/blocks/code_component.html.erb"), BlockTypes.fetch(:code).component_template
    assert_nil definition.component_template
    d = definition
    d.component Class.new(ViewComponent::Base)
    assert_nil d.component_template, "an anonymous component has no source file to look beside"
  end

  test "a component without a template file answers nil" do
    d = definition
    d.component ContentModel::BlockTypeDefinition::Sample
    assert_nil d.component_template
  end
end
