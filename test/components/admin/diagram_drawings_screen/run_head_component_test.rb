require "test_helper"

# `Admin::DiagramDrawingsScreen::RunHeadComponent`: the screen's heading, its
# lead and count, "Draw all" (the area's one primary, one button whose label
# the script changes to Stop, so the focus never moves), and the parts the
# run writes, drawn empty or hidden: the progress line, the polite live
# region, the summary's slot and the reason a disabled "Draw all" gives.
class Admin::DiagramDrawingsScreen::RunHeadComponentTest < ViewComponent::TestCase
  TARGET = "data-admin--diagram--draw-all-target".freeze

  def head(count) = render_inline(Admin::DiagramDrawingsScreen::RunHeadComponent.new(count:))

  test "the heading, the lead and the count" do
    head(4)

    assert_selector "h1", text: "Draw diagrams"
    assert_text "Diagrams written outside CS Studio, by a loader, a script or MCP, have no drawing until a browser draws them. " \
                "Each drawing is saved as a change; nothing is published."
    assert_selector "[#{TARGET}='count']", text: "4 diagrams to draw."

    head(1)
    assert_text "1 diagram to draw."
  end

  test "Draw all is the one primary, a button the script turns into Stop" do
    head(2)

    button = page.find("button[#{TARGET}='start']", text: "Draw all")
    assert_includes button[:class], "bg-accent"
    assert_equal "click->admin--diagram--draw-all#toggle", button["data-action"]
    assert_selector "button", count: 1
  end

  test "the run's parts are drawn empty or hidden" do
    head(2)

    assert_selector "[#{TARGET}='progress'][hidden]", visible: :hidden
    assert_selector "[#{TARGET}='progress'] [aria-hidden='true'] [data-part='bar']", visible: :hidden
    assert_selector "[#{TARGET}='status'][aria-live='polite']", visible: :all, text: ""
    assert_selector "[#{TARGET}='summary']", visible: :all, text: ""
  end

  test "a disabled Draw all says why in words, hidden until the script finds it cannot draw" do
    head(2)

    reason = page.find("[#{TARGET}='insecure'][hidden]", visible: :hidden)
    assert_equal "Drawing needs HTTPS.", reason.text(:all).strip
    assert reason[:id].present?, "the script names the reason by its id when it shows it"
    assert_nil page.find("button[#{TARGET}='start']")["aria-describedby"], "a hidden reason would still be read"
  end

  test "with nothing to draw there is no count and no button" do
    head(0)

    assert_selector "h1", text: "Draw diagrams"
    assert_no_text "to draw."
    assert_no_selector "button"
  end
end
