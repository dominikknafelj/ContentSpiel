require "application_system_test_case"

# The Folders column of the Media screen in a real browser (the card
# StudioMediaFolders, D1): the shell's tree column, subject `media`, outside
# `#content`. A row opens its place in the content frame and the column's
# selection follows the place shown (`admin--media--folders`); a fold is kept
# in its own cookie, `cs_media_open`, and never in the Pages tree's; the find
# narrows the folders; the rows' links keep the grid's search.
class Admin::MediaFoldersSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @clients = Media::Folder.create!(name: "Clients")
    @client_a = Media::Folder.create!(name: "Client A", parent: @clients)
    @events = Media::Folder.create!(name: "Events")
    @logo = create_media_asset.tap { |asset| asset.update!(title: "logo") }
    @portrait = create_media_asset.tap { |asset| asset.update!(title: "portrait") }
    @logo.update_columns(folder_id: @client_a.id) # version: none (a test's own rows)
  end

  def row(place) = "#tree-column [data-tree-row][data-media-place='#{place}']"

  def selected_places = page.all("#tree-column .admin-tree-row--selected", visible: :all).map { |each| each["data-media-place"] }

  def cookie(name) = page.evaluate_script("document.cookie").to_s[/(?:^|; )#{name}=([^;]*)/, 1]

  def children_hidden?(folder) = page.evaluate_script("document.getElementById('media-folder-children-#{folder.id}').hidden")

  def open_place(name) = click_frame_link { within("#tree-column") { click_link(name) } }

  def href_of(place) = find("#{row(place)} a[data-tree-focus]", visible: :all)[:href]

  test "a row opens its place in the content frame and the column follows the selection" do
    visit_screen "/cs-studio/media"
    assert_equal [ "all" ], selected_places
    assert children_hidden?(@clients), "Clients is folded by default"

    open_place("Not in a folder")
    assert_selector "#content #media-library[data-media-place=none]"
    assert_selector "#media-asset-#{@portrait.id}"
    assert_no_selector "#media-asset-#{@logo.id}"
    assert_equal [ "none" ], selected_places
    assert_selector "#{row('none')} a[aria-current=page]"
    assert_no_selector "#{row('all')} a[aria-current]"
    assert_current_path "/cs-studio/media?folder=none"

    # A place reached another way (a full load of a folder's address) is
    # selected too, with the path to it open and its mark the open folder.
    visit_screen "/cs-studio/media?folder=#{@client_a.id}"
    assert_not children_hidden?(@clients), "the path to the place shown is open"
    assert_equal [ @client_a.id.to_s ], selected_places
    assert_selector "#{row(@client_a.id)} [data-tree-glyph=folder_open]"
    assert_no_selector "#{row(@client_a.id)} [data-tree-glyph=folder]"
    assert_selector "#{row(@clients.id)} [data-tree-glyph=folder]"
    assert_no_selector "#{row(@clients.id)} [data-tree-glyph=folder_open]"

    open_place("Events")
    assert_selector "#content #media-library[data-media-place='#{@events.id}']"
    assert_equal [ @events.id.to_s ], selected_places
    assert_selector "#{row(@events.id)} [data-tree-glyph=folder_open]"
    assert_selector "#{row(@client_a.id)} [data-tree-glyph=folder]"
    assert_no_selector "#{row(@client_a.id)} a[aria-current]"
  end

  test "a fold is kept in cs_media_open across a visit and leaves the Pages tree's folds alone" do
    page_fold = "-#{root_page.id}"
    visit_screen "/cs-studio/media"
    page.execute_script("document.cookie = #{"cs_tree_open=#{page_fold}; path=/#{ContentSpiel::ADMIN_PATH}".to_json}")

    find("#{row(@clients.id)} button[aria-label='Unfold Clients']").click
    assert_not children_hidden?(@clients)
    assert_selector row(@client_a.id)
    assert_equal @clients.id.to_s, cookie("cs_media_open")
    assert_equal page_fold, cookie("cs_tree_open")

    visit_screen "/cs-studio/media"
    assert_not children_hidden?(@clients), "the server drew the open from cs_media_open"
    assert_selector "#{row(@clients.id)} button[aria-expanded=true]"

    find("#{row(@clients.id)} button[aria-label='Fold Clients']").click
    assert children_hidden?(@clients)
    assert_nil cookie("cs_media_open"), "a fold back to the default stores nothing"
    assert_equal page_fold, cookie("cs_tree_open")

    visit_screen "/cs-studio/pages"
    assert_equal page_fold, cookie("cs_tree_open")
  end

  test "Find a folder narrows the rows and says how many match" do
    visit_screen "/cs-studio/media"

    find_field("Find a folder").send_keys("client")
    assert_selector "#{row(@clients.id)} mark", text: "Client"
    assert_selector "#{row(@client_a.id)} mark", text: "Client"
    assert_no_selector row(@events.id)
    assert_selector "#tree-column [role=search] [role=status]", text: "2 folders match"
    # All media and Not in a folder are places, not folders: the find leaves them.
    assert_selector row("all")
    assert_selector row("none")

    find("#tree-column [role=search] button[aria-label=Clear]").click
    find_field("Find a folder").send_keys("zzz")
    assert_selector "#tree-column [role=search] [role=status]", text: "No folders match"

    find_field("Find a folder").send_keys(:escape)
    assert_selector row(@events.id)
    assert children_hidden?(@clients), "the find's opens are given back"
    assert_nil cookie("cs_media_open")
  end

  test "a search typed in the grid is kept by the rows' links" do
    visit_screen "/cs-studio/media"

    watch_frame_load
    fill_in "Search images", with: "logo"
    await_frame_load
    assert_selector "#content #media-library[data-media-query*='logo']"
    assert_eventually(message: -> { "the row's link is #{href_of(@events.id)}" }) { href_of(@events.id).include?("q=logo") }
    assert_includes href_of("all"), "q=logo"
    assert_not_includes href_of("all"), "page="

    open_place("Not in a folder")
    assert_selector "#content #media-library[data-media-place=none][data-media-query*='logo']"
    assert_equal "logo", find_field("Search images").value
    assert_current_path "/cs-studio/media?folder=none&q=logo"
    assert_no_selector "#media-asset-#{@portrait.id}"
  end

  # A create's answer replaces the column's part, which names the new folder
  # as the place to go to (`data-media-go`): the content frame goes there and
  # the address advances with it, so Back returns to the place before.
  test "a create's answer opens the new folder and advances the address" do
    visit_screen "/cs-studio/media?folder=none"

    watch_frame_load
    page.execute_script(<<~JS)
      (async () => {
        const answer = await fetch("/cs-studio/media_folders", {
          method: "POST",
          headers: { "Accept": "text/vnd.turbo-stream.html", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content ?? "" },
          body: new URLSearchParams({ "media_folder[name]": "Trips", "place": "none" })
        })
        window.Turbo.renderStreamMessage(await answer.text())
      })()
    JS
    await_frame_load
    trips = Media::Folder.find_by!(name: "Trips")

    assert_current_path "/cs-studio/media?folder=#{trips.id}"
    assert_selector "#content #media-library[data-media-place='#{trips.id}']"
    assert_equal [ trips.id.to_s ], selected_places
    assert_no_selector "#media-folder-tree-part[data-media-go]", visible: :all

    page.go_back
    assert_current_path "/cs-studio/media?folder=none"
  end

  # The folder dialogs (D2, D3, D4 and D10's menu): every write is sent
  # through the write queue, and the answer's column sends the screen to the
  # place it names.

  def dialog = "dialog#media-folder-dialog[open]"

  def focused_id = page.evaluate_script("document.activeElement?.id")

  def toasts_text = find("#toasts", visible: :all).text(:all).squish

  def open_folder_menu(item)
    find("[data-media-place-heading] button[aria-label='Folder actions']").click
    find("[data-media-place-heading] [role=menu] button", text: item).click
  end

  test "a folder is created from a row's +, becomes the place, and gets no toast" do
    visit_screen "/cs-studio/media"

    find("#{row(@clients.id)} button[aria-label='New folder in Clients']", visible: :all).click
    within(dialog) do
      assert_selector "h2", text: "New folder"
      assert_selector "#media-folder-where", text: "Inside Clients"
      assert_button "Create folder"
    end
    assert_equal "media-folder-name", focused_id

    fill_in "Name", with: "Trips"
    watch_frame_load
    press "Create folder"
    await_frame_load

    trips = Media::Folder.find_by!(name: "Trips")
    assert_equal @clients.id, trips.parent_id
    assert_current_path "/cs-studio/media?folder=#{trips.id}"
    assert_selector "#content h1", text: "Trips"
    assert_no_selector dialog
    assert_equal [ trips.id.to_s ], selected_places
    assert_equal "", toasts_text
  end

  test "a taken name keeps the dialog open with the error under the field and the focus in it" do
    visit_screen "/cs-studio/media"

    find("#tree-column button", text: "+ New folder").click
    within(dialog) { assert_selector "#media-folder-where", text: "At the top of the library" }
    fill_in "Name", with: "events"
    press "Create folder"

    within(dialog) do
      assert_selector "#media-folder-name + #media-folder-name-errors", text: "A folder named “events” is already here."
      assert_field "Name", with: "events"
      assert_selector "#media-folder-where", text: "At the top of the library"
    end
    assert_eventually(message: "the focus is back in the field") { focused_id == "media-folder-name" }
    assert_equal 1, Media::Folder.where(parent_id: nil).pluck(:name).count { |name| name.casecmp?("events") }

    fill_in "Name", with: "Events 2"
    watch_frame_load
    press "Create folder"
    await_frame_load
    assert_selector "#content h1", text: "Events 2"
    assert_nil Media::Folder.find_by!(name: "Events 2").parent_id
  end

  test "a folder is renamed from the place menu" do
    visit_screen "/cs-studio/media?folder=#{@client_a.id}"

    open_folder_menu "Rename…"
    within(dialog) do
      assert_selector "h2", text: "Rename folder"
      assert_field "Name", with: "Client A"
      assert_selector "#media-folder-where", text: "Inside Clients"
    end
    assert_eventually(message: "the name is selected, to be typed over") do
      page.evaluate_script("(f => document.activeElement === f && f.selectionStart === 0 && f.selectionEnd === f.value.length)(document.getElementById('media-folder-name'))")
    end

    fill_in "Name", with: "Client B"
    watch_frame_load
    press "Rename"
    await_frame_load

    assert_equal "Client B", @client_a.reload.name
    assert_equal @clients.id, @client_a.parent_id
    assert_current_path "/cs-studio/media?folder=#{@client_a.id}"
    assert_selector "#content h1", text: "Client B"
    assert_selector "#{row(@client_a.id)} a", text: "Client B"
    assert_equal "", toasts_text
  end

  test "deleting a folder says what moves where, then opens the parent with Folder deleted" do
    visit_screen "/cs-studio/media?folder=#{@client_a.id}"

    open_folder_menu "Delete folder…"
    within("dialog#media-folder-delete-dialog[open]") do
      assert_selector "h2", text: "Delete “Client A”?"
      assert_text "Its 1 image move to “Clients”. Nothing else is deleted."
      assert_text "This can't be undone."
    end

    watch_frame_load
    press "Delete folder"
    await_frame_load

    assert_nil Media::Folder.find_by(id: @client_a.id)
    assert_equal @clients.id, @logo.reload.folder_id
    assert_current_path "/cs-studio/media?folder=#{@clients.id}"
    assert_selector "#content h1", text: "Clients"
    assert_selector "#toasts", text: "Folder deleted"
    assert_no_selector row(@client_a.id), visible: :all
    assert_equal [ @clients.id.to_s ], selected_places
  end

  test "a folder is created and deleted from the keyboard alone" do
    visit_screen "/cs-studio/media"

    # The keyboard starts on the column's button; from there no pointer.
    page.execute_script("Array.from(document.querySelectorAll('#tree-column button')).find((b) => b.textContent.includes('New folder')).focus()")
    page.send_keys(:enter)
    assert_selector dialog
    assert_eventually(message: "the dialog starts on its field") { focused_id == "media-folder-name" }
    watch_frame_load
    page.send_keys("Trips", :enter)
    await_frame_load
    trips = Media::Folder.find_by!(name: "Trips")
    assert_current_path "/cs-studio/media?folder=#{trips.id}"

    page.execute_script("document.querySelector(\"[data-media-place-heading] button[aria-label='Folder actions']\").focus()")
    page.send_keys(:enter)
    assert_eventually(message: "the menu opens on its first item") { page.evaluate_script("document.activeElement?.textContent") == "New folder inside…" }
    page.send_keys(:up)
    assert_equal "Delete folder…", page.evaluate_script("document.activeElement?.textContent")
    page.send_keys(:enter)
    assert_selector "dialog#media-folder-delete-dialog[open]", text: "It is empty."
    assert_equal "Cancel", page.evaluate_script("document.activeElement?.textContent")
    page.send_keys(:tab)
    assert_equal "Delete folder", page.evaluate_script("document.activeElement?.textContent")
    watch_frame_load
    page.send_keys(:enter)
    await_frame_load

    assert_nil Media::Folder.find_by(id: trips.id)
    assert_current_path "/cs-studio/media"
    assert_selector "#toasts", text: "Folder deleted"
  end
end
