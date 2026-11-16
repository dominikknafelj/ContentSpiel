require "application_system_test_case"

# The one media picker:
# `Admin::Ui::MediaPickerComponent`, a modal that is the Media grid in miniature -- instant
# search, segments, selectable tiles, a header Upload and a footer "N selected ·
# Cancel · Use image" -- opened from the page hero field, an image block's image
# field and the rich-text editor's Image button, each of which receives
# the picked asset's id and stores it (a hidden `hero_media_asset_id` /
# `media_asset_id` input autosave sends, or an `image{asset_id}` node). Choosing
# is select-then-use (D14): a click selects, Use image confirms, a double click
# does both.
#
# Native clicks throughout (Cuprite's own `click`), not
# `ApplicationSystemTestCase#press`'s scripted one: opening a modal
# `<dialog>`, moving focus into it and handing it back afterwards are
# exactly what these tests are about, and a scripted `element.click()`
# never focuses the button it clicks the way a real pointer click does.
class Admin::MediaPickerSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  PLACE_KEY = "cs.media.picker.place"

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))

    # `wide.png` is 3000x2000, so every variant width applies; processed
    # up front so the public page's `srcset` has something to list.
    @asset = create_media_asset(filename: "wide.png")
    @asset.file.analyze
    perform_enqueued_jobs # includes Media::RenditionJob: the widths are made here
    @asset.reload

    @landing = create_page(title: "Landing")
    assert Pages::Save.call(@landing, attributes: { template: "landing" }).ok?
  end

  # The place the picker remembers is per browser, and the browser is shared
  # with the tests that follow.
  teardown do
    page.execute_script("try { localStorage.removeItem(arguments[0]) } catch {}", PLACE_KEY)
  end

  test "picking an image sets the field's width, height and blur, and the next pick replaces them" do
    bare = create_media_asset(filename: "tiny.png") # its widths are not made: the preview stands in
    @asset.update_columns(width: 3000, height: 2000) # version: none (a test's own size)

    visit_editor(@landing)
    within("#page-hero-image-section") { click_on "Choose image" }
    pick_from_library(bare)
    thumb = "#page-hero-image-section img[data-admin--media--field-target=thumbnail]"
    assert_selector "#{thumb}[src^='data:'][width='#{bare.width}'][height='#{bare.height}'].blur-sm"

    within("#page-hero-image-section") { click_on "Change image" }
    pick_from_library(@asset)
    assert_selector "#{thumb}[width='3000'][height='2000']:not([src^='data:']):not(.blur-sm)"

    # The pick's autosave answer replaces the section: wait for it before pressing Remove.
    assert_eventually(wait: 10, message: "the pick was saved") { @landing.reload.hero_media_asset_id == @asset.id }
    within("#page-hero-image-section") { click_on "Remove image" }
    assert_selector "#{thumb}[hidden]:not([width]):not([height])", visible: :all
  end

  test "one library image as hero, image block and rich text is listed under Used on, and removing the hero drops its usage" do
    block = @landing.content_blocks.create!(block_type: "image", position: 0)
    post = create_post(title: "Notes")
    @asset.update!(alt: "A wide view", caption: "Wide")

    # Hero: choose the library image. The hero's alt override now shows the
    # image's own default as its placeholder.
    visit_editor(@landing)
    within("#page-hero-image-section") { click_on "Choose image" }
    pick_from_library(@asset)
    within("#page-hero-image-section") { assert_button "Change image" }
    assert_selector "#page-hero_alt[placeholder='A wide view']"
    assert_eventually { @landing.reload.hero_media_asset_id == @asset.id }

    # The public page renders it responsively. The site shows the page's
    # published copy, so the hero chosen in the editor is published first
    # (setup fix).
    publish_changes(@landing)
    visit "/landing"
    assert_selector "header img[src='#{@asset.src}'][srcset*='480w']"

    # Image block: the same image.
    visit_editor(@landing)
    within("##{Admin::EditorScreen::BlockCardComponent.error_prefix(block)}-image-section") { click_on "Choose image" }
    pick_from_library(@asset)
    assert_eventually { block.reload.media_asset_id == @asset.id }

    # Rich text: the Image button opens the same picker and inserts an
    # `image{asset_id}` node.
    visit_editor(post)
    find(".ProseMirror").click
    press_insert "Image"
    # Picking opens the image dialog, so not `pick_from_library`,
    # which waits for every dialog to close.
    within("dialog[open]") { click_on @asset.title; click_on "Use image" }
    assert_selector "dialog#rich-text-image-dialog[open]"
    # The per-use fields show the image's own defaults as placeholders.
    within("dialog#rich-text-image-dialog[open]") do
      assert_field "Alt text", with: "", placeholder: "A wide view"
      assert_field "Caption", with: "", placeholder: "Wide"
      click_on "Insert image"
    end
    assert_eventually do
      post.reload.body_document(locale: :en).to_h.to_json.include?(%("asset_id":#{@asset.id}))
    end

    # "Used on" lists all three places.
    visit "/cs-studio/media?selected=#{@asset.id}"
    assert_link "Hero image — page “Landing”"
    assert_link "Image block — page “Landing”"
    assert_link "Rich text — post “Notes” (en)"

    # Removing the hero clears the reference; the usage goes with it.
    visit_editor(@landing)
    within("#page-hero-image-section") { click_on "Remove image" }
    within("#page-hero-image-section") { assert_button "Choose image" }
    assert_eventually { @landing.reload.hero_media_asset_id.nil? }

    visit "/cs-studio/media?selected=#{@asset.id}"
    assert_link "Image block — page “Landing”"
    assert_no_link "Hero image — page “Landing”"
    assert Media::Asset.exists?(@asset.id)
  end

  test "an upload through the picker's header Upload: a refused file keeps its tile and reason, a good one is selected, Use image lands it in an image block" do
    block = @landing.content_blocks.create!(block_type: "image", position: 0)
    visit_editor(@landing)

    within("##{Admin::EditorScreen::BlockCardComponent.error_prefix(block)}-image-section") { click_on "Choose image" }
    within("dialog[open]") do
      assert_button @asset.title
      attach_file "Image file", file_fixture("fake.png").to_s
      assert_selector "[data-upload-tile]", text: /PNG, JPEG, GIF, or WEBP/, wait: 10
      assert_button "Dismiss"
      assert_text "No image selected"
    end
    assert_equal 1, Media::Asset.count

    within("dialog[open]") do
      attach_file "Image file", file_fixture("tiny.png").to_s
      assert_text "1 selected", wait: 10
      # The refused file's tile is still there beside the new one.
      assert_selector "[data-upload-tile]", text: /PNG, JPEG, GIF, or WEBP/
      click_on "Use image"
    end
    refute_selector "dialog[open]"

    within("##{Admin::EditorScreen::BlockCardComponent.error_prefix(block)}-image-section") { assert_button "Change image" }
    uploaded = Media::Asset.where.not(id: @asset.id).sole
    assert_equal "tiny", uploaded.title
    assert_eventually { block.reload.media_asset_id == uploaded.id }
  end

  # The carried requirement: one good and one refused file in a single batch.
  test "a batch of one good and one refused file in the picker: the good one becomes a tile and is selected, the refused one keeps its reason and Dismiss" do
    visit_editor(@landing)

    within("#page-hero-image-section") { click_on "Choose image" }
    within("dialog[open]") do
      assert_button @asset.title
      attach_file "Image file", [ file_fixture("fake.png").to_s, file_fixture("tiny.png").to_s ]
      assert_text "1 selected", wait: 10
      assert_selector "[data-upload-tile]", text: /PNG, JPEG, GIF, or WEBP/
      assert_button "tiny"
      assert_text "Unused", minimum: 2
      find("[data-upload-tile] button", text: "Dismiss").click
      assert_no_selector "[data-upload-tile]"
    end
    assert_equal 2, Media::Asset.count
  end

  # "Nothing was chosen" can't be read off the record straight away: a choice is
  # saved by the form's autosave, a debounce after the field is filled, so the
  # record is empty at that moment whether or not something was chosen. So the
  # field is asked -- its value is what the next save would send -- and, with
  # `after_a_save:`, a save is pushed through with another field first, after
  # which the record's own value means something.
  def assert_no_image_chosen(after_a_save: nil)
    assert_equal "", find("#page-hero-image-section input[data-admin--media--field-target=input]", visible: :all).value
    return unless after_a_save

    fill_in "Title", with: after_a_save
    assert_eventually { @landing.reload.title(locale: :en) == after_a_save }
    assert_nil @landing.hero_media_asset_id
  end

  test "choosing: a click only selects, Use image fills the field, a double click picks at once" do
    other = create_media_asset(filename: "tiny.png")
    visit_editor(@landing)

    within("#page-hero-image-section") { click_on "Choose image" }
    within("dialog[open]") do
      assert_text "No image selected"
      assert_button "Use image", disabled: true
      click_on @asset.title
      assert_text "1 selected"
      assert_selector "button[aria-pressed=true]", count: 1
      assert_button "Use image", disabled: false
      # Selecting another moves the selection.
      click_on other.title
      assert_selector "button[aria-pressed=true]", text: other.title, count: 1
    end
    assert_selector "dialog[open]"
    assert_no_image_chosen

    within("dialog[open]") { click_on "Use image" }
    refute_selector "dialog[open]"
    within("#page-hero-image-section") { assert_button "Change image" }
    assert_eventually { @landing.reload.hero_media_asset_id == other.id }

    within("#page-hero-image-section") { click_on "Change image" }
    within("dialog[open]") { find("button", text: @asset.title).double_click }
    refute_selector "dialog[open]"
    assert_eventually { @landing.reload.hero_media_asset_id == @asset.id }
  end

  # Keys go to the page, so they reach whatever holds the focus: the tile is
  # reached by Tab from the search field and never clicked.
  test "the keyboard reaches a tile by Tab from the search field, Space selects it and a second Enter on it confirms" do
    visit_editor(@landing)

    within("#page-hero-image-section") { click_on "Choose image" }
    within("dialog[open]") { assert_button @asset.title }
    # The search field takes the focus as the picker opens.
    search = find_field("Search images")[:id]
    assert_eventually(message: "the search field never took the focus") { page.evaluate_script("document.activeElement.id") == search }
    stop_on("dialog[open] button[aria-pressed]")
    assert_match(/\A#{Regexp.escape(@asset.title)}\b/, focused_text)
    assert_selector "dialog[open] button[aria-pressed=false]", text: @asset.title

    page.send_keys(:space)
    assert_selector "dialog[open] [role=status]", text: "1 selected"
    assert_selector "dialog[open] button[aria-pressed=true]", text: @asset.title
    assert_selector "dialog[open]"

    page.send_keys(:enter)
    refute_selector "dialog[open]"
    assert_eventually { @landing.reload.hero_media_asset_id == @asset.id }
  end

  # The picker draws the library's tile class and keeps its own fixed columns,
  # which follow the window, not a container.
  test "the picker's tiles are the library's: a pressed tile has the accent outline, and the grid takes 4, 3 or 2 columns by the window" do
    visit_editor(@landing)

    within("#page-hero-image-section") { click_on "Choose image" }
    within("dialog[open]") { click_on @asset.title }
    assert_selector "dialog[open] button.admin-tile[aria-pressed=true]", text: @asset.title
    assert_equal Admin::MediaLibrary::TileComponent::CARD, find("dialog[open] button[aria-pressed=true]")[:class]

    accent = page.evaluate_script(<<~JS)
      (() => {
        const probe = document.createElement("div")
        probe.style.color = "var(--cs-accent)"
        document.querySelector("dialog[open]").append(probe)
        const color = getComputedStyle(probe).color
        probe.remove()
        return color
      })()
    JS
    look = page.evaluate_script(<<~JS)
      (() => {
        const style = getComputedStyle(document.querySelector("dialog[open] button[aria-pressed=true]"))
        return [ style.outlineStyle, style.outlineWidth, style.outlineOffset, style.outlineColor, style.borderTopWidth ]
      })()
    JS
    assert_equal [ "solid", "2px", "2px", accent, "0px" ], look

    # Beside the places (the card's D12): four columns from 1024px, three
    # from 768px, two below.
    columns = -> { page.evaluate_script(%(getComputedStyle(document.querySelector("dialog[open] ul.admin-media-grid")).gridTemplateColumns.split(" ").length)) }
    assert_equal 4, columns.call
    at_window(800) { assert_eventually(message: -> { "the picker shows #{columns.call} columns at 800px" }) { columns.call == 3 } }
    at_window(600) { assert_eventually(message: -> { "the picker shows #{columns.call} columns at 600px" }) { columns.call == 2 } }
  end

  test "the search is instant with no button, segments filter inside the dialog, and the selection survives" do
    other = create_media_asset(filename: "tiny.png")
    visit_editor(@landing)

    within("#page-hero-image-section") { click_on "Choose image" }
    within("dialog[open]") do
      assert_no_button "Search"
      assert_button other.title
      click_on @asset.title
      assert_text "1 selected"

      fill_in "Search images", with: "tiny"
      assert_no_button @asset.title
      assert_button other.title
      # The choice outlives a grid that no longer lists it.
      assert_text "1 selected"
      assert_button "Use image", disabled: false

      fill_in "Search images", with: ""
      assert_selector "button[aria-pressed=true]", text: @asset.title

      find("label", text: /Missing alt/).click
      assert_button @asset.title
    end
    assert_selector "dialog[open]"
    assert_current_path "/cs-studio/pages/#{@landing.id}"
  end

  test "Escape clears the search first, a second Escape closes the dialog and focus goes back to the opener" do
    visit_editor(@landing)

    within("#page-hero-image-section") { click_on "Choose image" }
    within("dialog[open]") do
      assert_button @asset.title
      fill_in "Search images", with: "zzz-nothing"
      assert_text "No matches"
      page.send_keys(:escape)
      assert_field "Search images", with: ""
      assert_button @asset.title
    end
    assert_selector "dialog[open]"

    page.send_keys(:escape)
    refute_selector "dialog[open]"
    assert_selector "#page-hero-image-section button:focus", text: "Choose image"
  end

  test "the × and Cancel close without choosing, and a press that begins inside and ends on the backdrop leaves it open" do
    visit_editor(@landing)

    within("#page-hero-image-section") { click_on "Choose image" }
    within("dialog[open]") do
      assert_button @asset.title
      click_on @asset.title
    end

    box = page.evaluate_script("(() => { const r = document.querySelector('dialog[open]').getBoundingClientRect(); return [r.left, r.top, r.right, r.bottom] })()")
    left, top, right, _bottom = box
    mouse = page.driver.browser.mouse
    mouse.move(x: (left + right) / 2, y: top + 30)
    mouse.down
    mouse.move(x: 5, y: 5)
    mouse.up
    await_frames # the backdrop's click handler has run by now
    assert_selector "dialog[open]"

    within("dialog[open]") { find("button[aria-label=Close]").click }
    refute_selector "dialog[open]"
    assert_no_image_chosen

    within("#page-hero-image-section") { click_on "Choose image" }
    within("dialog[open]") do
      # Reopened afresh: nothing is selected.
      assert_text "No image selected"
      click_on "Cancel"
    end
    refute_selector "dialog[open]"
    assert_no_image_chosen after_a_save: "Landing, nothing chosen"
  end

  # With a realistic trigger: the image is deleted
  # between opening the picker and picking it. The save is refused
  # ("doesn't exist"), the field goes back to the stored hero with the
  # message showing, and the next autosave doesn't resend the refused id.
  test "picking an image deleted meanwhile is refused and the field shows the stored hero again" do
    stored = create_media_asset(filename: "tiny.png")
    assert Pages::Save.call(@landing, attributes: { hero_media_asset_id: stored.id }).ok?
    doomed = create_media_asset(filename: "medium.png")
    visit_editor(@landing)

    within("#page-hero-image-section") { click_on "Change image" }
    within("dialog[open]") { assert_button doomed.title }
    assert delete_for_good(doomed)
    pick_from_library(doomed)

    # Waited for outside `within` first: the refusal
    # replaces the whole section, and a `within` scope found before that
    # stream lands goes stale (Cuprite's ObsoleteNode) instead of retrying.
    # A longer wait than Capybara's 2s default: picking runs an autosave
    # PATCH whose refusal comes back as a stream replacing the section,
    # which can take longer than 2s on a slow CI runner.
    assert_selector "#page-hero-image-section", text: "Hero image doesn't exist", wait: 10
    within("#page-hero-image-section") do
      assert_text "Hero image doesn't exist"
      assert_text stored.title
      assert_button "Change image"
      assert_selector "input[type=hidden][value='#{stored.id}']", visible: :all
    end

    # The next autosave -- another field -- goes through.
    fill_in "Title", with: "Landing v2"
    assert_eventually { @landing.reload.title(locale: :en) == "Landing v2" }
    assert_equal stored.id, @landing.hero_media_asset_id
    # ...and that successful save did not erase the refusal message: it stays
    # until the editor acts on the hero field again.
    assert_selector "#page-hero-image-section", text: "Hero image doesn't exist"
  end

  test "Escape closes the picker and returns focus to the button that opened it" do
    visit_editor(@landing)

    within("#page-hero-image-section") { click_on "Choose image" }
    assert_selector "dialog[open]"

    page.send_keys(:escape)

    refute_selector "dialog[open]"
    assert_selector "#page-hero-image-section button:focus", text: "Choose image"
    assert_no_image_chosen after_a_save: "Landing, after Escape"
  end

  # The picker's height changes while it is open -- the grid is empty until its
  # request answers, a search narrows it, progress tiles join it -- and a centred
  # dialog moved its header with every change (112px up when the library arrived),
  # so a click aimed at something just after opening landed on what had slid
  # under the pointer: CI's one-run-in-ten failure of the rich-text upload test.
  # The picker hangs from a fixed top edge (`.admin-media-picker`), so its top and
  # its header stay put. The grid's answer is held back here until the first
  # measurement is taken, so the test sees both states every time instead of
  # whichever the timing gives it.
  test "the picker's top edge stays where it is when the grid arrives and when a search narrows it" do
    other = create_media_asset(filename: "tiny.png")
    visit_editor(@landing)
    hold_picker_grid
    top = -> { page.evaluate_script("document.getElementById('media-picker').getBoundingClientRect().top") }

    within("#page-hero-image-section") { click_on "Choose image" }
    assert_selector "dialog#media-picker[open]"
    assert_no_selector "#media-picker-grid *", visible: :all, wait: 0.5
    before_grid = top.call

    page.execute_script("window.__releaseGrid()")
    within("dialog[open]") { assert_button @asset.title }
    assert_in_delta before_grid, top.call, 0.5, "the dialog moved when the grid loaded"

    within("dialog[open]") do
      fill_in "Search images", with: "tiny"
      assert_no_button @asset.title
      assert_button other.title
    end
    assert_in_delta before_grid, top.call, 0.5, "the dialog moved when a search narrowed the grid"
  end

  # Opened again, the picker loads a fresh grid, and the last open's stood in
  # the frame until it came: a press that began on an old tile and ended on
  # its fresh twin was no click (CI: Use image never came on). The grid's
  # answer is held so the frame is seen between the open and the grid.
  test "opened again, the picker shows none of the last open's grid before its own arrives" do
    visit_editor(@landing)
    within("#page-hero-image-section") { click_on "Choose image" }
    within("dialog[open]") { assert_button @asset.title }
    page.send_keys(:escape)
    refute_selector "dialog[open]"
    hold_picker_grid

    within("#page-hero-image-section") { click_on "Choose image" }
    assert_selector "dialog#media-picker[open]"
    assert_no_selector "#media-picker-grid *", visible: :all

    page.execute_script("window.__releaseGrid()")
    pick_from_library(@asset)
    assert_selector "#page-hero-image-section [data-admin--media--field-target=title]", text: @asset.title
  end

  # Closed and opened again before its grid was drawn, the picker let that
  # load finish: a second one drew over it, took the search box the first
  # grid had focused out from under the person and left the focus on the
  # page's body (CI: the next key pressed went to a detached node).
  test "closed and opened again before its grid arrives, the picker asks for the grid once and the search box keeps the focus" do
    visit_editor(@landing)
    hold_picker_grid

    within("#page-hero-image-section") { click_on "Choose image" }
    assert_selector "dialog#media-picker[open]"
    page.send_keys(:escape)
    refute_selector "dialog[open]"
    assert_selector "#page-hero-image-section button:focus", text: "Choose image"
    page.send_keys(:space)
    assert_selector "dialog#media-picker[open]"

    page.execute_script("window.__releaseGrid()")
    within("dialog[open]") { assert_button @asset.title }
    assert_selector "#media-picker-q:focus"
    assert_equal 1, page.evaluate_script("window.__gridRequests")
  end

  # A dialog's `close` event comes a task after the close, so a picker opened
  # again at once is already open when it arrives; answering it then forgot
  # the new opener, and the image picked next went nowhere. A person is never
  # that quick; a script closing and opening in one task is the event's order
  # every time.
  test "a close whose event arrives after the next open leaves that open's pick standing" do
    block = @landing.content_blocks.create!(block_type: :image, position: 0)
    card = "[data-block-id='#{block.id}']"
    visit_editor(@landing)
    within(card) { click_on "Choose image" }
    assert_selector "dialog#media-picker[open]"

    page.execute_script(<<~JS)
      const opener = document.querySelector("#{card} button[data-action*='admin--media--field#choose']")
      document.getElementById("media-picker").close()
      window.dispatchEvent(new CustomEvent("media-picker:open", { detail: { opener } }))
    JS
    pick_from_library(@asset)
    assert_selector "#{card} [data-admin--media--field-target=title]", text: @asset.title
  end

  # The picker choosing several (the card StudioGallery, D4), opened by a
  # stand-in for the Gallery card: `media-picker:open` with `multiple`, `max`
  # (what the gallery still takes) and `chosen` (the ids already in it).
  test "a multiple opening reads Add images, toggles tiles numbered in the order chosen, keeps the order across searches and places, and hands back items" do
    harbour, crowd = titled("Harbour"), titled("Crowd")
    client_a = client_folders.last
    stage = in_folder(titled("Stage"), client_a)
    visit_screen(admin_root_path)

    open_multiple(max: 10)
    within("dialog[open]") do
      assert_selector "h2", exact_text: "Add images"
      assert_button "Add images", disabled: true
      assert_no_button "Use image"
      assert_selector "[role=status]", exact_text: "No images selected · the gallery takes 10 more"

      click_on "Harbour"
      assert_order harbour => 1
      assert_selector "[role=status]", exact_text: "1 selected · the gallery takes 9 more"
      click_on "Crowd"
      assert_order harbour => 1, crowd => 2
      assert_button "Add 2 images", disabled: false
      # Unchoosing renumbers the rest.
      click_on "Harbour"
      assert_order crowd => 1
      assert_selector "#{tile(harbour)}[aria-pressed=false]"
      click_on "Harbour"
      assert_order crowd => 1, harbour => 2

      fill_in "Search images", with: "Crowd"
      assert_no_button "Harbour"
      assert_order crowd => 1
      assert_selector "[role=status]", exact_text: "2 selected · the gallery takes 8 more"
      fill_in "Search images", with: ""
      assert_order crowd => 1, harbour => 2

      find("button[aria-label='Unfold Clients']").click
      click_on "Client A"
      assert_place client_a.id
      click_on "Stage"
      assert_order stage => 3
      click_on "All media"
      assert_place "all"
      assert_order crowd => 1, harbour => 2, stage => 3
      assert_selector "[role=status]", exact_text: "3 selected · the gallery takes 7 more"
      click_on "Add 3 images"
    end
    refute_selector "dialog[open]"

    await_js("window.__picked !== null", message: "the opener was never answered")
    picked = page.evaluate_script("window.__picked")
    assert_equal [ crowd.id, harbour.id, stage.id ], picked.fetch("items").map { |item| item["id"] }
    assert_equal %w[alt caption id title url], picked["items"].first.keys.intersection(%w[id url title alt caption]).sort
    assert_equal "Crowd", picked["items"].first["title"]
    assert_nil picked["id"], "a multiple opening answers items, not one image's keys"
    assert_equal "stand-in-opener", page.evaluate_script("document.activeElement.id")
  end

  test "images already in the gallery are marked and not chosen again" do
    harbour, crowd = titled("Harbour"), titled("Crowd")
    visit_screen(admin_root_path)

    open_multiple(max: 5, chosen: [ harbour.id ])
    within("dialog[open]") do
      present = find("#{tile(harbour)}[aria-disabled=true]")
      assert_equal "In the gallery", find_by_id(present["aria-describedby"], visible: :all).text(:all).strip
      assert_selector "#{tile(harbour)} [data-media-pick-in-gallery]", text: "In the gallery"
      assert_match(/saturate\(0\.35\)/, page.evaluate_script(%(getComputedStyle(document.querySelector("#{tile(harbour)} img:not([aria-hidden])")).filter)))

      present.click
      assert_selector "#{tile(harbour)}[aria-pressed=false]"
      assert_no_selector "#{tile(harbour)} [data-media-pick-order]"
      assert_button "Add images", disabled: true

      click_on "Crowd"
      assert_order crowd => 1
      # The mark outlives a load of the grid.
      fill_in "Search images", with: "Harbour"
      assert_selector "#{tile(harbour)}[aria-disabled=true]"
      assert_selector "#{tile(harbour)} [data-media-pick-in-gallery]"
      assert_no_selector "#{tile(crowd)}[aria-disabled]"
    end
  end

  test "the choice stops at max and says so" do
    harbour, crowd, stage = titled("Harbour"), titled("Crowd"), titled("Stage")
    visit_screen(admin_root_path)

    # 58 images in the gallery, so it takes 2 more of its 60.
    open_multiple(max: 2, chosen: (1..58).map { |n| 1_000_000 + n })
    within("dialog[open]") do
      click_on "Harbour"
      click_on "Crowd"
      assert_selector "[role=status]", exact_text: "The gallery takes no more: 60 images."
      assert_selector "#{tile(stage)}[aria-disabled=true]"
      assert_no_selector "#{tile(harbour)}[aria-disabled], #{tile(crowd)}[aria-disabled]"
      # It looks disabled, with no pill, and the status line says why.
      limited = find("#{tile(stage)}[data-media-pick-limit]")
      assert_equal "The gallery takes no more: 60 images.", find_by_id(limited["aria-describedby"]).text
      assert_no_selector "#{tile(stage)} [data-media-pick-in-gallery], #{tile(stage)} [data-media-pick-order]"
      look = page.evaluate_script(<<~JS)
        (() => {
          const tile = document.querySelector("#{tile(stage)}")
          const meta = getComputedStyle(document.querySelector("dialog[open] [role=status].text-meta")).color
          return { filter: getComputedStyle(tile.querySelector("img:not([aria-hidden])")).filter, cursor: getComputedStyle(tile).cursor,
                   title: getComputedStyle(tile.querySelector(".text-ink, .font-medium")).color === meta }
        })()
      JS
      assert_equal({ "filter" => "saturate(0.35)", "cursor" => "not-allowed", "title" => true }, look)
      # No lift under the pointer: elevation 1, a chosen tile's.
      find(tile(stage)).hover
      shadow = ->(asset) { page.evaluate_script(%(getComputedStyle(document.querySelector("#{tile(asset)}")).boxShadow)) }
      assert_equal shadow.(harbour), shadow.(stage)

      find(tile(stage)).click
      assert_selector "#{tile(stage)}[aria-pressed=false]"
      assert_order harbour => 1, crowd => 2

      click_on "Harbour"
      assert_no_selector "#{tile(stage)}[aria-disabled]"
      assert_no_selector "#{tile(stage)}[data-media-pick-limit], #{tile(stage)}[aria-describedby]"
      assert_selector "[role=status]", exact_text: "1 selected · the gallery takes 1 more"
      click_on "Stage"
      assert_order crowd => 1, stage => 2
    end
  end

  test "a chosen tile's name says its place in the order" do
    harbour, crowd, stage = titled("Harbour"), titled("Crowd"), titled("Stage")
    visit_screen(admin_root_path)

    open_multiple(max: 10)
    within("dialog[open]") do
      unchosen = accessible_name(tile(crowd))
      assert_match(/\ACrowd\b.*No alt.*Unused\z/, unchosen)
      click_on "Harbour"
      click_on "Crowd"
      click_on "Stage"
      assert_order harbour => 1, crowd => 2, stage => 3
      # The whole name stays, the order after it; the badges stay drawn.
      assert_equal "#{unchosen}, chosen 2nd", accessible_name(tile(crowd))
      assert_match(/, chosen 1st\z/, accessible_name(tile(harbour)))
      assert_match(/, chosen 3rd\z/, accessible_name(tile(stage)))
      assert_selector tile(crowd), text: "No alt"
      assert_no_selector "#{tile(crowd)}[aria-label]"

      click_on "Harbour"
      assert_no_match(/chosen/, accessible_name(tile(harbour)))
      assert_match(/, chosen 2nd\z/, accessible_name(tile(stage)))
      # The number is a picture of the name, never read beside it.
      assert_selector "#{tile(stage)} [data-media-pick-order][aria-hidden=true]", text: "2"
    end
  end

  # Important 1: the keyboard in a multiple opening. A press is a toggle, a
  # tile that cannot be chosen takes no press, and a held Enter (the key's
  # repeats) toggles once, not on and off with every repeat.
  test "in a multiple opening Tab reaches a tile, Space chooses it, Enter unchooses it, a disabled tile takes no key and a held Enter toggles once" do
    harbour, crowd = titled("Harbour"), titled("Crowd")
    visit_screen(admin_root_path)

    # 59 images in the gallery: it takes one more of its 60.
    open_multiple(max: 1, chosen: (1..59).map { |n| 1_000_000 + n })
    await_js(%(document.activeElement?.matches("dialog[open] input[type=search]")), message: "the search field did not take the focus")
    stop_on("dialog[open] button[aria-pressed]")
    first = page.evaluate_script("document.activeElement.closest('li').id")
    other = ([ harbour, crowd ].map { |asset| "media-picker-asset-#{asset.id}" } - [ first ]).sole

    page.send_keys(:space)
    assert_selector "##{first} button[aria-pressed=true] [data-media-pick-order]", text: "1"
    assert_selector "##{other} button[aria-disabled=true]"
    assert_selector "dialog[open]"

    # The other tile is at the limit: Space and Enter on it change nothing.
    stop_on("##{other} button")
    page.send_keys(:space)
    page.send_keys(:enter)
    assert_selector "##{other} button[aria-pressed=false][aria-disabled=true]"
    assert_selector "##{first} button[aria-pressed=true]"

    stop_on("##{first} button", keys: [ :shift, :tab ])
    page.send_keys(:enter)
    assert_selector "##{first} button[aria-pressed=false]"
    assert_no_selector "dialog[open] [data-media-pick-order]"

    hold_enter(repeats: 3)
    assert_selector "##{first} button[aria-pressed=true] [data-media-pick-order]", text: "1"
    assert_selector "dialog[open] [role=status]", exact_text: "The gallery takes no more: 60 images."
  end

  # A gallery adds what was just uploaded: every finished upload of a batch
  # joins the choice in the order it finished, until the gallery is full,
  # and a tile that arrives after that is drawn at the limit at once.
  test "in a multiple opening every finished upload joins the choice, up to the limit" do
    harbour = titled("Harbour")
    visit_screen(admin_root_path)

    open_multiple(max: 3, chosen: (1..57).map { |n| 1_000_000 + n })
    within("dialog[open]") do
      click_on "Harbour"
      attach_file "Image file", [ file_fixture("tiny.png").to_s, file_fixture("small.gif").to_s, file_fixture("medium.png").to_s ]
      assert_selector "[role=status]", exact_text: "The gallery takes no more: 60 images.", wait: 15
      # The setup's image, Harbour and the three uploads.
      assert_selector "ul.admin-media-grid > li[id^=media-picker-asset-]", count: 5, wait: 15
    end
    uploads = Media::Asset.where.not(id: [ harbour.id, @asset.id ]).order(:id).to_a
    assert_equal 3, uploads.size
    within("dialog[open]") do
      assert_order harbour => 1, uploads[0] => 2, uploads[1] => 3
      assert_selector "#{tile(uploads[2])}[aria-disabled=true][data-media-pick-limit]"
    end
  end

  # Minor 2: the choice and the scripts' marks go with the close, and the
  # single opening's title and primary come back, so neither the next
  # opening nor Turbo's snapshot keeps them.
  test "a closed multiple opening leaves nothing chosen for the next" do
    titled("Harbour")
    visit_screen(admin_root_path)

    open_multiple(max: 10)
    within("dialog[open]") do
      click_on "Harbour"
      assert_selector "[data-media-pick-order]"
      click_on "Cancel"
    end
    refute_selector "dialog[open]"
    within("dialog#media-picker", visible: :all) do
      assert_selector "h2", exact_text: "Choose an image", visible: :all
      assert_selector "button[data-admin--media--select-target=use]", exact_text: "Use image", visible: :all
      assert_no_selector "[data-media-pick-order], [aria-pressed=true]", visible: :all
    end

    open_multiple(max: 10)
    within("dialog[open]") do
      assert_selector "h2", exact_text: "Add images"
      assert_selector "[role=status]", exact_text: "No images selected · the gallery takes 10 more"
      assert_no_selector "[data-media-pick-order], [aria-pressed=true]"
      assert_button "Add images", disabled: true
    end
  end

  test "focus: places puts the focus on the places, and without it the default focus stays" do
    visit_screen(admin_root_path)

    open_multiple(max: 10, focus: "places")
    await_js(%(document.activeElement?.closest("#media-picker-place-row-all") !== null), message: "the place shown did not take the focus")
    within("dialog[open]") { click_on "Cancel" }
    refute_selector "dialog[open]"

    open_multiple(max: 10)
    await_js(%(document.activeElement?.matches("dialog[open] input[type=search]")), message: "the search field did not take the focus")
  end

  test "a single opener still gets one image's keys" do
    titled("Harbour")
    visit_screen(admin_root_path)

    # A multiple opening first: what it changed is put back for the next.
    open_multiple(max: 10)
    within("dialog[open]") { click_on "Cancel" }
    refute_selector "dialog[open]"

    open_stand_in
    within("dialog[open]") do
      assert_selector "h2", exact_text: "Choose an image"
      assert_selector "[role=status]", exact_text: "No image selected"
      click_on "Harbour"
      assert_no_selector "[data-media-pick-order]"
      assert_no_selector "[aria-label*=chosen]"
      click_on "Use image"
    end
    refute_selector "dialog[open]"

    await_js("window.__picked !== null", message: "the opener was never answered")
    picked = page.evaluate_script("window.__picked")
    assert_equal "Harbour", picked["title"]
    assert_equal %w[alt caption id title url], picked.keys.intersection(%w[id url title alt caption]).sort
    assert_nil picked["items"]
  end

  private

  # A library image with a title of its own.
  def titled(title)
    asset = create_media_asset(filename: "tiny.png")
    asset.update_columns(title: title) # version: none (a test's own rows)
    asset
  end

  # What a screen reader names an element, from Chrome's accessibility tree.
  def accessible_name(selector)
    cdp = page.driver.browser.page
    root = cdp.command("DOM.getDocument", depth: 0).dig("root", "nodeId")
    node = cdp.command("DOM.querySelector", nodeId: root, selector: selector).fetch("nodeId")
    # The words appended to a chosen tile stand in a box of their own, so
    # Chrome puts a space before their comma: no screen reader says it.
    cdp.command("Accessibility.getPartialAXTree", nodeId: node, fetchRelatives: false).fetch("nodes").first.dig("name", "value").to_s.squish.gsub(" ,", ",")
  end

  # Enter held down: one press, then the key's repeats, then its release
  # (CDP key events, which `send_keys` cannot repeat).
  def hold_enter(repeats:)
    cdp = page.driver.browser.page
    key = { key: "Enter", code: "Enter", windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13 }
    cdp.command("Input.dispatchKeyEvent", type: "keyDown", text: "\r", **key)
    repeats.times { cdp.command("Input.dispatchKeyEvent", type: "keyDown", text: "\r", autoRepeat: true, **key) }
    cdp.command("Input.dispatchKeyEvent", type: "keyUp", **key)
  end

  # The picker's tile of an image.
  def tile(asset) = "#media-picker-asset-#{asset.id} button"

  # Each tile chosen, with its number, and no other.
  def assert_order(order)
    order.each { |asset, number| assert_selector "#{tile(asset)}[aria-pressed=true] [data-media-pick-order]", exact_text: number.to_s }
    assert_selector "[data-media-pick-order]", count: order.size
  end

  # The Gallery card's stand-in: a button that opens the picker and keeps
  # what it is answered in `window.__picked`.
  def open_stand_in(**detail)
    page.execute_script(<<~JS, detail.to_json)
      let opener = document.getElementById("stand-in-opener")
      if (!opener) {
        opener = document.createElement("button")
        opener.id = "stand-in-opener"
        opener.type = "button"
        opener.textContent = "Stand-in"
        document.body.append(opener)
        opener.addEventListener("media-picker:picked", (event) => { window.__picked = event.detail })
      }
      window.__picked = null
      window.dispatchEvent(new CustomEvent("media-picker:open", { detail: { opener, ...JSON.parse(arguments[0]) } }))
    JS
    assert_selector "dialog[open] #media-picker-place", visible: :all
  end

  def open_multiple(max:, chosen: [], focus: nil)
    open_stand_in(multiple: true, max: max, chosen: chosen, **(focus ? { focus: focus } : {}))
  end

  # Holds every grid request of the picker until `window.__releaseGrid()`,
  # counting them in `window.__gridRequests`.
  def hold_picker_grid
    page.execute_script(<<~JS)
      const original = window.fetch
      window.__gridRequests = 0
      window.__gridHeld = new Promise((release) => { window.__releaseGrid = release })
      window.fetch = (url, options) => {
        if (!String(url?.url || url).includes("picker=1")) return original(url, options)
        window.__gridRequests += 1
        return window.__gridHeld.then(() => original(url, options))
      }
    JS
  end

  # A modal opened from far down a page must stand in the viewport, not at
  # the bottom of the page cut off, with the page behind shifted and a band
  # on top. This opens it in a real browser (1400x900) with the page scrolled down 600px
  # and checks the dialog lies inside the viewport and nothing behind it moved.
  # The page is scrolled to where the Choose image button sits 300px below the
  # viewport top (about 600px down), not to a fixed 600: the editor header is
  # sticky now, and at a fixed offset the button can sit under it, where the
  # driver's click first scrolls the page to reach it -- a scroll of the test's
  # own making, not the picker's.
  test "the picker opens inside the viewport on a scrolled page, and the page behind does not move" do
    page.current_window.resize_to(1400, 900)
    visit_editor(@landing)
    # Make sure there is 600px to scroll whatever the editor's own height is.
    page.execute_script("document.querySelector('main').style.minHeight = '3000px'; window.scrollTo(0, 0)")
    button_top = page.evaluate_script("Math.round(document.querySelector('#page-hero-image-section button').getBoundingClientRect().top)")
    scrolled_to = [ button_top - 300, 1 ].max
    page.execute_script("window.scrollTo(0, #{scrolled_to})")
    assert_equal scrolled_to, page.evaluate_script("Math.round(window.scrollY)")

    within("#page-hero-image-section") { click_on "Choose image" }
    assert_selector "dialog#media-picker[open]"

    box = page.evaluate_script(<<~JS)
      (() => {
        const r = document.getElementById("media-picker").getBoundingClientRect()
        return { top: r.top, left: r.left, bottom: r.bottom, right: r.right,
                 width: window.innerWidth, height: window.innerHeight, scrollY: Math.round(window.scrollY) }
      })()
    JS
    assert_operator box["top"], :>=, 0
    assert_operator box["left"], :>=, 0
    assert_operator box["bottom"], :<=, box["height"]
    assert_operator box["right"], :<=, box["width"]
    assert_equal scrolled_to, box["scrollY"]
  ensure
    page.current_window.resize_to(1400, 1400)
  end

  # The picker's places (the card StudioMediaFolders, D12): the library's
  # places beside the grid, read-only, and the frame opens at the place it
  # showed last in this browser (`cs.media.picker.place`).
  test "the picker browses into a folder, and opens there the next time" do
    client_a = client_folders.last
    logo = in_folder(create_media_asset(filename: "tiny.png"), client_a)
    block = image_block
    visit_editor(@landing)
    editor_path = current_path

    choose_image(block)
    within("dialog[open]") do
      assert_button @asset.title
      assert_button logo.title
      assert_text "Uploads go into no folder"
      # Client A is folded under Clients, as on the Media screen.
      assert_no_link "Client A"
      find("button[aria-label='Unfold Clients']").click
      click_on "Client A"
      assert_place client_a.id
      assert_no_button @asset.title
      assert_button logo.title
      assert_text "Uploads go into Client A"
      assert_selector "a[aria-current=page]", text: "Client A"
      # The rows are read-only.
      assert_no_selector ".admin-tree-row__add, .admin-tree-node__handle", visible: :all
    end
    assert_equal client_a.id.to_s, stored_place
    # The page under the dialog kept its address.
    assert_equal editor_path, current_path
    within("dialog[open]") { click_on "Cancel" }
    refute_selector "dialog[open]"

    choose_image(block)
    within("dialog[open]") do
      assert_place client_a.id
      assert_selector "a[aria-current=page]", text: "Client A"
      assert_text "Uploads go into Client A"
      assert_no_button @asset.title
    end
    pick_from_library(logo)
    assert_eventually { block.reload.media_asset_id == logo.id }
  end

  # Review Focus 5: the folder was deleted in between.
  test "a remembered folder that is gone opens All media and is forgotten" do
    gone = Media::Folder.create!(name: "Old shoot")
    block = image_block
    visit_editor(@landing)
    remember_place(gone.id)
    gone.destroy!

    choose_image(block)
    within("dialog[open]") do
      assert_selector "#media-picker-place[data-media-place='all'][data-media-place-gone]", visible: :all
      assert_selector "a[aria-current=page]", text: "All media"
      assert_button @asset.title
      assert_text "Uploads go into no folder"
      assert_no_link "Old shoot"
    end
    assert_eventually(message: -> { "the gone folder is still remembered: #{stored_place.inspect}" }) { stored_place.nil? }
    pick_from_library(@asset)
    assert_eventually { block.reload.media_asset_id == @asset.id }
  end

  test "storage that throws opens All media and the picker still works" do
    client_a = client_folders.last
    logo = in_folder(create_media_asset(filename: "tiny.png"), client_a)
    block = image_block
    visit_editor(@landing)
    remember_place(client_a.id)
    # Storage refused for the picker's key (a private window, blocked site
    # data): every read and write of it throws.
    page.execute_script(<<~JS, PLACE_KEY)
      const key = arguments[0]
      for (const name of [ "getItem", "setItem", "removeItem" ]) {
        const own = Storage.prototype[name]
        Storage.prototype[name] = function (each, ...rest) {
          if (each === key) throw new DOMException("refused", "SecurityError")
          return own.call(this, each, ...rest)
        }
      }
    JS

    choose_image(block)
    within("dialog[open]") do
      assert_place "all"
      assert_button @asset.title
      find("button[aria-label='Unfold Clients']").click
      click_on "Client A"
      assert_place client_a.id
      assert_no_button @asset.title
    end
    pick_from_library(logo)
    assert_eventually { block.reload.media_asset_id == logo.id }
  end

  test "an upload in the picker lands in the folder shown" do
    client_a = client_folders.last
    block = image_block
    visit_editor(@landing)

    choose_image(block)
    within("dialog[open]") do
      find("button[aria-label='Unfold Clients']").click
      click_on "Client A"
      assert_place client_a.id
      upload = find_button("Upload")
      assert_equal "Uploads go into Client A", find("##{upload['aria-describedby']}").text
      count = ->(place) { "#media-picker-folder-tree [data-media-place-count='#{place}']" }
      assert_selector count.call(client_a.id), text: "", visible: :all
      assert_selector count.call("all"), exact_text: "1", visible: :all
      attach_file "Image file", file_fixture("tiny.png").to_s
      assert_text "1 selected", wait: 10
      # The places' counts follow the answer, Client A's from nothing to 1.
      assert_selector count.call(client_a.id), exact_text: "1"
      assert_selector count.call("all"), exact_text: "2", visible: :all
      assert_selector count.call("none"), exact_text: "1", visible: :all
    end
    uploaded = Media::Asset.where.not(id: @asset.id).sole
    assert_equal client_a.id, uploaded.folder_id
    assert_nil @asset.reload.folder_id
  end

  test "the remembered place is the selected row, scrolled into view" do
    folders = (1..40).map { |n| Media::Folder.create!(name: format("Shoot %02d", n)) }
    block = image_block
    at_window(1400, height: 700) do
      visit_editor(@landing)
      remember_place(folders.last.id)

      choose_image(block)
      within("dialog[open]") do
        assert_place folders.last.id
        assert_selector ".admin-tree-row--selected a[aria-current=page]", text: "Shoot 40"
      end
      await_js(<<~JS, message: "the selected row is not in the list's view")
        (() => {
          const row = document.querySelector("dialog[open] nav .admin-tree-row--selected")
          const list = row?.closest("nav")
          if (!row || list.scrollHeight <= list.clientHeight) return false
          const edge = row.getBoundingClientRect(), box = list.getBoundingClientRect()
          return list.scrollTop > 0 && edge.top >= box.top && edge.bottom <= box.bottom
        })()
      JS
      # Only the list scrolled: the grid's column did not.
      assert_equal 0, page.evaluate_script(%(document.querySelector("dialog[open] ul.admin-media-grid").closest(".overflow-y-auto").scrollTop))
    end
  end

  test "below 640px the places are the select" do
    clients, client_a = client_folders
    logo = in_folder(create_media_asset(filename: "tiny.png"), client_a)
    block = image_block
    visit_editor(@landing)

    choose_image(block)
    at_window(600) do
      within("dialog[open]") do
        assert_no_selector "nav[aria-label=Folders]"
        folder = find_field("Folder", type: "select")
        assert_equal "all", folder.value
        assert_equal [ "all", "none", clients.id.to_s, client_a.id.to_s ], folder.all("option").map(&:value)
        folder.find("option[value='#{client_a.id}']").select_option
        assert_place client_a.id
        assert_no_button @asset.title
        assert_button logo.title
        assert_equal client_a.id.to_s, find_field("Folder", type: "select").value
      end
      # The new select took the focus the old one lost with the frame's body.
      await_js(%(document.activeElement?.id === "media-picker-place-select"), message: "the select lost the focus")
    end
    assert_equal client_a.id.to_s, stored_place
  end

  # Select-then-use (D14): a click selects the tile, Use image confirms.
  def pick_from_library(asset)
    within("dialog[open]") do
      click_on asset.title
      click_on "Use image"
    end
    refute_selector "dialog[open]"
  end

  # Clients, and Client A inside it.
  def client_folders
    clients = Media::Folder.create!(name: "Clients")
    [ clients, Media::Folder.create!(name: "Client A", parent: clients) ]
  end

  def in_folder(asset, folder)
    asset.update_columns(folder_id: folder.id) # version: none (a test's own rows)
    asset
  end

  def image_block = @landing.content_blocks.create!(block_type: "image", position: 0)

  # Opens the picker from the Image block's field and waits for its frame.
  def choose_image(block)
    within("##{Admin::EditorScreen::BlockCardComponent.error_prefix(block)}-image-section") { click_on "Choose image" }
    assert_selector "dialog[open] #media-picker-place", visible: :all
  end

  # The place the frame shows (`#media-picker-place`, inside it).
  def assert_place(place)
    assert_selector "#media-picker-place[data-media-place='#{place}']", visible: :all
  end

  def remember_place(place) = page.execute_script("localStorage.setItem(arguments[0], arguments[1])", PLACE_KEY, place.to_s)

  def stored_place = page.evaluate_script("localStorage.getItem('#{PLACE_KEY}')")
end
