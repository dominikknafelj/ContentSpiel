require "test_helper"

# The `:diagram_drawing` field type (Diagram block spec, §1 and §3): the SVG the
# renderer frame drew, cleaned by `Diagrams::Drawing` on the way in, with the
# digest of the source it was drawn from. A drawing that does not clean is
# refused, never dropped.
class ContentModel::DiagramDrawingFieldTest < ActiveSupport::TestCase
  include TestTypes

  RAW = Rails.root.join("test/fixtures/diagrams/flowchart.svg").read
  FROM = Diagrams::Drawing.digest("flowchart LR\n  A --> B")
  SCRIPT = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><script>alert(1)</script></svg>'

  def definition
    ContentModel::BlockTypeDefinition.new("sample").tap do |t|
      t.field :source, :mermaid, translated: true, drawing: :drawing
      t.field :drawing, :diagram_drawing, translated: true
    end
  end

  def fields(values, translations = {}, options = {}) = definition.field_set.new({}, translations, locale: options.fetch(:locale, "en")).assign(values)

  test "diagram_drawing cleans on cast and a drawing that fails is :invalid_drawing" do
    clean = Diagrams::Drawing.clean(RAW).svg

    from_json = fields("drawing" => JSON.generate(svg: RAW, from: FROM))
    assert from_json.valid?, from_json.errors.full_messages.inspect
    assert_equal({ "svg" => clean, "from" => FROM }, from_json.drawing)
    assert_equal({ "svg" => clean, "from" => FROM }, fields("drawing" => { "svg" => RAW, "from" => FROM }).drawing, "a Hash, as jsonb reads back")
    other = Diagrams::Drawing.digest("another source")
    assert_equal other, fields("drawing" => { "svg" => RAW, "from" => other }).drawing["from"], "a digest is kept as given: the cast cannot see the source"

    not_digests = [ "hand-made", "#{FROM}0", FROM[0..62], "#{FROM}\n", "x" * 100_000, 42 ]
    hand_made = not_digests.map { |from| JSON.generate(svg: RAW, from: from) }
    [ JSON.generate(svg: SCRIPT, from: FROM), "not json", JSON.generate([ 1 ]), JSON.generate(svg: RAW), { "from" => FROM }, *hand_made ].each do |sent|
      refused = fields("drawing" => sent)

      assert_not refused.valid?, sent.inspect
      assert_equal [ "This drawing can't be shown on the site." ], refused.errors[:drawing], sent.inspect
      assert refused.errors.added?(:drawing, :invalid_drawing)
    end
  end

  test "a refused drawing in another language is refused, and a stored one in a language this save did not send is not this save's" do
    german = fields({ "drawing" => JSON.generate(svg: SCRIPT, from: FROM) }, { "en" => { "drawing" => { "svg" => RAW, "from" => FROM } } }, locale: "de")
    assert_equal [ "This drawing can't be shown on the site." ], german.tap(&:valid?).errors[:drawing]

    stored = definition.field_set.new({}, { "en" => { "drawing" => { "svg" => SCRIPT, "from" => FROM } } }, locale: "en")
    assert stored.valid?, "only what a save was handed is refused"
    assert_nil stored.drawing["svg"], "and it reads back as no drawing"
  end

  test "it is not translatable and is audited as a digest" do
    type = ContentModel::FieldTypes.fetch(:diagram_drawing)

    assert_not type.translatable
    assert_equal :digest, type.audit
  end

  test "a block whose save sends a drawing that does not clean is refused, and its stored drawing stays" do
    saved = BlockTypes.all.dup
    BlockTypes.register("test_diagram") do |t|
      TestTypes.declare(t)
      t.label "Diagram"
      t.field :source, :mermaid, translated: true, drawing: :drawing
      t.field :drawing, :diagram_drawing, translated: true
      t.component TestQuoteComponent
    end
    Current.actor = users(:one)
    block = ContentBlock.create!(owner: Page.create!(title: "Home", slug: ""), block_type: "test_diagram", position: 0,
      translated_settings: { "en" => { "source" => "flowchart LR\n  A --> B", "drawing" => { "svg" => Diagrams::Drawing.clean(RAW).svg, "from" => FROM } } })

    result = ContentBlocks::Save.call(block, attributes: { settings: { "drawing" => JSON.generate(svg: SCRIPT, from: FROM) } })

    assert_not result.ok?
    assert_includes result.errors.to_sentence, "This drawing can't be shown on the site."
    assert_equal FROM, block.reload.translated_settings.dig("en", "drawing", "from")
  ensure
    BlockTypes.reset!
    saved.each { |definition| BlockTypes.registry_put(definition) }
  end
end
