require "test_helper"
require_relative "../../../support/answers_test_helper"
require_relative "../../../support/rail_tab_probe"

class Admin::Answers::RailTabStreamsTest < ActionView::TestCase
  include AnswersTestHelper

  test "a save's answer replaces each registered tab by id and no panel" do
    page = create_page(title: "About")
    Admin::Slots.with("editor.rail.tabs" => [ RailTabProbe, RailTabProbe::Quiet ]) do
      streams = Admin::Answers::RailTabStreams.for(page, view: view, viewer: users(:one))
      nodes = Nokogiri::HTML5.fragment(streams.join).element_children

      assert_equal [ [ "replace", "editor-grid-tab-probe" ] ], nodes.map { |node| [ node["action"], node["target"] ] }
      assert_includes nodes.sole.inner_html, "Probe"
      assert_no_match(/tabpanel/, nodes.sole.inner_html)
    end
  end

  test "nothing registered is no stream, and the rail's id is the caller's" do
    page = create_page(title: "About")
    assert_empty Admin::Answers::RailTabStreams.for(page, view: view, viewer: nil)
    Admin::Slots.with("editor.rail.tabs" => [ RailTabProbe ]) do
      target = Nokogiri::HTML5.fragment(Admin::Answers::RailTabStreams.for(page, view: view, viewer: nil, rail_id: "r").join).element_children.sole["target"]
      assert_equal "r-tab-probe", target
    end
  end
end
