require "application_system_test_case"

# Move to… in a real browser (the card StudioMediaFolders, D6, D7, D9 and
# D5's keyboard way): the dialog opens from the image panel's Folder fact, the
# place menu or the selection's bar, loads its list for what moves, keeps Move
# here disabled until a place is chosen, sends through the write queue, and
# closes on success; a refusal stands on top of the list with the focus on
# it. Selection mode (`select=1`) ticks tiles by press, Space, Shift+click and
# Select all, and is left by Escape, Done or a visit.
class Admin::MediaFolderMovesSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @clients = Media::Folder.create!(name: "Clients")
    @client_a = Media::Folder.create!(name: "Client A", parent: @clients)
    @events = Media::Folder.create!(name: "Events")
    @logo = create_media_asset.tap { |asset| asset.update!(title: "logo") }
    @logo.update_columns(folder_id: @client_a.id) # version: none (a test's own rows)
  end

  def dialog = "dialog#media-move-dialog[open]"

  def move_here = find("#{dialog} footer button", text: "Move here")

  def focused_id = page.evaluate_script("document.activeElement?.id")

  def focused_text = page.evaluate_script("document.activeElement?.textContent?.trim()")

  def fact = "#media-panel-folder-#{@logo.id}"

  def open_from_panel
    visit_screen "/cs-studio/media?folder=#{@client_a.id}&selected=#{@logo.id}"
    within(fact) { press "Move to…" }
    assert_selector "#{dialog} [role=radiogroup]"
  end

  test "the panel's Move to moves the image and keeps the panel open on it" do
    open_from_panel
    within(dialog) do
      assert_selector "h2", text: "Move “logo”"
      assert_selector "label", text: /Client A\s+Current/
      choose "Events"
    end
    move_here.click

    assert_no_selector dialog
    assert_selector "#toasts", text: "Moved “logo” to “Events”."
    assert_eventually(message: "the image moved") { @logo.reload.folder_id == @events.id }
    assert_no_selector "#media-asset-#{@logo.id}"
    assert_selector "#media-panel"
    assert_selector "#{fact} a", text: "Events"
  end

  test "a folder moves with the place menu's Move to from the keyboard alone" do
    visit_screen "/cs-studio/media?folder=#{@client_a.id}"

    # The keyboard starts on the menu's button; from there no pointer.
    page.execute_script("document.querySelector(\"[data-media-place-heading] button[aria-label='Folder actions']\").focus()")
    page.send_keys(:enter)
    assert_eventually(message: "the menu opens on its first item") { focused_text == "New folder inside…" }
    page.send_keys(:down, :down)
    assert_equal "Move to…", focused_text
    page.send_keys(:enter)

    assert_selector "#{dialog} h2", text: "Move “Client A”"
    assert_eventually(message: "the list arrives and the focus is on Find a folder") { focused_id == "media-move-find" }
    within(dialog) do
      assert_selector "label", text: /Clients\s+Current/
      assert_selector "label", text: /Client A\s+this folder/
    end

    # Tab enters the radiogroup on its first place that can be chosen; Down
    # skips the two that cannot and chooses Events.
    page.send_keys(:tab)
    assert_equal "media-move-choice-top", focused_id
    page.send_keys(:down)
    assert_equal "media-move-choice-#{@events.id}", focused_id
    assert move_here.matches_css?(":not([disabled])")
    page.send_keys(:tab, :tab)
    assert_equal "Move here", focused_text
    watch_frame_load
    page.send_keys(:enter)
    await_frame_load

    assert_equal @events.id, @client_a.reload.parent_id
    assert_no_selector dialog
    assert_selector "#toasts", text: "Moved “Client A” to “Events”."
    assert_selector "[data-media-place-heading] nav", text: /All media\s+›\s+Events\s+›\s+Client A/
    assert_current_path "/cs-studio/media?folder=#{@client_a.id}"
  end

  test "Move here is disabled until a choice" do
    open_from_panel
    assert move_here.disabled?

    within(dialog) do
      fill_in "Find a folder", with: "eve"
      assert_selector "[role=radiogroup] label", text: "Events"
      assert_no_selector "[role=radiogroup] label", text: "Clients"
      choose "Events"
    end
    assert_not move_here.disabled?

    within(dialog) { find("footer button", text: "Cancel").click }
    assert_no_selector dialog
    within(fact) { press "Move to…" }
    assert_selector "#{dialog} [role=radiogroup] label", text: "Clients"
    assert move_here.disabled?, "a new opening chooses nothing"
    assert_no_selector "#{dialog} input[type=radio]:checked"
  end

  test "a refused move shows the danger notice with the focus on it and moves nothing" do
    open_from_panel
    within(dialog) { choose "Events" }
    # Another tab deletes the folder chosen.
    @events.destroy!
    move_here.click

    within(dialog) do
      assert_selector "#media-move-refusal[role=alert]", text: "That folder is gone."
      assert_no_selector "label", text: "Events"
    end
    assert_eventually(message: "the focus is on the notice") { focused_id == "media-move-refusal" }
    assert move_here.disabled?
    assert_equal @client_a.id, @logo.reload.folder_id
    assert_selector "#media-asset-#{@logo.id}"
  end

  def tile(asset) = "#media-asset-#{asset.id} > button"

  def bar = "[data-media-selection-bar]"

  def pressed?(asset) = find(tile(asset))["aria-pressed"] == "true"

  # Images in Client A beside the logo, newest first as the grid draws them.
  def images_in_client_a(count)
    Array.new(count) { |index| create_media_asset.tap { |asset| asset.update_columns(title: "photo-#{index}", folder_id: @client_a.id) } } # version: none (a test's own rows)
      .reverse
  end

  def enter_selection(path = "/cs-studio/media?folder=#{@client_a.id}")
    visit_screen path
    click_frame_link { within("[data-media-place-heading]") { press "Select" } }
    assert_selector bar
  end

  test "three images selected move with the dialog from the keyboard alone" do
    first, second, third = images_in_client_a(3)
    enter_selection

    # The keyboard starts on the first tile; from there no pointer.
    page.execute_script("document.querySelector(#{tile(first).to_json}).focus()")
    page.send_keys(:space, :tab, :space, :tab, :space)
    assert_selector "#{bar} strong", text: "3 selected"
    assert_selector "[role=status]", text: "3 selected", visible: :all
    assert [ first, second, third ].all? { |asset| pressed?(asset) }
    assert_not pressed?(@logo)
    assert find("#{tile(first)} [data-media-tick] input", visible: :all).checked?

    # Back past the tiles to the bar's Done, then Move to….
    page.send_keys([ :shift, :tab ], [ :shift, :tab ], [ :shift, :tab ])
    assert_equal "Done", focused_text
    page.send_keys([ :shift, :tab ])
    assert_equal "Move to…", focused_text
    page.send_keys(:enter)

    assert_selector "#{dialog} h2", text: "Move 3 images"
    assert_eventually(message: "the list arrives and the focus is on Find a folder") { focused_id == "media-move-find" }
    within(dialog) { assert_selector "label", text: /Client A\s+Current/ }
    page.send_keys(:tab)
    assert_equal "media-move-choice-none", focused_id
    page.send_keys(:down, :down)
    assert_equal "media-move-choice-#{@events.id}", focused_id
    page.send_keys(:tab, :tab)
    assert_equal "Move here", focused_text
    page.send_keys(:enter)

    assert_no_selector dialog
    assert_selector "#toasts", text: "Moved 3 images to “Events”."
    assert_eventually(message: "the three moved") { [ first, second, third ].all? { |asset| asset.reload.folder_id == @events.id } }
    assert_equal @client_a.id, @logo.reload.folder_id
    [ first, second, third ].each { |asset| assert_no_selector "#media-asset-#{asset.id}" }
    assert_selector "#{bar} strong", text: "0 selected"
    assert find("#{bar} button", text: "Move to…").disabled?
  end

  test "Shift+click ticks a range in grid order" do
    images = images_in_client_a(4)
    enter_selection
    order = page.all("ul.admin-media-grid > li > button").map { |button| button["data-asset-id"].to_i }
    assert_equal [ *images.map(&:id), @logo.id ], order

    find(tile(images[0])).click
    find(tile(images[3])).click(:shift)
    assert(images.all? { |asset| pressed?(asset) })
    assert_not pressed?(@logo)
    assert_selector "#{bar} strong", text: "4 selected"

    # A press without Shift toggles one, and is the next range's anchor.
    find(tile(images[1])).click
    assert_not pressed?(images[1])
    find(tile(@logo)).click(:shift)
    assert(images[1..].all? { |asset| pressed?(asset) } && pressed?(@logo))
    assert_selector "#{bar} strong", text: "5 selected"
  end

  test "Select all selects what the page draws, then reads All 34 selected" do
    images_in_client_a(33)
    enter_selection
    assert_selector "#{bar} button", text: "Select all 34"

    within(bar) { press "Select all 34" }
    assert_selector "#{bar} button[aria-disabled=true]", text: "All 34 selected"
    assert_selector "#{bar} strong", text: "34 selected"
    assert_selector "ul.admin-media-grid > li > button[aria-pressed=true]", count: 34

    within(bar) { press "Clear" }
    assert_selector "#{bar} strong", text: "0 selected"
    assert_selector "#{bar} button:not([aria-disabled])", text: "Select all 34"
    assert_no_selector "ul.admin-media-grid > li > button[aria-pressed=true]"
  end

  test "Escape, Done and a visit leave selection mode" do
    enter_selection
    find(tile(@logo)).click
    assert pressed?(@logo)

    watch_frame_load
    page.send_keys(:escape)
    await_frame_load
    assert_no_selector bar
    assert_selector "#media-asset-#{@logo.id} > a"
    assert_current_path "/cs-studio/media?folder=#{@client_a.id}"

    click_frame_link { within("[data-media-place-heading]") { press "Select" } }
    assert_current_path "/cs-studio/media?folder=#{@client_a.id}&select=1"
    click_frame_link { within(bar) { press "Done" } }
    assert_no_selector bar
    assert_current_path "/cs-studio/media?folder=#{@client_a.id}"

    click_frame_link { within("[data-media-place-heading]") { press "Select" } }
    find(tile(@logo)).click
    click_frame_link { within("##{Admin::MediaLibrary::FolderTreeComponent::ID}") { click_link "Clients" } }
    assert_no_selector bar
    assert_current_path "/cs-studio/media?folder=#{@clients.id}"
    click_frame_link { within("##{Admin::MediaLibrary::FolderTreeComponent::ID}") { click_link "Client A" } }
    assert_selector "#media-asset-#{@logo.id} > a"
  end

  test "one image selected is named by its title, or counted when it has none" do
    enter_selection
    find(tile(@logo)).click
    within(bar) { press "Move to…" }
    assert_selector "#{dialog} h2", text: "Move “logo”"
    within(dialog) { find("footer button", text: "Cancel").click }
    assert_no_selector dialog

    @logo.update_columns(title: "") # version: none (a test's own rows)
    enter_selection
    find(tile(@logo)).click
    within(bar) { press "Move to…" }
    assert_selector "#{dialog} h2", text: "Move 1 image"
  end

  test "a choice Find a folder hides is chosen no more" do
    open_from_panel
    within(dialog) do
      choose "Events"
      fill_in "Find a folder", with: "cli"
      assert_no_selector "[role=radiogroup] label", text: "Events"
    end
    assert move_here.disabled?
    assert_no_selector "#{dialog} input[type=radio]:checked", visible: :all

    within(dialog) { fill_in "Find a folder", with: "" }
    assert_selector "#{dialog} [role=radiogroup] label", text: "Events"
    assert move_here.disabled?, "showing it again does not choose it again"
  end

  test "a selection holding images that are not the viewer's is refused in the dialog with the focus on it" do
    mine = create_media_asset.tap { |asset| asset.update_columns(title: "mine", folder_id: @client_a.id, created_by_id: users(:author).id) } # version: none (a test's own rows)
    theirs = create_media_asset.tap { |asset| asset.update_columns(title: "theirs", folder_id: @client_a.id) } # version: none (a test's own rows)

    using_session(:author) do
      sign_in_via_form(users(:author))
      enter_selection
      within(bar) { press "Select all 3" }
      within(bar) { press "Move to…" }
      assert_selector "#{dialog} h2", text: "Move 3 images"
      within(dialog) { choose "Events" }
      move_here.click

      within(dialog) do
        assert_selector "#media-move-refusal[role=alert]", text: "2 of these images are not yours to move. Nothing was moved."
      end
      assert_eventually(message: "the focus is on the notice") { focused_id == "media-move-refusal" }
      assert move_here.disabled?
    end
    assert_equal [ @client_a.id ] * 3, [ mine, theirs, @logo ].map { |asset| asset.reload.folder_id }
  end

  test "the toast says where the images went" do
    open_from_panel
    within(dialog) { choose "Not in a folder" }
    move_here.click

    assert_selector "#toasts", text: "Moved “logo” to “Not in a folder”."
    assert_nil @logo.reload.folder_id
    assert_selector "#{fact} span", text: "Not in a folder"
  end
end
