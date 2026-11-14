require "test_helper"

# The `:mermaid` field type (Diagram block spec, §1 and §5): a Mermaid source,
# kept as typed like `:code`, held to `Diagrams::Source`'s line rules, each
# refusal its own sentence, in every language the object holds.
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

  test "mermaid refuses each rule with its own sentence, naming the line" do
    assert_equal [ "Line 2: colours come from the site's theme, so classDef isn't used here." ], sentences("source" => "flowchart LR\n  classDef a fill:red")
    assert_equal [ "Line 3: a diagram can't hold links or actions, so click isn't used here." ], sentences("source" => "flowchart LR\n  A --> B\n  click A x")
    assert_equal [ "Line 1: settings in --- front matter aren't used here, so the drawing follows the site." ], sentences("source" => "---\ntitle: x\n---\nflowchart LR")
    assert_equal [ "Line 2: maths can't be drawn here, so $$ isn't used." ], sentences("source" => "flowchart LR\n  A[$$x$$]")
    assert_equal [ "mindmap diagrams aren't supported yet. Use one of: flowchart, sequenceDiagram, classDiagram, stateDiagram, erDiagram, gantt, pie." ],
      sentences("source" => "mindmap\n  root")
    assert_equal [ "The first line names the diagram's type, like flowchart or sequenceDiagram." ], sentences("source" => "A --> B")
    assert_empty sentences("source" => "classDiagram\n  class Animal")
  end

  # Ruby's I18n reads `%%` as an escaped `%` when it interpolates, so the
  # directive's own marker arrives as the word, never as text of the sentence.
  test "the directive's sentence prints its marker as typed" do
    assert_equal [ "Line 2: settings in %%{ } aren't used here, so the drawing follows the site." ],
      sentences("source" => "flowchart LR\n  %%{init: {}}%%")
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

  test "a refused source in another language is refused too, once per sentence" do
    translations = { "en" => { "source" => "flowchart LR\n  A --> B" } }
    german = sentences({ "source" => "flowchart LR\n  style A fill:red" }, translations, locale: "de")

    assert_equal [ "Line 2: colours come from the site's theme, so style isn't used here." ], german

    both = { "en" => { "source" => "flowchart LR\n  style A fill:red" }, "de" => { "source" => "flowchart LR\n  style A fill:red" } }
    assert_equal 1, ContentModel::FieldSet.for(define).new({}, both, locale: "en").tap(&:valid?).errors[:source].size
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
    saved = FieldGroups.all.dup
    register = lambda do |&block|
      FieldGroups.register("test/diagram_pair", &block)
    ensure
      FieldGroups.reset!
      saved.each { |definition| FieldGroups.registry_put(definition) }
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
end
