require "application_system_test_case"

# The one media picker (media library design spec §6, Task 8):
# `Media::PickerComponent`, a modal with a Library tab (search and pick) and
# an Upload tab, opened from the page hero field, an image block's image
# field and the rich-text editor's Image button -- each of which receives
# the picked asset's id and stores it (a hidden `hero_media_asset_id` /
# `media_asset_id` input autosave sends, or an `image{asset_id}` node).
#
# Native clicks throughout (Cuprite's own `click`), not
# `ApplicationSystemTestCase#press`'s scripted one: opening a modal
# `<dialog>`, moving focus into it and handing it back afterwards are
# exactly what these tests are about, and a scripted `element.click()`
# never focuses the button it clicks the way a real pointer click does.
class Admin::MediaPickerSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))

    # `wide.png` is 3000x2000, so every variant width applies; processed
    # up front so the public page's `srcset` has something to list.
    @asset = create_media_asset(filename: "wide.png")
    @asset.file.analyze
    perform_enqueued_jobs

    @landing = create_page(title: "Landing")
    assert Pages::Save.call(@landing, attributes: { page_type: "landing" }).ok?
  end

  test "one library image as hero, image block and rich text is listed under Used on, and removing the hero drops its usage" do
    block = @landing.content_blocks.create!(block_type: "image", position: 0)
    post = create_post(title: "Notes")
    @asset.update!(alt: "A wide view", caption: "Wide")

    # Hero: choose the library image. The hero's alt override now shows the
    # image's own default as its placeholder.
    visit_editor
    within("#page-hero-image-section") { click_on "Choose image" }
    pick_from_library(@asset)
    within("#page-hero-image-section") { assert_button "Change image" }
    assert_selector "#page-hero_alt[placeholder='A wide view']"
    assert_eventually { @landing.reload.hero_media_asset_id == @asset.id }

    # The public page renders it responsively.
    visit "/landing"
    assert_selector "header img[src='#{@asset.src}'][srcset*='480w']"

    # Image block: the same image.
    visit_editor
    within("##{Admin::BlockCardComponent.error_prefix(block)}-image-section") { click_on "Choose image" }
    pick_from_library(@asset)
    assert_eventually { block.reload.media_asset_id == @asset.id }

    # Rich text: the Image button opens the same picker and inserts an
    # `image{asset_id}` node.
    visit "/cs-studio/posts/#{post.id}"
    await_admin_controllers
    find(".ProseMirror").click
    press_insert "Image"
    # Picking opens the image dialog (Task 13), so not `pick_from_library`,
    # which waits for every dialog to close.
    within("dialog[open]") { click_on @asset.title }
    assert_selector "dialog#rich-text-image-dialog[open]"
    # The per-use fields show the image's own defaults as placeholders
    # (fix round 1, I1).
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
    visit_editor
    within("#page-hero-image-section") { click_on "Remove image" }
    within("#page-hero-image-section") { assert_button "Choose image" }
    assert_eventually { @landing.reload.hero_media_asset_id.nil? }

    visit "/cs-studio/media?selected=#{@asset.id}"
    assert_link "Image block — page “Landing”"
    assert_no_link "Hero image — page “Landing”"
    assert Media::Asset.exists?(@asset.id)
  end

  test "an upload through the picker's Upload tab shows errors inline, then lands in an image block" do
    block = @landing.content_blocks.create!(block_type: "image", position: 0)
    visit_editor

    within("##{Admin::BlockCardComponent.error_prefix(block)}-image-section") { click_on "Choose image" }
    within("dialog[open]") do
      click_on "Upload"
      attach_file "Image file", file_fixture("fake.png").to_s
      assert_selector "[role=alert]", text: /PNG, JPEG, GIF, or WEBP/
    end
    assert_equal 1, Media::Asset.count

    within("dialog[open]") { attach_file "Image file", file_fixture("tiny.png").to_s }
    refute_selector "dialog[open]"

    within("##{Admin::BlockCardComponent.error_prefix(block)}-image-section") { assert_button "Change image" }
    uploaded = Media::Asset.where.not(id: @asset.id).sole
    assert_equal "tiny", uploaded.title
    assert_eventually { block.reload.media_asset_id == uploaded.id }
  end

  # Fix round 1 (I2), with a realistic trigger: the image is deleted
  # between opening the picker and picking it. The save is refused
  # ("doesn't exist"), the field goes back to the stored hero with the
  # message showing, and the next autosave doesn't resend the refused id.
  test "picking an image deleted meanwhile is refused and the field shows the stored hero again" do
    stored = create_media_asset(filename: "tiny.png")
    assert Pages::Save.call(@landing, attributes: { hero_media_asset_id: stored.id }).ok?
    doomed = create_media_asset(filename: "medium.png")
    visit_editor

    within("#page-hero-image-section") { click_on "Change image" }
    within("dialog[open]") { assert_button doomed.title }
    assert delete_for_good(doomed)
    pick_from_library(doomed)

    # Waited for outside `within` first (final fix wave): the refusal
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
    visit_editor

    within("#page-hero-image-section") { click_on "Choose image" }
    assert_selector "dialog[open]"

    find("dialog[open]").send_keys(:escape)

    refute_selector "dialog[open]"
    assert_selector "#page-hero-image-section button:focus", text: "Choose image"
    assert_nil @landing.reload.hero_media_asset_id
  end

  test "the Library tab searches the library" do
    other = create_media_asset(filename: "tiny.png")
    visit_editor

    within("#page-hero-image-section") { click_on "Choose image" }
    within("dialog[open]") do
      assert_button other.title
      fill_in "Search images", with: "wid"
      click_on "Search"
      assert_no_button other.title
      assert_button @asset.title
    end
  end

  # The picker's height changes while it is open -- the Library frame is empty
  # until its request answers, and the Upload panel is shorter than a loaded
  # library -- and a centred dialog moved its tab row with every change (112px
  # up when the library arrived). A click aimed at "Upload" just after opening
  # then landed on the library that had slid under the pointer and the tab
  # never switched: CI's "Unable to find visible file field "Image file"", one
  # run in ten. The picker hangs from a fixed top edge now (`.admin-media-picker`),
  # so the tabs stay put. The library's answer is held back here until the
  # first measurement is taken, so the test sees both states every time
  # instead of whichever the timing gives it.
  test "the picker's tabs stay where they are when the library arrives and when the tab changes" do
    visit_editor
    page.execute_script(<<~JS)
      const original = window.fetch
      window.__libraryHeld = new Promise((release) => { window.__releaseLibrary = release })
      window.fetch = (url, options) => {
        if (!String(url?.url || url).includes("picker=1")) return original(url, options)
        return window.__libraryHeld.then(() => original(url, options))
      }
    JS
    tab_top = -> { page.evaluate_script("document.getElementById('media-picker-upload-tab').getBoundingClientRect().top") }

    within("#page-hero-image-section") { click_on "Choose image" }
    assert_selector "dialog#media-picker[open]"
    assert_no_selector "#media-picker-library *", visible: :all, wait: 0.5
    before_library = tab_top.call

    page.execute_script("window.__releaseLibrary()")
    within("dialog[open]") { assert_button @asset.title }
    assert_equal before_library, tab_top.call, "the tab row moved when the library loaded"

    within("dialog[open]") do
      click_on "Upload"
      assert_field "Image file"
    end
    assert_equal before_library, tab_top.call, "the tab row moved when the tab changed"
  end

  private

  # Round 1 second review: Design's screenshot showed the picker at the bottom
  # of the page, cut off, with the page behind shifted and a black band on top.
  # This opens it in a real browser (1400x900) with the page scrolled down 600px
  # and checks the dialog lies inside the viewport and nothing behind it moved.
  # The page is scrolled to where the Choose image button sits 300px below the
  # viewport top (about 600px down), not to a fixed 600: the editor header is
  # sticky now, and at a fixed offset the button can sit under it, where the
  # driver's click first scrolls the page to reach it -- a scroll of the test's
  # own making, not the picker's.
  test "the picker opens inside the viewport on a scrolled page, and the page behind does not move" do
    page.driver.resize(1400, 900)
    visit_editor
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
    page.driver.resize(1400, 1400)
  end

  def visit_editor
    visit "/cs-studio/pages/#{@landing.id}"
    await_admin_controllers
  end

  def pick_from_library(asset)
    within("dialog[open]") { click_on asset.title }
    refute_selector "dialog[open]"
  end

  # Polls the database rather than the save-status line: a hidden input's
  # debounced autosave shows "Saved" too, but only the record proves the
  # right value landed.
  def assert_eventually(timeout: 5)
    deadline = Time.current + timeout
    until yield
      raise Minitest::Assertion, "condition never became true" if Time.current > deadline

      sleep 0.1
    end
  end
end
