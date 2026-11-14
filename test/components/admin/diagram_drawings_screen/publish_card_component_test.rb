require "test_helper"

# `Admin::DiagramDrawingsScreen::PublishCardComponent`: "Live pages with new
# drawings", drawn hidden with an empty list and the row the script clones
# for each live page a run saved a drawing on.
class Admin::DiagramDrawingsScreen::PublishCardComponentTest < ViewComponent::TestCase
  TARGET = "data-admin--diagram--draw-all-target".freeze

  setup { render_inline Admin::DiagramDrawingsScreen::PublishCardComponent.new }

  test "the card is hidden, its head says what it lists, and its list is empty" do
    card = page.find("[#{TARGET}='publish'][hidden]", visible: :hidden)
    assert card.has_css?("h2", text: "Live pages with new drawings", visible: :hidden)
    assert card.has_text?(:all, "Their drawings are saved, not on the site yet.")
    assert card.has_css?("ul[#{TARGET}='publishList']", visible: :hidden, text: "")
  end

  test "the row's template holds the title, the path and Review and publish…" do
    assert page.has_css?("template[#{TARGET}='publishRow']", visible: :all)
    row = Nokogiri::HTML5.fragment(rendered_content[%r{<template[^>]*publishRow[^>]*>(.*?)</template>}m, 1])

    assert row.at_css("li [data-part='title']")
    assert row.at_css("li [data-part='path']")
    link = row.at_css("li a[data-part='review']")
    assert_equal "Review and publish…", link.text.strip
    assert_equal "_top", link["data-turbo-frame"]
  end
end
