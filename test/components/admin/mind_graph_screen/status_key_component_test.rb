require "test_helper"

# The Mind graph's status key (pages in the mind graph, spec §6; design
# answer H6): a dialog named "Status key" with the five looks, in the words
# the card's chip uses.
class Admin::MindGraphScreen::StatusKeyComponentTest < ViewComponent::TestCase
  def key = render_inline(Admin::MindGraphScreen::StatusKeyComponent.new)

  test "the status key is a dialog named Status key that holds the five looks in the chip's words and no control" do
    key
    dialog = "dialog#mind-graph-status-key[aria-labelledby='mind-graph-status-key-title']"

    assert_selector "#{dialog} h2#mind-graph-status-key-title", text: "Status key", visible: :all
    assert_equal [ "Live", "Draft", "Scheduled", "Live, unpublished changes", "Live, change scheduled" ], page.all("#{dialog} li[data-legend-state]", visible: :all).map { |item| item.text(:all).squish }
    assert_equal %w[live draft scheduled live_with_changes live_change_scheduled], page.all("#{dialog} li[data-legend-state]", visible: :all).map { |item| item["data-legend-state"] }
    assert_no_selector "#{dialog} .admin-dialog__body input, #{dialog} .admin-dialog__body button, #{dialog} .admin-dialog__body a", visible: :all
    assert_no_match(/\d/, page.find(dialog, visible: :all).text(:all), "no date: the day of a scheduled change stands only on a card's chip")
  end

  # The names are `Publishing::State`'s: a sixth state fails here until the
  # key has a row for it.
  test "the key has a row for every state a record can be in, and no other" do
    assert_equal Publishing::State::STATES.sort, Admin::MindGraphScreen::StatusKeyComponent::STATES.sort
  end

  test "each look's swatch is a canvas for the graph's own renderer, named after its state, and the key draws none itself" do
    key

    names = page.all("dialog li[data-legend-state] canvas[data-swatch]", visible: :all).map { |canvas| canvas["data-swatch"] }
    assert_equal %w[state-live state-draft state-scheduled state-live-with-changes state-live-change-scheduled], names
    assert_selector "dialog ul[data-controller='admin--mind-graph--swatches'] canvas[data-swatch][data-width='18'][data-height='18'][aria-hidden=true]", count: 5, visible: :all
    assert_no_selector "dialog svg", visible: :all
  end
end
