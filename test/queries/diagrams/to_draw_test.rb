require "test_helper"
require_relative "../../support/diagram_fixtures"

# The Diagram blocks whose stored drawing is not of their current source, per
# language with a source of its own (draw-diagrams spec §3).
class Diagrams::ToDrawTest < ActiveSupport::TestCase
  EN = BlockTypes::Diagram::SAMPLE_SOURCES.fetch("en")
  DE = BlockTypes::Diagram::SAMPLE_SOURCES.fetch("de")

  setup do
    @svg = Diagrams::Drawing.clean(DiagramFixtures::DIR.join("flowchart.svg").read).svg
    @page = create_page(title: "Flows", published: false)
    with_locales(%w[en de es], default: "en")
  end

  def cast(source) = ContentModel::FieldTypes.fetch(:mermaid).cast.call(source)

  def drawing_of(source) = { "svg" => @svg, "from" => Diagrams::Drawing.digest(cast(source)) }

  # `languages`: locale => [source, drawing or nil].
  def diagram(page = @page, languages:, section: nil, position: nil)
    translations = languages.to_h do |locale, (source, drawing)|
      [ locale, { settings: { "source" => source, "drawing" => drawing }.compact } ]
    end
    attributes = { block_type: "diagram" }
    attributes.merge!(section_id: section.id, section_column: 1) if section
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: attributes, translations: translations, actor: users(:one))
    assert result.ok?, result.errors.to_sentence
    result.record.tap { |block| block.update_columns(position: position) if position }
  end

  def rows(actor = users(:one)) = Diagrams::ToDraw.new(actor: actor).rows

  test "a diagram with no drawing is not drawn" do
    block = diagram(languages: { "en" => [ EN, nil ] })

    row = rows.sole
    assert_equal [ block, @page, "en", :not_drawn, cast(EN) ], [ row.block, row.page, row.locale, row.state, row.source ]
  end

  test "a drawing of another source is kept" do
    diagram(languages: { "en" => [ EN, drawing_of(DE) ] })

    assert_equal [ :kept ], rows.map(&:state)
  end

  test "a drawing no site could show is not drawn, though it names the source" do
    block = diagram(languages: { "en" => [ EN, nil ] })
    stored = block.translated_settings.to_h
    stored["en"]["drawing"] = { "svg" => "", "from" => Diagrams::Drawing.digest(cast(EN)) }
    block.update_columns(translated_settings: stored)

    assert_equal [ :not_drawn ], rows.map(&:state)
  end

  test "a current drawing is not listed" do
    diagram(languages: { "en" => [ EN, drawing_of(EN) ] })

    assert_empty rows
    assert_equal 0, Diagrams::ToDraw.new(actor: users(:one)).count
  end

  test "each language with its own source is a row" do
    diagram(languages: { "en" => [ EN, drawing_of(EN) ], "de" => [ DE, nil ] })

    assert_equal %w[de], rows.map(&:locale)
  end

  test "a language that falls back is not listed" do
    diagram(languages: { "en" => [ EN, nil ] })

    assert_equal %w[en], rows.map(&:locale)
  end

  test "a language switched off is not listed" do
    diagram(languages: { "en" => [ EN, nil ], "de" => [ DE, nil ] })
    with_locales(%w[en es], default: "en")

    assert_equal %w[en], rows.map(&:locale)
  end

  test "a diagram in a section is listed" do
    section = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "section", settings: { "layout" => "two" } }, actor: users(:one)).record
    block = diagram(languages: { "en" => [ EN, nil ] }, section: section)

    assert_equal [ block ], rows.map(&:block)
  end

  test "a block of another type is not listed" do
    ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }, actor: users(:one))

    assert_empty rows
  end

  test "a trashed branch is not listed" do
    child = create_page(title: "Child", parent: @page, published: false)
    diagram(child, languages: { "en" => [ EN, nil ] })
    result = Trash::Move.call(@page, actor: users(:one))
    assert result.ok?, result.errors.to_sentence

    assert_empty rows
  end

  test "a page outside the scope is not listed" do
    other = create_page(title: "Other", published: false)
    inside = diagram(@page, languages: { "en" => [ EN, nil ] })
    diagram(other, languages: { "en" => [ EN, nil ] })
    group = access_control_groups(:branch_editors)
    %w[pages.read pages.edit].each { |key| group.grants.create!(permission: key, scope: { "page_ids" => [ @page.id ] }) }

    assert_equal [ inside ], rows(users(:editor_branch)).map(&:block)
  end

  test "a published page needs publish" do
    live = create_page(title: "Live", published: true)
    draft = diagram(@page, languages: { "en" => [ EN, nil ] })
    diagram(live, languages: { "en" => [ EN, nil ] })
    group = access_control_groups(:branch_editors)
    %w[pages.read pages.edit].each { |key| group.grants.create!(permission: key, scope: {}) }
    query = Diagrams::ToDraw.new(actor: users(:editor_branch))

    assert_equal [ draft ], query.rows.map(&:block)
    assert_equal 1, query.count

    group.grants.create!(permission: "pages.publish", scope: {})

    assert_equal 2, Diagrams::ToDraw.new(actor: users(:editor_branch)).count
  end

  test "rows follow the tree, then the position, then the languages" do
    second = create_page(title: "Second", published: false)
    first_child = create_page(title: "First child", parent: @page, published: false)
    second.update_columns(position: 5)
    @page.update_columns(position: 1)
    late = diagram(@page, languages: { "en" => [ EN, nil ] }, position: 9)
    early = diagram(@page, languages: { "de" => [ DE, nil ], "en" => [ EN, nil ] }, position: 2)
    below = diagram(first_child, languages: { "en" => [ EN, nil ] }, position: 0)
    last = diagram(second, languages: { "en" => [ EN, nil ] }, position: 0)

    assert_equal [ [ early, "en" ], [ early, "de" ], [ late, "en" ], [ below, "en" ], [ last, "en" ] ],
      rows.map { |row| [ row.block, row.locale ] }
    assert_equal [ [ @page, [ early, late ] ], [ first_child, [ below ] ], [ second, [ last ] ] ],
      Diagrams::ToDraw.new(actor: users(:one)).pages.map { |page, list| [ page, list.map(&:block).uniq ] }
  end
end
