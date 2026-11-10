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

  # The header's notice slot (`#editor-notice`) speaks through no region of
  # its own, so the line the live script puts there when the record is gone
  # keeps the warn notice's alert: nothing else would announce it.
  test "the missing line is the warn notice, an alert of its own, with the way back" do
    record = create_page(title: "Region")

    render_inline Admin::EditorScreen::LiveRegionComponent.new(record: record, locale: "en")

    inner = rendered_content[%r{<template data-admin--editing--live-target="missing">(.*?)</template>}m, 1]
    line = Nokogiri::HTML.fragment(inner).at_css("[data-editing-missing]")
    assert_equal "alert", line["role"]
    %w[rounded-card border-warn bg-warn-tint text-warn-ink text-small].each { |utility| assert_includes line["class"].split, utility }
    assert_not_includes line["class"].split, "rounded-cs"
    assert_equal "/cs-studio/pages", line.at_css("a[data-turbo-frame=_top]")["href"]
  end
end
