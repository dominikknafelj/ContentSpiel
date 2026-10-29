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

  test "body_content is :rich unless declared, takes :table, refuses anything else; an outside type may not declare :table" do
    d = definition
    assert_equal :rich, d.body_content
    d.body_content :table
    assert_equal :table, d.body_content
    assert_equal :table, definition.tap { |other| other.body_content "table" }.body_content
    assert_match(/\Atest_shape: body_content is one of rich, table/, assert_raises(ArgumentError) { definition.body_content :markdown }.message)

    error = assert_raises(ArgumentError) { BlockTypes.register("gem_owner/grid") { |t| t.body_content :table } }
    assert_match(/\Agem_owner\/grid: .*body_content :table/, error.message)
    assert_not_includes BlockTypes.all.map(&:name), "gem_owner/grid"
    BlockTypes.register("gem_owner/words") { |t| t.body_content :rich; TestTypes.declare(t) }
  ensure
    Rails.application.reloader.prepare!
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

  test "an outside type's token names start with its owner, and its stylesheet is an absolute path that holds no colour literal" do
    saved = BlockTypes.all.dup
    error = assert_raises(ArgumentError) { BlockTypes.register("gallery/album") { |t| TestTypes.declare(t); t.tokens themed: %w[frame] } }
    assert_includes error.message, "gallery-"

    error = assert_raises(ArgumentError) { BlockTypes.register("gallery/album") { |t| TestTypes.declare(t); t.stylesheet "album.css" } }
    assert_includes error.message, "absolute"

    Dir.mktmpdir do |dir|
      sheet = Pathname(dir).join("album.css")
      sheet.write(%(:root { --th-gallery-frame: #ff0000; }))
      error = assert_raises(ArgumentError) { BlockTypes.register("gallery/album") { |t| TestTypes.declare(t); t.tokens themed: %w[gallery-frame]; t.stylesheet sheet } }
      assert_includes error.message, "colour"
      assert_includes error.message, "var()"

      [ "rgb(0,0,0)", "rgba(0,0,0,1)", "hsl(0 0% 0%)", "oklch(0.5 0 0)", "#fff" ].each do |literal|
        sheet.write(%(.content-block--gallery-album { color: #{literal}; }))
        assert_raises(ArgumentError, literal) { BlockTypes.register("gallery/album") { |t| TestTypes.declare(t); t.stylesheet sheet } }
      end
      sheet.write(%(.content-block--gallery-album { color: color-mix(in oklab, var(--th-ink) 60%, var(--th-page)); }))
      assert BlockTypes.register("gallery/album") { |t| TestTypes.declare(t); t.stylesheet sheet }, "a mix of base tokens is no literal"
    end
  ensure
    BlockTypes.reset!
    saved.each { |definition| BlockTypes.registry_put(definition) }
  end

  # Task 6 review I2: a colour is a value's, never a selector's, a
  # comment's or a string's, and every kind of literal is one.
  test "the colour guard reads declaration values: every kind of literal is refused, a selector, a comment and a string are not" do
    rule = ->(declaration) { ".content-block--gallery-album { #{declaration}; }" }
    refused = [ "border: 1px solid red", "color: White", "color: lab(50% 40 59)", "color: oklab(0.5 0.1 0.1)", "color: hwb(0 0% 0%)",
                "color: color(display-p3 1 0 0)", "color: color-mix(in oklab, red 40%, var(--th-ink))", "color: #ff0000",
                "color: rgb(0 0 0)", "color: rgba(0,0,0,1)", "color: hsl(0 0% 0%)", "color: hsla(0,0%,0%,1)", "color: oklch(0.5 0 0)",
                "color: lch(50% 0 0)", "--th-gallery-frame: tomato" ]
    refused.each { |css| assert ContentModel::BlockTypeDefinition.colour_literal?(rule.(css)), "#{css} was let through" }

    passed = [ "#fade { color: var(--th-ink); }", "li:has(#bead) { color: var(--th-ink); }", "/* not #fff, nor red */ .a { color: var(--th-ink); }",
               ".a { color: var(--th-red); }", ".a { animation-name: red-pulse; }", %(.a::before { content: "#bad red"; }),
               ".a { background: url(red.png); }", ".a { color: color-mix(in oklab, var(--th-ink) 60%, var(--th-page)); }",
               ".a { color: currentcolor; border-color: transparent; }", ".red { color: var(--th-ink); }" ]
    passed.each { |css| assert_not ContentModel::BlockTypeDefinition.colour_literal?(css), "#{css} was refused" }
  end

  test "an outside type's stylesheet is one file: an @import is refused" do
    saved = BlockTypes.all.dup
    Dir.mktmpdir do |dir|
      sheet = Pathname(dir).join("album.css")
      sheet.write(%(@import "./colours.css";\n.a { color: var(--th-ink); }))
      error = assert_raises(ArgumentError) { BlockTypes.register("gallery/album") { |t| TestTypes.declare(t); t.stylesheet sheet } }
      assert_includes error.message, "@import"
    end
  ensure
    BlockTypes.reset!
    saved.each { |definition| BlockTypes.registry_put(definition) }
  end

  # Task 6 review M2: a token name has no underscore, so an owner with one
  # names its tokens with a dash.
  test "an owner with an underscore names its tokens with a dash" do
    saved = BlockTypes.all.dup
    assert BlockTypes.register("photo_gallery/album") { |t| TestTypes.declare(t); t.tokens themed: %w[photo-gallery-frame] }
    error = assert_raises(ArgumentError) { BlockTypes.register("photo_gallery/strip") { |t| TestTypes.declare(t); t.tokens themed: %w[gallery-frame] } }
    assert_includes error.message, "photo-gallery-"
  ensure
    BlockTypes.reset!
    saved.each { |definition| BlockTypes.registry_put(definition) }
  end

  # Task 3 review M4: a gem's missing stylesheet stops the boot as that
  # type's, not as a bare Errno::ENOENT.
  test "an outside type's stylesheet that is not there is refused with the type's name" do
    saved = BlockTypes.all.dup
    error = assert_raises(ArgumentError) { BlockTypes.register("gallery/album") { |t| TestTypes.declare(t); t.stylesheet Pathname("/nowhere/gallery/album.css") } }
    assert_includes error.message, "gallery/album: "
    assert_includes error.message, "/nowhere/gallery/album.css"
  ensure
    BlockTypes.reset!
    saved.each { |definition| BlockTypes.registry_put(definition) }
  end

  # Task 3 review M5: an engine's component with no template of its own
  # (an inline `erb_template`) still has a folder the build scans.
  test "a component's folder is the folder of its source, with or without a template beside it" do
    assert_equal Rails.root.join("app/components/blocks"), BlockTypes.fetch(:code).component_folder
    d = definition
    d.component TestQuoteComponent
    assert_nil d.component_template
    assert_equal Rails.root.join("test/support"), d.component_folder
    assert_nil definition.component_folder
  end

  test "a block type without theme methods or a sample is refused, and the message says what to declare" do
    saved = BlockTypes.all.dup
    error = assert_raises(ArgumentError) { BlockTypes.register(:test_bare) { |t| t.label "Bare"; t.sample shows: [ "x" ] } }
    assert_includes error.message, "theme_methods"
    error = assert_raises(ArgumentError) { BlockTypes.register(:test_bare) { |t| t.label "Bare"; t.theme_methods :block, :page } }
    assert_includes error.message, "sample"
    assert_nil BlockTypes.find(:test_bare)
  ensure
    BlockTypes.reset!
    saved.each { |definition| BlockTypes.registry_put(definition) }
  end

  # Task 8 review M3: no reader asks for a capability the CMS does not know,
  # so claiming one (`:code` was one until the Code block's conversion) would
  # be a promise nothing keeps.
  test "a capability the CMS does not know is refused at registration, naming the type and the capability" do
    saved = BlockTypes.all.dup
    error = assert_raises(ArgumentError) { BlockTypes.register(:test_coded) { |t| TestTypes.declare(t); t.capability :code } }
    assert_includes error.message, "test_coded"
    assert_includes error.message, ":code"
    assert_nil BlockTypes.find(:test_coded)
  ensure
    BlockTypes.reset!
    saved.each { |definition| BlockTypes.registry_put(definition) }
  end

  test "a block type's icon is one CS Studio draws, or none" do
    definition = ContentModel::BlockTypeDefinition.new("x")
    assert_nil definition.icon

    definition.icon :pilcrow
    assert_equal "pilcrow", definition.icon
    error = assert_raises(ArgumentError) { ContentModel::BlockTypeDefinition.new("x").icon "rocket" }
    assert_match(/\Ax: icon is one of pilcrow, image, code_xml, posts, columns_2, info, lightbulb, circle_alert, triangle_alert/, error.message)
  end

  # Note block plan, ruling 12: the Note's icon in the picker is its type's
  # (`info`), and on a block's card and tile its kind's. A callable answers
  # it for each block, from the same closed list.
  test "a block type's icon may follow its block: the callable answers one of the list for each block, and the type's own stands where there is no block" do
    definition = ContentModel::BlockTypeDefinition.new("x")
    definition.icon :info, for_block: ->(block) { block.settings["tone"] == "loud" ? "triangle_alert" : "info" }

    assert_equal "info", definition.icon
    assert definition.icon_follows_block?
    assert_equal "triangle_alert", definition.icon_for(ContentBlock.new(settings: { "tone" => "loud" }))
    assert_equal "info", definition.icon_for(ContentBlock.new(settings: {}))
    assert_equal "info", definition.icon_for(nil), "the picker has no block"

    plain = ContentModel::BlockTypeDefinition.new("y").tap { |type| type.icon :pilcrow }
    assert_not plain.icon_follows_block?
    assert_equal "pilcrow", plain.icon_for(ContentBlock.new(settings: { "tone" => "loud" }))
    assert_nil ContentModel::BlockTypeDefinition.new("z").icon_for(ContentBlock.new), "a type with no icon has none for its blocks"

    error = assert_raises(ArgumentError) { ContentModel::BlockTypeDefinition.new("x").icon :info, for_block: "triangle_alert" }
    assert_includes error.message, "callable"
  end

  test "a block's icon off the list raises, naming the list, and never reaches the page as markup" do
    definition = ContentModel::BlockTypeDefinition.new("x")
    definition.icon :info, for_block: ->(_block) { "<svg onload=x>" }

    error = assert_raises(ArgumentError) { definition.icon_for(ContentBlock.new) }
    assert_match(/\Ax: its icon for a block is one of pilcrow, .*, triangle_alert/, error.message)
  end

  # An outside type's callable would be asked on every card and tile of the
  # editor, where a raise is a 500: not yet (plan ruling 12).
  test "a block type from outside names one icon for all its blocks: for_block is refused at registration" do
    definition = ContentModel::BlockTypeDefinition.new("gallery/flag")
    definition.icon :info, for_block: ->(_block) { "info" }

    error = assert_raises(ArgumentError) { definition.finalize! }
    assert_match(/\Agallery\/flag: a block type from outside names one icon/, error.message)
  end

  # Task 8 review M2: the tile's cut and the Code block's summary's are one
  # figure, held by the definition (a model may not name a component).
  test "the tile and the Code block's summary cut a line at one length" do
    assert_equal ContentModel::BlockTypeDefinition::SUMMARY_LENGTH, Admin::EditorScreen::TileSummaryComponent::LENGTH
    assert_equal ContentModel::BlockTypeDefinition::SUMMARY_LENGTH, BlockTypes::Code::SUMMARY_LENGTH
  end
end
