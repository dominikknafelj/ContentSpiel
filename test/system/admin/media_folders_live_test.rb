require "application_system_test_case"

# Other tabs follow the library's folders (media-folders spec §11, the card
# StudioMediaFolders, D13): a tab with the Media screen or the open picker
# hears that the library changed elsewhere (`Media::LibraryChannel`), fetches
# the Folders column's part again and replaces it silently, folds and focus
# kept, and never replaces the grid: when the place shown changed, one notice
# above the grid offers "Show changes". The acting tab hears its own signal
# and does nothing. A change made here through a service (no tab) is a change
# from another tab to every browser.
class Admin::MediaFoldersLiveSystemTest < ApplicationSystemTestCase
  NOTICE = "[data-media-live-notice]".freeze
  WORDS = "Images here changed since you opened this view.".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @clients = Media::Folder.create!(name: "Clients")
    @client_a = Media::Folder.create!(name: "Client A", parent: @clients)
    @events = Media::Folder.create!(name: "Events")
    @logo = create_media_asset.tap { |asset| asset.update!(title: "logo") }
    @portrait = create_media_asset.tap { |asset| asset.update!(title: "portrait") }
    @logo.update_columns(folder_id: @client_a.id) # version: none (a test's own rows)
  end

  teardown do
    page.execute_script("try { localStorage.removeItem('cs.media.picker.place') } catch {}")
  end

  def row(place) = "#tree-column [data-tree-row][data-media-place='#{place}']"

  def focused_id = page.evaluate_script("document.activeElement?.id")

  def open_screen(path)
    sign_in_via_form(users(:one))
    visit_screen path
    await_notes_live
    # A reload would take this away: the column must be replaced in place.
    page.execute_script("window.__notReloaded = true")
  end

  def not_reloaded? = page.evaluate_script("window.__notReloaded === true")

  def elsewhere(&) = as(users(:one), &)

  # Counts this tab's fetches of the column's part (`GET /media/folders`)
  # in `window.__partFetches`; every other request goes through untouched.
  def count_part_fetches
    page.execute_script(<<~JS)
      window.__partFetches = 0
      const real = window.fetch
      window.fetch = (input, init) => {
        if (String(input).includes("/media/folders")) window.__partFetches += 1
        return real(input, init)
      }
    JS
  end

  test "a folder made in one tab appears in the other without a reload, its folds and focus kept" do
    open_screen "/cs-studio/media?folder=#{@client_a.id}"
    assert_not page.evaluate_script("document.getElementById('media-folder-children-#{@clients.id}').hidden"), "the path is open"
    page.execute_script("document.getElementById('media-place-row-#{@events.id}-link').focus()")

    using_session(:colleague) do
      sign_in_via_form(users(:one))
      visit_screen "/cs-studio/media"
      find("#tree-column button", text: "+ New folder").click
      fill_in "Name", with: "Trips"
      press "Create folder"
      assert_selector "#content h1", text: "Trips"
    end

    trips = Media::Folder.find_by!(name: "Trips")
    assert_selector row(trips.id), text: "Trips", wait: 8
    assert not_reloaded?
    assert_not page.evaluate_script("document.getElementById('media-folder-children-#{@clients.id}').hidden"), "Clients stays open"
    assert_equal "media-place-row-#{@events.id}-link", focused_id
    assert_selector "#{row(@client_a.id)}.admin-tree-row--selected"
    # Nothing changed in Client A: no notice.
    await_frames
    assert_no_selector NOTICE
  end

  test "images moved out of the shown folder by another tab leave the grid alone and offer to show the changes" do
    open_screen "/cs-studio/media?folder=#{@client_a.id}"
    assert_selector "#media-asset-#{@logo.id}"

    elsewhere { assert Media::MoveImages.call(asset_ids: [ @logo.id ], folder: @events).ok? }

    assert_selector NOTICE, text: WORDS, wait: 8
    assert_selector "#{NOTICE}[role=status]"
    assert_selector "#{NOTICE} button", text: "Show changes"
    assert_selector "#media-asset-#{@logo.id}", text: "logo"
    assert_equal "1", find("#{row(@events.id)} [data-media-place-count]").text
    assert_equal "", find("#{row(@client_a.id)} [data-media-place-count]", visible: :all).text(:all).strip
    assert not_reloaded?
  end

  test "Show changes reloads the place and removes the notice" do
    open_screen "/cs-studio/media?folder=#{@client_a.id}"
    elsewhere { assert Media::MoveImages.call(asset_ids: [ @logo.id ], folder: @events).ok? }
    assert_selector NOTICE, wait: 8

    find("#{NOTICE} button", text: "Show changes").click
    assert_no_selector "#media-asset-#{@logo.id}"
    assert_no_selector NOTICE
    assert_current_path "/cs-studio/media?folder=#{@client_a.id}"

    # The folder shown deleted elsewhere: Show changes opens All media.
    page.execute_script("window.__notReloaded = true")
    elsewhere { assert Media::DeleteFolder.call(@client_a).ok? }
    assert_selector NOTICE, wait: 8
    assert not_reloaded?
    find("#{NOTICE} button", text: "Show changes").click
    assert_selector "#content #media-library[data-media-place=all]"
    assert_no_selector NOTICE
    assert_current_path "/cs-studio/media"
  end

  test "the notice is never stacked and never in the acting tab" do
    open_screen "/cs-studio/media?folder=#{@client_a.id}&selected=#{@logo.id}"

    using_session(:colleague) do
      sign_in_via_form(users(:one))
      visit_screen "/cs-studio/media?folder=#{@client_a.id}"
      await_notes_live
    end

    # This tab moves the image out of the place it shows, counting its
    # fetches of the column's part from here on.
    count_part_fetches
    within("#media-panel-folder-#{@logo.id}") { press "Move to…" }
    within("dialog#media-move-dialog[open]") { choose "Events" }
    find("dialog#media-move-dialog[open] footer button", text: "Move here").click
    assert_no_selector "#media-asset-#{@logo.id}"

    using_session(:colleague) { assert_selector NOTICE, count: 1, wait: 8 }
    # The colleague heard the signal; this tab heard the same one, its own
    # echo (`origin`), and fetches nothing for it.
    sleep 1 # sleep: the echo reaches this tab about when the colleague's arrived; a fetch for it would start at once
    assert_equal 0, page.evaluate_script("window.__partFetches")
    assert_no_selector NOTICE

    using_session(:colleague) do
      # A second change of the place: still one notice.
      elsewhere { assert Media::MoveImages.call(asset_ids: [ @portrait.id ], folder: @client_a).ok? }
      assert_eventually(message: "the second change reaches the column") { find("#{row(@client_a.id)} [data-media-place-count]", visible: :all).text(:all).strip == "1" }
      assert_selector NOTICE, count: 1
    end

    # The colleague's tab heard both; this one heard its own move, then the
    # portrait coming in, which is a change of its place.
    assert_selector NOTICE, count: 1, wait: 8

    # A change elsewhere after this tab's own move: the digest its answer drew
    # is the one it holds, so a later unrelated change says nothing.
    find("#{NOTICE} button", text: "Show changes").click
    assert_selector "#media-asset-#{@portrait.id}"
    assert_no_selector NOTICE
    page.execute_script("window.__notReloaded = true")
    find("#media-asset-#{@portrait.id} a").click
    assert_selector "#media-panel-folder-#{@portrait.id}"
    within("#media-panel-folder-#{@portrait.id}") { press "Move to…" }
    within("dialog#media-move-dialog[open]") { choose "Clients" }
    find("dialog#media-move-dialog[open] footer button", text: "Move here").click
    assert_no_selector "#media-asset-#{@portrait.id}"
    elsewhere { assert Media::SaveFolder.call(attributes: { name: "Trips" }).ok? }
    trips = Media::Folder.find_by!(name: "Trips")
    assert_selector row(trips.id), wait: 8
    await_frames
    assert_no_selector NOTICE
  end

  test "the picker, open, shows the same notice above its grid" do
    sign_in_via_form(users(:one))
    landing = create_page(title: "Landing")
    assert Pages::Save.call(landing, attributes: { template: "landing" }).ok?
    visit_editor(landing)
    within("#page-hero-image-section") { click_on "Choose image" }
    within("dialog#media-picker[open]") do
      click_link "Not in a folder"
      assert_selector "#media-picker-place[data-media-place=none]", visible: :all
      assert_selector "#media-picker-asset-#{@portrait.id}"
    end
    await_notes_live

    elsewhere { assert Media::MoveImages.call(asset_ids: [ @portrait.id ], folder: @events).ok? }

    within("dialog#media-picker[open]") do
      assert_selector NOTICE, text: WORDS, wait: 8
      assert_selector "#media-picker-asset-#{@portrait.id}"
      assert_equal "1", find("#media-picker-place-row-#{@events.id} [data-media-place-count]").text
      find("#{NOTICE} button", text: "Show changes").click
      assert_no_selector "#media-picker-asset-#{@portrait.id}"
      assert_no_selector NOTICE
    end

    # Closed, the picker listens to nothing.
    find("dialog#media-picker[open] button", text: "Cancel").click
    assert_no_selector "dialog#media-picker[open]"
    assert_not page.evaluate_script("document.getElementById('media-picker').hasAttribute('data-live-part')")
  end
end
