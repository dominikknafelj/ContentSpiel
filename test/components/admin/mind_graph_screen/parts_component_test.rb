require "test_helper"

# The parts the graph's scripts clone (`mind_graph/parts.js`): the shared
# components' own markup in one `<template>`, so no chip and no button is
# drawn by hand in JavaScript.
class Admin::MindGraphScreen::PartsComponentTest < ViewComponent::TestCase
  ARGUMENTS = {
    "status-live" => -> { Admin::Ui::StatusChipComponent.new(status: "live") },
    "status-draft" => -> { Admin::Ui::StatusChipComponent.new(status: "draft") },
    "status-scheduled" => -> { Admin::Ui::StatusChipComponent.new(status: "scheduled") },
    "unpublished" => -> { Admin::Ui::UnpublishedChipComponent.new },
    "icon-page" => -> { Admin::Ui::IconChipComponent.new(icon: :pages, family: :structure, size: :small) },
    "icon-post" => -> { Admin::Ui::IconChipComponent.new(icon: :posts, family: :lists, size: :small) },
    "icon-tag" => -> { Admin::Ui::IconChipComponent.new(icon: :tags, family: :lists, size: :small) },
    "icon-type" => -> { Admin::Ui::IconChipComponent.new(icon: :clipboard_list, family: :lists, size: :small) },
    "close" => -> { Admin::Ui::ButtonComponent.new(label: "Close", icon: :x, variant: :tertiary, size: :small, data: { mind_graph_card_close: "" }) }
  }.freeze

  test "the parts are one template holding the three status chips, the unpublished chip, an icon chip per kind and Close as the shared icon button" do
    templates = parts_templates
    assert_equal 1, templates.size
    names = templates.first.css("> span[data-part]").map { |part| part["data-part"] }
    assert_equal %w[status-live status-draft status-scheduled unpublished icon-page icon-post icon-tag icon-type close], names
    assert_equal names, Admin::MindGraphScreen::PartsComponent::NAMES
    part = ->(name) { templates.first.css("> span[data-part='#{name}'] > *").tap { |found| assert_equal 1, found.size, "#{name} holds one element" }.first }
    assert_classes part.("status-live"), %w[admin-status-chip bg-live], status: "live"
    assert_classes part.("status-draft"), %w[admin-status-chip border-field-line], status: "draft"
    assert_classes part.("status-scheduled"), %w[admin-status-chip bg-scheduled], status: "scheduled"
    assert part.("unpublished").key?("data-unpublished-changes")
    assert_classes part.("icon-page"), %w[bg-ic-structure-bg size-5.5]
    %w[icon-post icon-tag icon-type].each { |name| assert_classes part.(name), %w[bg-ic-lists-bg size-5.5] }
    %w[icon-page icon-post icon-tag icon-type].each { |name| assert_equal "true", part.(name)["aria-hidden"], name }
    close = part.("close")
    assert_equal [ "button", "button", "Close", "" ], [ close.name, close["type"], close["aria-label"], close["data-mind-graph-card-close"] ]
  end

  test "a part is the shared component's own markup" do
    parts = parts_templates.first.css("> span[data-part]").to_h { |part| [ part["data-part"], part.inner_html.strip ] }

    ARGUMENTS.each do |name, component|
      assert_equal Nokogiri::HTML5.fragment(render_inline(component.call).to_html).to_html.strip, parts.fetch(name), "#{name} is not its component's markup"
    end
  end

  private

  # The template as a browser parses it: its content is the template's own
  # (the HTML4 parser Capybara reads with leaves a template empty).
  def parts_templates
    render_inline(Admin::MindGraphScreen::PartsComponent.new)
    Nokogiri::HTML5.fragment(rendered_content).css("template[data-mind-graph-parts]")
  end

  def assert_classes(element, classes, status: nil)
    assert_empty classes - element["class"].split, "#{element["class"]} lacks #{classes}"
    assert_equal status, element["data-status"] if status
  end
end
