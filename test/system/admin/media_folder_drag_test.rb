require "application_system_test_case"

# Dragging onto the Folders column in a real browser (the card
# StudioMediaFolders, D5 and D8; `admin--media--drag`): a tile, or the
# selection from a ticked tile, dropped on a folder row or Not in a folder,
# and a folder by its row's gutter handle dropped on a folder row or All
# media, each sent through the write queue; a folded row opens under a
# resting drag; a row that cannot take a folder shows no target and says
# why; a coarse pointer and a typed find get no drag.
#
# The pointer walks in steps that rest past SortableJS's 50 ms sampling
# (`drag_pointer`'s reason), with real mouse events: SortableJS's fallback
# drag is pointer-driven, so Cuprite's mouse is what a person's is.
class Admin::MediaFolderDragSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @clients = Media::Folder.create!(name: "Clients")
    @client_a = Media::Folder.create!(name: "Client A", parent: @clients)
    @events = Media::Folder.create!(name: "Events")
    @logo = create_media_asset.tap { |asset| asset.update!(title: "logo") }
    @poster = create_media_asset.tap { |asset| asset.update!(title: "poster") }
  end

  def tile(asset) = "#media-asset-#{asset.id}"

  def row(place) = "#media-place-row-#{place.respond_to?(:id) ? place.id : place}"

  def handle(folder) = "#{row(folder)} [data-media-drag-handle]"

  def status = "#media-library [role=status][data-admin--media--drag-target=status]"

  def target = "#media-folder-tree .admin-tree-row.admin-tree-drop-target"

  def center(selector)
    page.evaluate_script(<<~JS)
      (() => {
        const box = document.querySelector(#{selector.to_json}).getBoundingClientRect()
        return { x: box.left + box.width / 2, y: box.top + box.height / 2 }
      })()
    JS
  end

  # Presses on `from` and walks to the middle of `to` in six resting steps;
  # yields with the button held, then releases unless `release: false`.
  def drag(from, to, release: true)
    start = center(from)
    finish = center(to)
    mouse = page.driver.browser.mouse
    mouse.move(x: start["x"], y: start["y"])
    mouse.down
    6.times do |step|
      mouse.move(x: start["x"] + ((finish["x"] - start["x"]) * (step + 1) / 6.0), y: start["y"] + ((finish["y"] - start["y"]) * (step + 1) / 6.0))
      sleep 0.08 # sleep: SortableJS samples the pointer on a 50 ms timer of its own; the pointer rests one tick plus margin per step
    end
    yield mouse if block_given?
    mouse.up if release
    mouse
  end

  # Whether the tree's own Sortable (the top-level folders') is disabled,
  # asked of SortableJS itself (the module is cached, so this import is the
  # page's own instance).
  def folders_sortable_disabled?
    page.evaluate_async_script(<<~JS)
      const done = arguments[0]
      import("sortablejs").then((module) => done(module.default.get(document.getElementById("media-folder-tree")).option("disabled")))
    JS
  end

  def count_of(place) = find("#{row(place)} [data-media-place-count]", visible: :all).text

  test "a tile dragged onto a folder moves, and the counts and the grid follow" do
    visit_screen "/cs-studio/media?folder=none"
    assert_selector tile(@logo)

    drag(tile(@logo), row(@events)) do
      assert_selector "#{row(@events)}.admin-tree-drop-target"
      # The ghost follows the pointer: the tile's thumbnail and its title.
      assert_selector "body > .admin-media-drag-ghost img[data-media-drag-thumb]"
      assert_selector "body > .admin-media-drag-ghost [data-media-drag-label]", text: "logo"
      assert_no_selector "body > .admin-media-drag-ghost [data-media-drag-count]"
    end

    assert_eventually(message: "the image moved into Events") { @logo.reload.folder_id == @events.id }
    assert_no_selector tile(@logo)
    assert_selector tile(@poster)
    assert_equal "1", count_of(@events)
    assert_equal "1", count_of("none")
    assert_selector "#media-place-count", text: "1 image"
    assert_no_selector target
    assert_no_selector ".admin-media-drag-ghost"
  end

  test "a selection dragged from a selected tile moves every selected image" do
    third = create_media_asset.tap { |asset| asset.update!(title: "third") }
    visit_screen "/cs-studio/media?folder=none&select=1"
    find("#{tile(@logo)} > button").click
    find("#{tile(@poster)} > button").click
    assert_selector "[data-admin--media--selection-target=count]", text: "2 selected"

    # An unticked tile does not lift: nothing follows the pointer and no row
    # is a target.
    drag("#{tile(third)} > button", row(@events)) do
      assert_no_selector ".admin-media-drag-ghost"
      assert_no_selector target
    end
    assert_selector "[data-admin--media--selection-target=count]", text: "2 selected"

    drag("#{tile(@poster)} > button", row(@events)) do
      assert_selector "body > .admin-media-drag-ghost [data-media-drag-label]", text: "2 images"
      assert_selector "body > .admin-media-drag-ghost [data-media-drag-count]", text: "2"
      assert_selector "#{row(@events)}.admin-tree-drop-target"
    end

    assert_eventually(message: "both selected images moved") { [ @logo, @poster ].all? { |asset| asset.reload.folder_id == @events.id } }
    assert_nil third.reload.folder_id
    assert_no_selector tile(@logo)
    assert_no_selector tile(@poster)
    assert_equal "2", count_of(@events)
  end

  test "Escape mid-drag in selection mode cancels the drop and keeps the selection" do
    visit_screen "/cs-studio/media?folder=none&select=1"
    find("#{tile(@logo)} > button").click
    assert_selector "[data-admin--media--selection-target=count]", text: "1 selected"
    # Selection mode's Escape presses Done: counted, so a press is seen
    # before its visit could land.
    page.execute_script("window.donePresses = 0; document.querySelector('[data-admin--media--selection-target=done]').addEventListener('click', () => window.donePresses++)")

    drag("#{tile(@logo)} > button", row(@events)) do
      assert_selector "#{row(@events)}.admin-tree-drop-target"
      page.send_keys(:escape)
      assert_no_selector target
    end

    assert_no_selector ".admin-media-drag-fallback", visible: :all
    assert_no_selector ".admin-media-drag-ghost"
    assert_equal 0, page.evaluate_script("window.donePresses")
    assert_current_path(/select=1/)
    assert_selector "[data-admin--media--selection-target=count]", text: "1 selected"
    assert_selector "#{tile(@logo)} > button[aria-pressed=true]"
    sleep 0.3 # sleep: nothing is expected to arrive; a move sent by mistake would answer within this
    assert_nil @logo.reload.folder_id
  end

  test "a drop on Not in a folder takes the image out of every folder" do
    @logo.update_columns(folder_id: @events.id) # version: none (a test's own rows)
    visit_screen "/cs-studio/media?folder=#{@events.id}"

    # All media is no target for an image, nor the place shown, where it stands.
    drag(tile(@logo), row("all"), release: false) { assert_no_selector target }.up
    drag(tile(@logo), row(@events), release: false) { assert_no_selector target }.up
    assert_equal @events.id, @logo.reload.folder_id

    drag(tile(@logo), row("none")) { assert_selector "#{row('none')}.admin-tree-drop-target" }

    assert_eventually(message: "the image left its folder") { @logo.reload.folder_id.nil? }
    assert_no_selector tile(@logo)
    assert_equal "2", count_of("none")
  end

  test "a folded row opens after a hover" do
    visit_screen "/cs-studio/media?folder=none"
    assert_selector "#{row(@clients)} ~ ul[hidden]", visible: :all
    assert_no_selector row(@client_a)

    drag(tile(@logo), row(@clients)) do
      assert_selector "#{row(@clients)}.admin-tree-drop-target"
      # Opened after a rest, stored open as a person's open.
      assert_selector row(@client_a)
      assert_includes page.evaluate_script("document.cookie").to_s[/(?:^|; )cs_media_open=([^;]*)/, 1].to_s.split("."), @clients.id.to_s
      drag_on = center(row(@client_a))
      page.driver.browser.mouse.move(x: drag_on["x"], y: drag_on["y"])
      assert_selector "#{row(@client_a)}.admin-tree-drop-target"
    end

    assert_eventually(message: "the image moved into the folder the hover opened") { @logo.reload.folder_id == @client_a.id }
  end

  test "a folder dragged by its handle onto a row moves into it, and onto All media to the top" do
    visit_screen "/cs-studio/media"

    drag(handle(@events), row(@clients)) do
      assert_selector "body > li.admin-drag-fallback", visible: :all
      assert_selector "#{row(@clients)}.admin-tree-drop-target"
    end
    assert_eventually(message: "Events moved into Clients") { @events.reload.parent_id == @clients.id }
    # The column is drawn again with Events inside Clients, which the move
    # stored open, and the new tree's handles drag too.
    assert_selector "li[data-tree-node]:has(> #{row(@clients)}) #{row(@events)}"
    await_sortables

    drag(handle(@events), row("all")) { assert_selector "#{row('all')}.admin-tree-drop-target" }
    assert_eventually(message: "Events moved to the top") { @events.reload.parent_id.nil? }
    assert_selector "#media-folder-tree > li[data-tree-node] > #{row(@events)}"
  end

  test "a row that cannot take the folder shows no target and says why" do
    deep_1 = Media::Folder.create!(name: "Archive")
    deep_2 = Media::Folder.create!(name: "2019", parent: deep_1)
    deep_3 = Media::Folder.create!(name: "Q4", parent: deep_2)
    mover = Media::Folder.create!(name: "Press")
    inner = Media::Folder.create!(name: "Inner", parent: mover)
    Media::Folder.create!(name: "press", parent: @clients)
    # Every branch open, so each row can be reached.
    page.execute_script("document.cookie = 'cs_media_open=#{[ deep_1, deep_2, mover, @clients ].map(&:id).join('.')}; path=/cs-studio'")
    visit_screen "/cs-studio/media"
    assert_selector row(deep_3)
    assert_selector row(inner)

    drag(handle(mover), row(deep_3), release: false) do |mouse|
      refused = "#{row(deep_3)}[data-media-drop-refused]"
      assert_selector refused
      assert_selector "#{refused} [data-media-drop-reason]", text: "too deep"
      assert_no_selector target
      assert_selector status, text: "Can't move “Press” there: too deep.", visible: :all
      # Its title and mark in meta: the colour a mark has at rest.
      meta = page.evaluate_script("getComputedStyle(document.querySelector('#{row(@events)} .admin-tree-row__mark')).color")
      assert_equal meta, page.evaluate_script("getComputedStyle(document.querySelector('#{row(deep_3)} .admin-tree-row__title a')).color")
      assert_equal meta, page.evaluate_script("getComputedStyle(document.querySelector('#{row(deep_3)} .admin-tree-row__mark')).color")

      inner_at = center(row(inner))
      mouse.move(x: inner_at["x"], y: inner_at["y"])
      assert_selector "#{row(inner)}[data-media-drop-refused] [data-media-drop-reason]", text: "this folder"
      assert_no_selector "#{row(deep_3)}[data-media-drop-refused]"
      assert_selector status, text: "Can't move “Press” there: this folder.", visible: :all

      own_at = center(row(mover))
      mouse.move(x: own_at["x"], y: own_at["y"])
      assert_selector "#{row(mover)}[data-media-drop-refused] [data-media-drop-reason]", text: "this folder"

      clients_at = center(row(@clients))
      mouse.move(x: clients_at["x"], y: clients_at["y"])
      assert_selector "#{row(@clients)}[data-media-drop-refused] [data-media-drop-reason]", text: "name taken"
      assert_selector status, text: "Can't move “Press” there: name taken.", visible: :all
      assert_no_selector target
    end.up

    # Released on a refused row: nothing was sent, and the marks are gone.
    assert_no_selector "[data-media-drop-refused]"
    assert_no_selector "[data-media-drop-reason]"
    sleep 0.3 # sleep: nothing is expected to arrive; a move sent by mistake would answer within this
    assert_nil mover.reload.parent_id
  end

  test "dragging a tile shows no upload overlay" do
    visit_screen "/cs-studio/media"
    overlay = "[data-admin--media--drop-target=overlay]"

    drag(tile(@logo), row(@events)) do
      assert_selector "#{row(@events)}.admin-tree-drop-target"
      assert_selector overlay, visible: :hidden
      assert_no_selector overlay, visible: :visible
    end
    assert_eventually(message: "the image moved") { @logo.reload.folder_id == @events.id }
    assert_no_selector overlay, visible: :visible
  end

  test "a coarse pointer gets no drag and no handle" do
    page.driver.browser.page.command("Emulation.setTouchEmulationEnabled", enabled: true, maxTouchPoints: 1)
    visit_screen "/cs-studio/media"
    assert page.evaluate_script("!matchMedia('(pointer: fine)').matches"), "the browser still reports a fine pointer"

    assert_no_selector "#media-library[data-sortable]"
    assert_selector handle(@events), visible: :all
    assert_no_selector handle(@events), visible: :visible
    assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector(#{handle(@events).to_json})).display")
  ensure
    page.driver.browser.page.command("Emulation.setTouchEmulationEnabled", enabled: false)
  end

  test "a search typed in Find a folder stops the folders' drag" do
    visit_screen "/cs-studio/media"
    fill_in "Find a folder", with: "e"
    assert_selector "#media-folder-tree[data-filtered]"
    assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector(#{handle(@events).to_json})).display")
    assert_equal true, folders_sortable_disabled?

    # A press where the handle would stand lifts nothing.
    at = center(row(@events))
    mouse = page.driver.browser.mouse
    mouse.move(x: at["x"] - 30, y: at["y"])
    mouse.down
    3.times { |step| mouse.move(x: at["x"] - 30, y: at["y"] - (20 * (step + 1))); sleep 0.08 } # sleep: SortableJS's 50 ms sampling, as `drag` above
    assert_no_selector "body > li.admin-drag-fallback", visible: :all
    mouse.up

    # An image can still be dropped on a row the find shows.
    drag(tile(@logo), row(@events)) { assert_selector "#{row(@events)}.admin-tree-drop-target" }
    assert_eventually(message: "the image moved") { @logo.reload.folder_id == @events.id }

    find("#media-folder-tree-find, input[type=search][aria-controls=media-folder-tree]", match: :first).set("")
    assert_no_selector "#media-folder-tree[data-filtered]"
    assert_equal false, folders_sortable_disabled?
    assert_equal "grid", page.evaluate_script("getComputedStyle(document.querySelector(#{handle(@events).to_json})).display")
  end

  test "the move is announced in the polite status" do
    visit_screen "/cs-studio/media?folder=none"

    drag(tile(@logo), row(@events))
    assert_selector status, text: "Moved “logo” to Events.", visible: :all

    third = create_media_asset.tap { |asset| asset.update!(title: "third") }
    visit_screen "/cs-studio/media?folder=none&select=1"
    find("#{tile(@poster)} > button").click
    find("#{tile(third)} > button").click
    drag("#{tile(third)} > button", row(@clients))
    assert_selector status, text: "Moved 2 images to Clients.", visible: :all
  end
end
