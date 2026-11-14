require "test_helper"

# `Admin::DiagramDrawingsScreen::PageGroupComponent`: a page's head on the
# Draw diagrams list (its title, its path in mono and its list state; not a
# link) over its rows.
class Admin::DiagramDrawingsScreen::PageGroupComponentTest < ViewComponent::TestCase
  include ContentHelper

  EN = BlockTypes::Diagram::SAMPLE_SOURCES.fetch("en")

  setup { Current.actor = users(:one) }
  teardown { Current.reset }

  def diagram(page)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "diagram" },
      translations: { "en" => { settings: { "source" => EN } } }, actor: users(:one))
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def group(page)
    rows = [ Diagrams::ToDraw::Row.new(block: diagram(page), page:, locale: "en", state: :not_drawn, source: EN) ]
    render_inline Admin::DiagramDrawingsScreen::PageGroupComponent.new(page:, rows:, language_column: true)
  end

  test "a draft's head names it, its path and Draft, and is no link" do
    record = create_page(title: "Release notes", published: false)
    group(record)

    head = page_head
    assert_selector "h2", text: "Release notes"
    assert_selector "[data-part='path']", text: PublicSite::Urls.new.path_for(record, "en")
    assert head.has_text?("Draft")
    assert head.has_no_css?("a")
    assert_selector "ul > li[data-draw-row]", count: 1
    assert_selector "[data-page-id='#{record.id}']"
  end

  test "a plain live page's head has no state chip" do
    record = create_page(title: "Pages and addresses", published: true)
    group(record)

    assert page_head.has_no_css?("[data-status]")
    assert_no_text "Draft"
  end

  def page_head = page.find("[data-part='head']")
end
