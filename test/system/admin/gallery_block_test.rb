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

  def titled(title) = create_media_asset.tap { |asset| asset.update!(title: title) }

  def gallery(ids = []) = @page.content_blocks.create!(block_type: "gallery", position: 0, settings: { "images" => ids })

  def card(block) = "#content_block_#{block.id}"

  def row(asset) = "[data-admin--editor--gallery-target=row][data-asset-id='#{asset.id}']"

  def handle(asset) = "#{row(asset)} .admin-gallery-row__handle"

  def shown_order(block) = page.all("#{card(block)} [data-admin--editor--gallery-target=row]").map { |element| element["data-asset-id"].to_i }

  def stored(block) = block.reload.settings["images"]

  def status(block) = find("#{card(block)} [data-admin--editor--gallery-target=status]")

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

    # The keyboard: Space picks Crowd up, Up moves it, Space drops it.
    find(handle(crowd)).click
    keyboard.type(:space)
    assert_equal "Picked up Crowd, image 3 of 3. Up and Down Arrow move it, Space drops it, Escape puts it back.", status(block).text
    keyboard.type(:up)
    assert_equal "Moved to 2 of 3.", status(block).text
    keyboard.type(:space)
    assert_equal "Dropped at 2 of 3.", status(block).text
    assert_eventually(message: "the keyboard move was never saved") { stored(block) == [ harbour.id, crowd.id, forest.id ] }

    # Escape puts a picked row back, and nothing is written.
    keyboard.type(:space)
    keyboard.type(:up)
    keyboard.type(:escape)
    assert_equal "Cancelled. Crowd is back where it was.", status(block).text
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
  end
end
