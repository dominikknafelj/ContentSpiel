require "test_helper"

# The bar of the Media screen's selection mode (the card StudioMediaFolders, D6).
class Admin::MediaLibrary::SelectionBarComponentTest < ViewComponent::TestCase
  def bar(count_on_page: 34, done_url: "/cs-studio/media?folder=7")
    render_inline Admin::MediaLibrary::SelectionBarComponent.new(count_on_page: count_on_page, done_url: done_url)
  end

  test "the bar counts, selects all drawn, clears, moves and is done" do
    bar

    page.find("[data-media-selection-bar].admin-media-selection-bar.bg-popover.shadow-3.rounded-card").then do |bar|
      bar.assert_selector "strong[data-admin--media--selection-target=count]", text: "0 selected"
      bar.assert_selector "button[data-action='admin--media--selection#selectAll'][data-admin--media--selection-target=selectAll]", text: "Select all 34"
      bar.assert_selector "button[data-action='admin--media--selection#clear']", text: "Clear"

      move = bar.find("button[data-admin--media--selection-target=move]")
      assert_equal "Move to…", move.text.strip
      assert move.disabled?, "nothing is ticked yet"
      bar.assert_selector "button[data-admin--media--selection-target=move] svg"
      assert_equal Admin::MediaLibrary::MoveDialogComponent::ID, move["data-admin--ui--dialog-id-param"]
      assert_equal "admin--ui--dialog#open", move["data-action"]
      assert_equal "", move["data-admin--media--move-asset-ids-param"]

      done = bar.find("a[data-admin--media--selection-target=done]", text: "Done")
      assert_equal "/cs-studio/media?folder=7", done[:href]
      assert_equal "content", done["data-turbo-frame"]
    end

    # The order of the card: the count, Select all, Clear, the room kept,
    # Move to…, Done.
    words = page.all("[data-media-selection-bar] > *").map { |node| node.text.strip }
    assert_equal [ "0 selected", "Select all 34", "Clear", "", "Move to…", "Done" ], words
    messages = JSON.parse(page.find("[data-media-selection-bar]")["data-messages"])
    assert_equal "%{count} selected", messages["components.media_library.selection.count"]
    assert_equal "All %{count} selected", messages["components.media_library.selection.all_selected"]
  end

  test "the count is announced outside the bar" do
    bar

    status = page.find("[role=status][aria-live=polite][data-admin--media--selection-target=status]", visible: :all)
    assert_equal "", status.text(:all)
    assert_no_selector "[data-media-selection-bar] [role=status]"
  end
end
