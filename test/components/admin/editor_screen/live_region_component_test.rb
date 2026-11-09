require "test_helper"

class Admin::EditorScreen::LiveRegionComponentTest < ViewComponent::TestCase
  include ContentHelper

  test "a page's region holds the taken-over mark once, as a template for the hold script, with no avatar" do
    record = create_page(title: "Region")

    render_inline Admin::EditorScreen::LiveRegionComponent.new(record: record, locale: "en")

    assert_selector "template[data-admin--editing--hold-target=takenOver]", count: 1, visible: :all
    inner = rendered_content[%r{<template data-admin--editing--hold-target="takenOver">(.*?)</template>}m, 1]
    template = Nokogiri::HTML.fragment(inner)
    assert_equal "Taken over by you · just now", template.at_css("[data-editing-mark]").text.squish
    assert_nil template.at_css("[aria-hidden]")
  end
end
