require "test_helper"
require_relative "../../../support/answers_test_helper"

class Admin::Answers::SlotStreamsTest < ActionView::TestCase
  include AnswersTestHelper

  # Built like a slot component; replaces the element its `stream_target` names.
  class TargetProbe < ViewComponent::Base
    def initialize(record:, viewer:, data: nil, label: "probe", **)
      @record = record
      @viewer = viewer
      @label = label
    end

    def stream_target = "probe-#{@label}"

    def call = tag.i("#{@label}:#{@record.id}:#{@viewer&.id}", id: stream_target)
  end

  class QuietProbe < TargetProbe
    def render? = false
  end

  test "each registered entry that renders replaces its own target with itself, in registration order" do
    page = create_page(title: "About")
    second = Admin::Slots::Entry.new(component: TargetProbe, options: { label: "second" })
    Admin::Slots.with("editor.block.removed" => [ TargetProbe, QuietProbe, second ]) do
      nodes = Nokogiri::HTML5.fragment(Admin::Answers::SlotStreams.for("editor.block.removed", page, view: view, viewer: users(:one)).join).element_children

      assert_equal [ [ "replace", "probe-probe" ], [ "replace", "probe-second" ] ], nodes.map { |node| [ node["action"], node["target"] ] }
      assert_includes nodes.last.at("template").inner_html, "second:#{page.id}:#{users(:one).id}"
    end
  end

  test "nothing registered is no stream" do
    Admin::Slots.with("editor.block.removed" => []) do
      assert_empty Admin::Answers::SlotStreams.for("editor.block.removed", create_page(title: "About"), view: view, viewer: users(:one))
    end
  end

  # The registry as it is: the page's notes counts, read again for the viewer.
  test "the registered stream after a block's delete is the page's notes counts, fresh" do
    page = create_page(title: "About")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)
    as(users(:two)) { [ page, block ].each { |subject| Notes::Start.call(subject, body: "A note") } }

    node = Nokogiri::HTML5.fragment(Admin::Answers::SlotStreams.for("editor.block.removed", page, view: view, viewer: users(:one)).join).element_children.sole

    assert_equal [ "replace", "notes-counts" ], [ node["action"], node["target"] ]
    counts = Nokogiri::HTML5.fragment(node.at("template").inner_html).at("span#notes-counts")
    assert_equal "counts", counts["data-admin--notes--drawer-target"]
    assert_equal 2, JSON.parse(counts["data-counts"])["total"]
  end
end
