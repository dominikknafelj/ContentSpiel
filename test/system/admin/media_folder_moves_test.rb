require "application_system_test_case"

# Move to… in a real browser (the card StudioMediaFolders, D7, D9 and D5's
# keyboard way): the dialog opens from the image panel's Folder fact or the
# place menu, loads its list for what moves, keeps Move here disabled until a
# place is chosen, sends through the write queue, and closes on success; a
# refusal stands on top of the list with the focus on it.
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

  test "the toast says where the images went" do
    open_from_panel
    within(dialog) { choose "Not in a folder" }
    move_here.click

    assert_selector "#toasts", text: "Moved “logo” to “Not in a folder”."
    assert_nil @logo.reload.folder_id
    assert_selector "#{fact} span", text: "Not in a folder"
  end
end
