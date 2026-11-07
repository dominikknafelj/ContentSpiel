require "test_helper"
require_relative "../../../support/answers_test_helper"
require_relative "../../../support/rail_tab_probe"

class Admin::Answers::RailTabStreamsTest < ActionView::TestCase
  include AnswersTestHelper

  # Updated, not replaced: the tab's `<button>` stays, so a focused tab
  # keeps the focus as the answer lands.
  test "a save's answer updates each registered tab's contents by id, and no panel" do
    page = create_page(title: "About")
    Admin::Slots.with("editor.rail.tabs" => [ RailTabProbe, RailTabProbe::Quiet ]) do
      streams = Admin::Answers::RailTabStreams.for(page, view: view, viewer: users(:one))
      nodes = Nokogiri::HTML5.fragment(streams.join).element_children

      assert_equal [ [ "update", "editor-grid-tab-probe" ] ], nodes.map { |node| [ node["action"], node["target"] ] }
      assert_includes nodes.sole.inner_html, "Probe"
      assert_no_match(/tabpanel|<button/, nodes.sole.inner_html)
    end
  end

  test "nothing registered is no stream, and the rail's id is the caller's" do
    page = create_page(title: "About")
    Admin::Slots.with("editor.rail.tabs" => []) { assert_empty Admin::Answers::RailTabStreams.for(page, view: view, viewer: nil) }
    Admin::Slots.with("editor.rail.tabs" => [ RailTabProbe ]) do
      target = Nokogiri::HTML5.fragment(Admin::Answers::RailTabStreams.for(page, view: view, viewer: nil, rail_id: "r").join).element_children.sole["target"]
      assert_equal "r-tab-probe", target
    end
  end

  # The registry as it is: the Notes tab. A save's stream hands no `reads:`,
  # so the tab reads no counts (a save is frequent, and its answer must not
  # cost the notes' two statements) and draws its number hidden, as a target
  # of `admin--notes--drawer`, which fills it from the counts the page holds.
  test "the Notes tab's stream reads no counts and hands its number to the script" do
    page = create_page(title: "About")
    as(users(:two)) { Notes::Start.call(page, body: "A note") }

    streams = nil
    statements = capture_sql { streams = Admin::Answers::RailTabStreams.for(page, view: view, viewer: users(:one)) }

    assert_empty statements.grep(/note_threads|note_deliveries/), "the stream read the notes' counts"
    node = Nokogiri::HTML5.fragment(streams.join).element_children.sole
    assert_equal [ "update", "editor-grid-tab-notes" ], [ node["action"], node["target"] ]
    tab = Nokogiri::HTML5.fragment(node.at("template").inner_html)
    assert_nil tab.at("button"), "the tab's button stays in the page"
    count = tab.at("span.text-count")
    assert_equal "total", count["data-admin--notes--drawer-target"]
    assert count.key?("hidden"), "the number is the script's to fill"
    assert_equal "Notes", tab.children.first.text
  end
end
