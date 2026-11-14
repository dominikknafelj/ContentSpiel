require "test_helper"

# The `:mermaid` field type (Diagram block spec, §1, §5 and §7): a Mermaid
# source, kept as typed like `:code` and refused only for its length, in
# every language the object holds. `Diagrams::Source`'s line rules are the
# editor's and the frame's, never a save's.
class ContentModel::MermaidFieldTest < ActiveSupport::TestCase
  def define(**source_options)
    ContentModel::BlockTypeDefinition.new("sample").tap do |t|
      t.field :source, :mermaid, translated: true, drawing: :drawing, max: 50, **source_options
      t.field :drawing, :diagram_drawing, translated: true
    end
  end

  def fields(values, translations = {}, options = {}) = ContentModel::FieldSet.for(define).new({}, translations, locale: options.fetch(:locale, "en")).assign(values)

  def sentences(values, translations = {}, options = {}) = fields(values, translations, options).tap(&:valid?).errors[:source]

  test "mermaid keeps text as typed with \\n line endings and outer blank lines dropped" do
    assert_equal "flowchart LR\n\tA --> B\n\n  B", fields("source" => "\n \r\nflowchart LR\r\n\tA --> B\r\n\r\n  B\n\t\n").source
    assert_nil fields("source" => " \n\t\n").source
    assert_equal({ "en" => { "source" => "pie\n  \"a\" : 1" } }, fields("source" => "pie\r  \"a\" : 1").all_translations)
  end

  # The line rules are the editor's and the frame's: a save that holds a
  # refused line, a type off the list or a first line with no type is
  # stored as typed, as any half-typed source is (Diagram block spec §7: a
  # refused save is a hand-made request's alone).
  test "a source with lines the rules refuse is stored as typed, with no error" do
    [ "flowchart LR\n  classDef a fill:red", "flowchart LR\n  A --> B\n  click A x", "---\ntitle: x\n---\nflowchart LR",
      "flowchart LR\n  A[$$x$$]", "mindmap\n  root", "A --> B", "flowchart LR\n  %%{init: {}}%%" ].each do |source|
      assert_not_empty Diagrams::Source.refusals(source), "the rules refuse #{source.inspect}"
      field_set = fields("source" => source)
      assert field_set.valid?, "#{source.inspect}: #{field_set.errors.full_messages.inspect}"
      assert_equal source, field_set.source
    end
  end

  test "more characters than max is the Code field's own refusal, and past the source's limit too without a max" do
    assert_equal [ "is too long (maximum is 50 characters)" ], sentences("source" => "flowchart LR\n#{"A-->B\n" * 10}")

    unlimited = ContentModel::BlockTypeDefinition.new("sample").tap do |t|
      t.field :source, :mermaid, drawing: :drawing
      t.field :drawing, :diagram_drawing
    end
    over = unlimited.field_set.new({}).assign("source" => "pie\n#{"x" * Diagrams::Source::MAX_CHARACTERS}").tap(&:valid?)
    assert_equal [ "is too long (maximum is 10,000 characters)" ], over.errors[:source]
  end

  test "mermaid may be translated and is never offered to the AI, and is audited as a digest" do
    type = ContentModel::FieldTypes.fetch(:mermaid)

    assert define.fields.first.translated?
    assert_not type.translatable
    assert_equal :digest, type.audit
  end

  test "a source over the limit in another language is refused too, once" do
    long = "flowchart LR\n#{"A-->B\n" * 10}"
    german = sentences({ "source" => long }, { "en" => { "source" => "flowchart LR\n  A --> B" } }, locale: "de")

    assert_equal [ "is too long (maximum is 50 characters)" ], german

    both = { "en" => { "source" => long }, "de" => { "source" => long } }
    assert_equal 1, ContentModel::FieldSet.for(define).new({}, both, locale: "en").tap(&:valid?).errors[:source].size
    assert_empty sentences({ "source" => "flowchart LR\n  style A fill:red" }, { "en" => { "source" => "flowchart LR\n  style A fill:red" } }, locale: "de")
  end

  # The drawing's `from` is the digest of what this cast stores, and
  # the editor's script hashes the same normalised text.
  test "a source cast by mermaid and Drawing.digest of it agree with a drawing whose from was hashed from the same cast text" do
    typed = "\r\nflowchart LR\r\n  A --> B\r\n\r\n"
    stored = fields("source" => typed).source
    drawing = Diagrams::Drawing.new({ "svg" => "<svg/>", "from" => Diagrams::Drawing.digest("flowchart LR\n  A --> B") })

    assert drawing.current?(stored)
    assert_equal Diagrams::Drawing.digest(stored), Diagrams::Drawing.digest("flowchart LR\n  A --> B")
    assert_not drawing.current?(typed), "the text as sent is not what was hashed"
  end

  test "a mermaid field names its drawing, a diagram_drawing field translated as it is, and the registration refuses anything else" do
    saved = BlockTypes.all.dup
    register = lambda do |&block|
      BlockTypes.register("test_diagram_pair") { |t| block.call(t); TestTypes.declare(t) }
    ensure
      BlockTypes.reset!
      saved.each { |definition| BlockTypes.registry_put(definition) }
    end

    assert_raises(ArgumentError, "no drawing:") { ContentModel::BlockTypeDefinition.new("x").field(:source, :mermaid) }
    error = assert_raises(ArgumentError) { register.call { |t| t.field :source, :mermaid, drawing: :drawing } }
    assert_includes error.message, "drawing"
    assert_raises(ArgumentError) do
      register.call { |t| t.field :source, :mermaid, drawing: :drawing; t.field :drawing, :string }
    end
    assert_raises(ArgumentError) do
      register.call { |t| t.field :source, :mermaid, translated: true, drawing: :drawing; t.field :drawing, :diagram_drawing }
    end
    definition = register.call { |t| t.field :source, :mermaid, drawing: :drawing; t.field :drawing, :diagram_drawing }
    assert_equal :drawing, definition.fields.first.options[:drawing]
    assert_raises(ArgumentError, "drawing: is a mermaid field's") { ContentModel::BlockTypeDefinition.new("x").field(:title, :string, drawing: :drawing) }
  end

  test "a mermaid field may name its description, a string or text field translated as it is, and the registration refuses anything else" do
    saved = BlockTypes.all.dup
    register = lambda do |&block|
      BlockTypes.register("test_diagram_described") { |t| block.call(t); TestTypes.declare(t) }
    ensure
      BlockTypes.reset!
      saved.each { |definition| BlockTypes.registry_put(definition) }
    end

    definition = register.call do |t|
      t.field :source, :mermaid, drawing: :drawing, description: :words
      t.field :drawing, :diagram_drawing
      t.field :words, :text
    end
    assert_equal :words, definition.fields.first.options[:description]
    assert_raises(ArgumentError, "a missing field") { register.call { |t| t.field :source, :mermaid, drawing: :drawing, description: :words; t.field :drawing, :diagram_drawing } }
    assert_raises(ArgumentError, "not a text field") do
      register.call { |t| t.field :source, :mermaid, drawing: :drawing, description: :words; t.field :drawing, :diagram_drawing; t.field :words, :integer }
    end
    assert_raises(ArgumentError, "translated otherwise") do
      register.call { |t| t.field :source, :mermaid, translated: true, drawing: :drawing, description: :words; t.field :drawing, :diagram_drawing, translated: true; t.field :words, :text }
    end
    assert_raises(ArgumentError, "description: is a mermaid field's") { ContentModel::BlockTypeDefinition.new("x").field(:title, :string, description: :x) }
    assert_raises(ArgumentError, "description: is a mermaid field's") { ContentModel::BlockTypeDefinition.new("x").field(:body, :text, description: :x) }
    assert_equal :description, BlockTypes.fetch(:diagram).fields.first.options[:description]
  end

  test "only a built-in block type may declare a mermaid source or a drawing: a content type, a field group and an outside block type may not" do
    [ ContentModel::ContentTypeDefinition, ContentModel::FieldGroupDefinition ].each do |kind|
      %i[mermaid diagram_drawing].each do |type|
        options = type == :mermaid ? { drawing: :drawing } : {}
        error = assert_raises(ArgumentError, "#{kind} #{type}") { kind.new("sample").field :part, type, **options }
        assert_match(/may not declare a #{type} field: a drawing is made by the Diagram block's card/, error.message)
      end
    end

    saved = BlockTypes.all.dup
    error = assert_raises(ArgumentError) do
      BlockTypes.register("gallery/chart") do |t|
        t.field :source, :mermaid, drawing: :drawing
        t.field :drawing, :diagram_drawing
        TestTypes.declare(t)
      end
    end
    assert_match(/a block type from outside may not declare a :mermaid field/, error.message)
  ensure
    BlockTypes.reset!
    saved&.each { |definition| BlockTypes.registry_put(definition) }
  end
end
