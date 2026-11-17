require "application_system_test_case"

# The Gallery block's card in the page editor, in a browser (gallery spec
# §10.3, StudioGallery D3): images added from the picker choosing several,
# captioned, reordered by drag and by the keyboard moves, removed, each
# change autosaved through the card's form; read-only for a second person
# while the first holds it; and stopped at the limit.
class Admin::GalleryBlockSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    users(:one).update!(name: "Olga Braun")
    @page = create_page(title: "Harbour walk", published: false)
    sign_in_via_form(users(:one))
  end

  # The place the picker remembers is per browser, and the browser is shared
  # with the tests that follow.
  teardown do
    page.execute_script("try { localStorage.removeItem('cs.media.picker.place') } catch {}")
  end

  def titled(title) = create_media_asset.tap { |asset| asset.update!(title: title) }

  def gallery(ids = []) = @page.content_blocks.create!(block_type: "gallery", position: 0, settings: { "images" => ids })

  def card(block) = "#content_block_#{block.id}"

  def row(asset) = "[data-admin--editor--gallery-target=row][data-asset-id='#{asset.id}']"

  def handle(asset) = "#{row(asset)} .admin-gallery-row__handle"

  def shown_order(block) = page.all("#{card(block)} [data-admin--editor--gallery-target=row]").map { |element| element["data-asset-id"].to_i }

  def stored(block) = block.reload.settings["images"]

  # The moves' status is for a screen reader only (`sr-only`).
  def status(block) = find("#{card(block)} [data-admin--editor--gallery-target=status]", visible: :all).text(:all)

  # Every `admin--editor--gallery:moving` the page has heard, in order.
  def moving_said = page.evaluate_script("window.__galleryMoving")

  def keyboard = page.driver.browser.keyboard

  def centre(selector)
    page.evaluate_script("(() => { const r = document.querySelector(arguments[0]).getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2] })()", selector)
  end

  test "images are added, captioned, reordered by drag and by keyboard, removed, autosaved and kept after a reload" do
    harbour, forest, crowd = titled("Harbour"), titled("Forest"), titled("Crowd")
    block = gallery
    visit_editor(@page)

    within(card(block)) do
      assert_text "No images yet. Add them from the library, in the order the site shows them."
      click_on "Add images"
    end
    within("dialog[open]") do
      assert_selector "h2", exact_text: "Add images"
      click_on "Harbour"
      click_on "Forest"
      click_on "Crowd"
      click_on "Add 3 images"
    end
    refute_selector "dialog[open]"
    assert_equal [ harbour.id, forest.id, crowd.id ], shown_order(block)
    assert_selector "#{card(block)} button[aria-label='Remove Forest']"
    assert_text "3 of 60 images"
    assert_eventually(message: "the list was never saved") { stored(block) == [ harbour.id, forest.id, crowd.id ] }

    find("#block-#{block.id}-texts-#{harbour.id}-caption").set("The harbour at dusk")
    assert_eventually(message: "the caption was never saved") { block.reload.translated_settings.dig("en", "texts", harbour.id.to_s, "caption") == "The harbour at dusk" }

    # The keyboard: Space picks Crowd up, Up moves it, Space drops it. The
    # pick holds the editor's live list off (`moving`) until the drop.
    page.execute_script("window.__galleryMoving = []; document.addEventListener('admin--editor--gallery:moving', (event) => window.__galleryMoving.push(event.detail.moving))")
    find(handle(crowd)).click
    keyboard.type(:space)
    assert_equal [ true ], moving_said
    assert_equal "Picked up Crowd, image 3 of 3. Up and Down Arrow move it, Space or Enter drops it, Escape puts it back.", status(block)
    keyboard.type(:up)
    assert_equal "Moved to 2 of 3.", status(block)
    keyboard.type(:space)
    assert_equal "Dropped at 2 of 3.", status(block)
    assert_equal [ true, false ], moving_said
    assert_eventually(message: "the keyboard move was never saved") { stored(block) == [ harbour.id, crowd.id, forest.id ] }

    # Escape puts a picked row back, and nothing is written.
    keyboard.type(:space)
    keyboard.type(:up)
    keyboard.type(:escape)
    assert_equal "Cancelled. Crowd is back where it was.", status(block)
    assert_equal [ harbour.id, crowd.id, forest.id ], shown_order(block)

    # The pointer: Forest dragged above Harbour.
    page.execute_script("document.querySelector(arguments[0]).scrollIntoView({ block: 'center' })", row(harbour))
    from_x, from_y = centre(handle(forest))
    _, to_y = centre(handle(harbour))
    mouse = drag_pointer(from_x, from_y, to_y - 30)
    assert_eventually(message: "the dragged row's slot never reached the top") { shown_order(block).first == forest.id }
    mouse.up
    assert_eventually(message: "the drag was never saved") { stored(block) == [ forest.id, harbour.id, crowd.id ] }

    find("#{row(crowd)} button[aria-label='Remove Crowd']").click
    assert_no_selector row(crowd)
    assert_eventually(message: "the removal was never saved") { stored(block) == [ forest.id, harbour.id ] }
    assert_writes_settled

    visit_editor(@page)
    assert_equal [ forest.id, harbour.id ], shown_order(block)
    assert_equal "The harbour at dusk", find("#block-#{block.id}-texts-#{harbour.id}-caption").value
    assert_text "2 of 60 images"
  end

  test "a second person's card is read-only" do
    harbour = titled("Harbour")
    block = gallery([ harbour.id ])
    visit_editor(@page)
    find("#block-#{block.id}-texts-#{harbour.id}-alt").set("Boats at dusk")
    assert_writes_settled
    assert_eventually { block.reload.translated_settings.dig("en", "texts", harbour.id.to_s, "alt") == "Boats at dusk" }

    using_session(:dana) do
      sign_in_via_form(users(:two))
      visit_editor(@page)

      assert_selector "#{card(block)}[data-editing-held=true] [data-editing-kind=held]", text: "Olga Braun is editing this block"
      assert_selector "#block-#{block.id}-texts-#{harbour.id}-alt[readonly][value='Boats at dusk']"
      assert_selector "#block-#{block.id}-texts-#{harbour.id}-caption[readonly]"
      assert_selector "#{handle(harbour)}[disabled]"
      assert_selector "#{row(harbour)} button[aria-label='Remove Harbour'][disabled]"
      assert_selector "#{card(block)} button[disabled]", text: "Add images"
      assert_no_selector "#{card(block)} form[data-controller~='admin--saving--autosave']"
      assert_equal [ harbour.id ], shown_order(block)
    end
    assert_equal [ harbour.id ], stored(block)
  end

  test "the 61st image is not added and the card says the limit" do
    gone = Media::Asset.maximum(:id).to_i + 1000
    # Fifty-nine images that are gone (their rows say so), and one to add.
    block = gallery((1..59).map { |n| gone + n })
    last, extra = titled("Last"), titled("Extra")
    visit_editor(@page)

    within(card(block)) do
      assert_text "59 of 60 images"
      click_on "Add images"
    end
    within("dialog[open]") do
      assert_selector "[role=status]", exact_text: "No images selected · the gallery takes 1 more"
      click_on "Last"
      click_on "Add 1 image"
    end
    refute_selector "dialog[open]"

    within(card(block)) do
      assert_text "60 of 60 images"
      assert_text "A gallery holds at most 60 images. Remove one to add another."
      assert_selector "button[aria-disabled=true]", text: "Add images"
    end
    assert_eventually(message: "the 60th was never saved") { stored(block)&.size == 60 && stored(block).last == last.id }

    # Pressed at the limit, Add images opens nothing; and a picker's answer
    # past it is not taken.
    within(card(block)) { click_on "Add images" }
    await_frames
    refute_selector "dialog[open]"
    page.execute_script(<<~JS, card(block), extra.id)
      const button = document.querySelector(`${arguments[0]} [data-admin--editor--gallery-target=add]`)
      button.dispatchEvent(new CustomEvent("media-picker:picked", { bubbles: true, detail: { items: [ { id: arguments[1], url: "", title: "Extra", alt: "", caption: "" } ] } }))
    JS
    await_frames
    assert_no_selector row(extra)
    assert_writes_settled
    assert_equal 60, stored(block).size

    # A removal lifts the limit at once.
    find("#{row(last)} button[aria-label='Remove Last']").click
    within(card(block)) do
      assert_text "59 of 60 images"
      assert_no_text "A gallery holds at most 60 images. Remove one to add another."
      assert_selector "button:not([aria-disabled]):not([aria-describedby])", text: "Add images"
    end
    assert_eventually(message: "the removal was never saved") { stored(block).size == 59 }
  end

  test "removing the last image with no right to add puts the focus on the Images section" do
    group = access_control_groups(:branch_editors)
    %w[pages.read pages.edit pages.publish].each { |key| AccessControl::Grant.create!(group: group, permission: key, scope: {}) }
    harbour = titled("Harbour")
    block = gallery([ harbour.id ])
    using_session(:branch) do
      sign_in_via_form(users(:editor_branch))
      visit_editor(@page)

      within(card(block)) { assert_text "Adding images needs the right to upload to the library." }
      find("#{row(harbour)} button[aria-label='Remove Harbour']").click
      assert_no_selector row(harbour)
      assert_equal "group", page.evaluate_script("document.activeElement.getAttribute('role')")
      assert_text "No images yet. Add them from the library, in the order the site shows them."
    end
    assert_eventually(message: "the removal was never saved") { stored(block).nil? }
  end

  # `count` images in a new folder, oldest first, titled "Shot 01" and on.
  def folder_of(name, count)
    folder = Media::Folder.create!(name: name)
    images = Array.new(count) { |n| titled(format("Shot %02d", n + 1)) }
    Media::Asset.where(id: images.map(&:id)).update_all(folder_id: folder.id) # version: none (a test's own rows)
    [ folder, images ]
  end

  # In the open picker, the folder's place, from its row in the places.
  def go_to_folder(folder)
    within("dialog[open]") { find("#media-picker-place-row-#{folder.id} a").click }
    assert_selector "#media-picker-place[data-media-place='#{folder.id}']", visible: :all
  end

  # The folder's row, after the picker has asked what the folder adds.
  def folder_row_answered(total)
    assert_selector "#media-picker-folder[data-media-folder-total='#{total}']", visible: :all
  end

  test "a whole folder is added in upload order, skipping images already there, up to the limit" do
    folder, shots = folder_of("Client A", 34)
    there = [ shots[4], shots[10], shots[20] ]
    block = gallery(there.map(&:id))
    gone = Media::Asset.maximum(:id).to_i + 1000
    # Forty-five images that are gone and the same three: the gallery takes 12.
    full = @page.content_blocks.create!(block_type: "gallery", position: 1, settings: { "images" => (1..45).map { |n| gone + n } + there.map(&:id) })
    visit_editor(@page)

    within(card(block)) { click_on "Add a folder" }
    go_to_folder(folder)
    folder_row_answered(31)
    within("#media-picker-folder") do
      assert_text "Client A"
      assert_text "34 images"
      click_on "Add all 31 new images in this folder"
    end
    refute_selector "dialog[open]"
    added = shots - there
    assert_equal there.map(&:id) + added.map(&:id), shown_order(block)
    assert_eventually(message: "the folder was never saved") { stored(block) == there.map(&:id) + added.map(&:id) }

    # Past what the gallery takes: the oldest that fit, after a tile chosen
    # first, which the count then leaves out.
    within(card(full)) { click_on "Add images" }
    assert_selector "#media-picker-place[data-media-place='#{folder.id}']", visible: :all
    folder_row_answered(31)
    within("#media-picker-folder") { assert_button "Add the first 12 of 31 new images" }
    within("dialog[open]") { click_on "Shot 34" }
    folder_row_answered(30)
    within("#media-picker-folder") { click_on "Add the first 11 of 30 new images" }
    refute_selector "dialog[open]"
    expected = there.map(&:id) + [ shots[33].id ] + (added - [ shots[33] ]).first(11).map(&:id)
    assert_equal expected, shown_order(full).last(15)
    within(card(full)) { assert_text "60 of 60 images" }
    assert_eventually(message: "the limit's folder was never saved") { stored(full)&.size == 60 && stored(full).last(15) == expected }
  end

  test "the folder's row stands only in a multiple opening at a folder with new images" do
    done, done_shots = folder_of("Done", 2)
    fresh, = folder_of("Fresh", 1)
    block = gallery(done_shots.map(&:id))
    image = @page.content_blocks.create!(block_type: "image", position: 1)
    visit_editor(@page)

    # All media, then a folder whose images are all in the gallery.
    within(card(block)) { click_on "Add images" }
    within("dialog[open]") do
      assert_selector "#media-picker-place[data-media-place='all']", visible: :all
      assert_no_selector "#media-picker-folder", visible: :all
    end
    go_to_folder(done)
    folder_row_answered(0)
    assert_no_selector "#media-picker-folder"

    go_to_folder(fresh)
    folder_row_answered(1)
    within("#media-picker-folder") do
      assert_text "Fresh"
      assert_text "1 image"
      assert_button "Add the 1 new image in this folder"
    end
    within("dialog[open]") { click_on "Cancel" }
    refute_selector "dialog[open]"

    # A single opening at the same folder draws the row and never shows it.
    within("##{Admin::EditorScreen::BlockCardComponent.error_prefix(image)}-image-section") { click_on "Choose image" }
    assert_selector "#media-picker-place[data-media-place='#{fresh.id}']", visible: :all
    assert_selector "#media-picker-folder", visible: :hidden
    await_frames
    assert_no_selector "#media-picker-folder"
    assert_no_selector "#media-picker-folder[data-media-folder-total]", visible: :all
  end
end
