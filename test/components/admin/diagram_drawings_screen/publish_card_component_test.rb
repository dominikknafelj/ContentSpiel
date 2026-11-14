require "test_helper"

# `Admin::DiagramDrawingsScreen::PublishCardComponent`: "Pages with new
# drawings", drawn hidden with an empty list, the row the script clones for
# each live or scheduled page a run saved a drawing on, and the status chip
# it puts in that row.
class Admin::DiagramDrawingsScreen::PublishCardComponentTest < ViewComponent::TestCase
  TARGET = "data-admin--diagram--draw-all-target".freeze

  setup { render_inline Admin::DiagramDrawingsScreen::PublishCardComponent.new }

  test "the card is hidden, its head says what it lists, and its list is empty" do
    card = page.find("[#{TARGET}='publish'][hidden]", visible: :hidden)
    assert card.has_css?("h2", exact_text: "Pages with new drawings", visible: :hidden)
    assert card.has_text?(:all, "Saved, not published: the site doesn't show these drawings, and a scheduled page goes live without them.")
    assert card.has_css?("ul[#{TARGET}='publishList']", visible: :hidden, text: "")
  end

  test "the row's template holds the title, the path and Review and publish…" do
    assert page.has_css?("template[#{TARGET}='publishRow']", visible: :all)
    row = Nokogiri::HTML5.fragment(rendered_content[%r{<template[^>]*publishRow[^>]*>(.*?)</template>}m, 1])

    assert row.at_css("li [data-part='title']")
    assert row.at_css("li [data-part='path']")
    assert row.at_css("li [data-part='status']"), "the slot of the page's status chip"
    link = row.at_css("li a[data-part='review']")
    assert_equal "Review and publish…", link.text.strip
    assert_equal "_top", link["data-turbo-frame"]
  end

  test "a status chip per state a listed page can be in, drawn by StatusChipComponent" do
    card = rendered_content
    %w[live scheduled].each do |status|
      chip = Nokogiri::HTML5.fragment(card[%r{<template[^>]*publishChip[^>]*data-status="#{status}"[^>]*>(.*?)</template>}m, 1].to_s)
      expected = Nokogiri::HTML5.fragment(render_inline(Admin::Ui::StatusChipComponent.new(status: status)).to_html)
      assert_equal expected.text.strip, chip.text.strip, status
      assert chip.at_css(".admin-status-chip"), status
    end
  end
end
