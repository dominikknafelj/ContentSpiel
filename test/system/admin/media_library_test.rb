require "application_system_test_case"

# The Media module's own grid and side panel (media library design spec
# §6, Task 7; round 3 Task 8): a real multi-file upload through the file
# input (`admin--media--upload`), then opening one of the uploaded images and
# setting its German alt text; and the panel's live effect on the tile and the
# segment counts.
class Admin::MediaLibrarySystemTest < ApplicationSystemTestCase
  test "uploading two files by the file input, opening one, and setting a German alt text persists" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))

    visit "/cs-studio/media"
    await_admin_controllers

    # A real, single multi-file selection on the visible file input --
    # `admin--media--upload#filesSelected` fires one POST per file, one at a time
    # (global constraints' own upload ruling), and nothing reloads.
    attach_file("media-upload-input", [ file_fixture("tiny.png").to_s, file_fixture("wide.png").to_s ])

    # One at a time, and no reload: each file's tile becomes the real one in turn.
    assert_selector ".admin-media-grid li[id^=media-asset-]", count: 2, wait: 10
    assert_no_selector "[data-upload-tile]"
    assert_equal 2, Media::Asset.count

    asset = Media::Asset.find_by!(title: "wide")
    click_tile(asset)

    assert_selector "#media-panel" # sanity: the side panel actually opened, beside the grid

    within("nav[aria-label='Languages']") { press "Deutsch" }
    # Waits for the language switch's own full top-level Turbo visit
    # (`data-turbo-frame="_top"`, `Admin::Ui::LanguageTabsComponent`'s own
    # comment) to actually land before typing -- alt/caption have no
    # read-only "original" hint the way a translated column with one would
    # (`Admin::LanguagesSystemTest`'s own comment on why *that* test polls
    # `[data-original-for]` first), so this polls the switcher's own
    # current-locale marker instead; text matched case-insensitively since
    # the switcher's own CSS renders it visually uppercase ("DEUTSCH")
    # while the DOM text is "Deutsch".
    assert_selector "nav[aria-label='Languages'] [aria-current='true']", text: /deutsch/i

    fill_in "Alt", with: "Ein Sonnenuntergang"
    assert_selector "#media-save-status", text: /\A(● )?SAVED( · NOT PUBLISHED)? \d{2}:\d{2}\z/, wait: 5

    assert_alt_eventually(asset, :de, "Ein Sonnenuntergang")
    assert_predicate asset.reload.alt(locale: :en), :blank?
  end

  test "choosing a tile opens the panel and advances the URL; typing an alt text takes NO ALT off the tile and drops the Missing alt count" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    with_locales(%w[en de], default: "en")
    bare = create_media_asset(filename: "tiny.png").tap { |asset| asset.update!(title: "Bare image") }
    described = create_media_asset(filename: "wide.png").tap { |asset| asset.update!(title: "Described image") }
    assert Media::Save.call(described, translations: { "en" => { alt: "A wide view" } }).ok?
    sign_in_via_form(users(:one))

    visit "/cs-studio/media"
    await_admin_controllers
    assert_selector "#media-count-missing_alt", text: "1"
    assert_selector "#media-asset-#{bare.id}", text: "NO ALT"
    assert_no_selector "#media-panel"

    click_tile(bare)

    assert_current_path(/\?selected=#{bare.id}\z/)
    assert_selector "#media-asset-#{bare.id} a[aria-current='true']"

    fill_in "Alt", with: "A bare wall"
    assert_selector "#media-save-status", text: /SAVED/, wait: 5

    assert_no_selector "#media-asset-#{bare.id}", text: "NO ALT", wait: 5
    assert_selector "#media-count-missing_alt", text: "0"
    assert_selector "#media-count-all", text: "2"
    assert_equal "A bare wall", bare.reload.alt(locale: :en)
    # The selection survived: the panel is still there, on the same image.
    assert_selector "#media-panel #media-title[value='Bare image']"

    page.go_back
    assert_no_selector "#media-panel", wait: 5
  end

  test "in the panel a translation tab stacks the original above the field" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    with_locales(%w[en de], default: "en")
    asset = create_media_asset
    assert Media::Save.call(asset, translations: { "en" => { alt: "A wide view" } }).ok?
    sign_in_via_form(users(:one))

    visit "/cs-studio/media?selected=#{asset.id}"
    await_admin_controllers
    within("nav[aria-label='Languages']") { press "Deutsch" }
    assert_selector "nav[aria-label='Languages'] [aria-current='true']", text: /deutsch/i
    assert_selector "#media-panel [data-original-for='alt']"

    width = page.evaluate_script(%(document.querySelector("#media-panel form.admin-translation-form").clientWidth))
    assert_operator width, :<, 824, "the premise: the panel's form is narrower than 824px (was #{width})"
    original_top = page.evaluate_script(%(document.querySelector("#media-panel [data-original-for='alt']").getBoundingClientRect().top))
    field_top = page.evaluate_script(%(document.querySelector("#media-alt").getBoundingClientRect().top))
    assert_operator original_top, :<, field_top - 4, "the original should sit above the field when stacked"
  end

  # Round 3 Task 9: drop images anywhere on the screen. A real OS drag cannot be
  # driven from here, so the page itself builds the `DataTransfer` and fires the
  # same events a drag would (`dragenter`, then `drop`).
  test "dropping files anywhere shows the overlay, then a progress tile for each and the real tile after it, with no reload" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    visit "/cs-studio/media"
    await_admin_controllers
    page.execute_script("window.__noReload = 'still here'")
    hold_uploads

    dispatch_file_drag("dragenter", "tiny.png")
    assert_selector "[data-admin--media--drop-target=overlay]", text: "Drop images to upload", visible: :visible
    dispatch_file_drop("tiny.png")

    assert_no_selector "[data-admin--media--drop-target=overlay]", visible: :visible
    assert_selector "[data-upload-tile]", text: "tiny.png"
    assert_selector "[data-upload-tile]", text: "Uploading…"
    assert_equal 0, Media::Asset.count

    release_uploads
    assert_selector ".admin-media-grid li[id^=media-asset-] a", text: "tiny", wait: 10
    assert_no_selector "[data-upload-tile]"
    assert_selector "#media-count-all", text: "1"
    assert_equal 1, Media::Asset.count
    assert_equal "still here", page.evaluate_script("window.__noReload")
  end

  test "a drop of one good and one refused file: the good one becomes a tile, the refused one keeps its reason and Dismiss, nothing reloads" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    visit "/cs-studio/media"
    await_admin_controllers
    page.execute_script("window.__noReload = 'still here'")

    dispatch_file_drop("fake.png", "tiny.png")

    assert_selector ".admin-media-grid li[id^=media-asset-] a", text: "tiny", wait: 10
    assert_selector "[data-upload-tile]", text: /fake\.png.*PNG, JPEG, GIF, or WEBP/m, wait: 10
    assert_equal 1, Media::Asset.count
    assert_equal "still here", page.evaluate_script("window.__noReload")

    find("[data-upload-tile] button", text: "Dismiss").click
    assert_no_selector "[data-upload-tile]"
    assert_selector ".admin-media-grid li", count: 1
  end

  test "a drag that carries text, and one that Escape ends, never shows the overlay for long" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    visit "/cs-studio/media"
    await_admin_controllers

    page.execute_script(<<~JS)
      const data = new DataTransfer()
      data.setData("text/plain", "just some words")
      document.dispatchEvent(new DragEvent("dragenter", { dataTransfer: data, bubbles: true, cancelable: true }))
    JS
    assert_no_selector "[data-admin--media--drop-target=overlay]", visible: :visible

    dispatch_file_drag("dragenter", "tiny.png")
    assert_selector "[data-admin--media--drop-target=overlay]", visible: :visible
    # Entering and leaving a child (the counted enter/leave) does not flicker it...
    dispatch_file_drag("dragenter", "tiny.png")
    dispatch_file_drag("dragleave", "tiny.png", related: true)
    assert_selector "[data-admin--media--drop-target=overlay]", visible: :visible
    # ...and Escape ends the drag.
    page.driver.browser.keyboard.type(:escape)
    assert_no_selector "[data-admin--media--drop-target=overlay]", visible: :visible
    assert_equal 0, Media::Asset.count
  end

  # Ledger C-M3: a tile's thumbnail dragged within the page carries `Files` too.
  test "a drag that starts in the page never shows the overlay and uploads nothing; a drag from outside afterwards still does" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    asset = create_media_asset(filename: "tiny.png")
    sign_in_via_form(users(:one))
    visit "/cs-studio/media"
    await_admin_controllers

    page.execute_script("document.querySelector('#media-asset-#{asset.id} img').dispatchEvent(new DragEvent('dragstart', { bubbles: true, cancelable: true }))")
    dispatch_file_drag("dragenter", "tiny.png")
    dispatch_file_drag("dragover", "tiny.png")
    assert_no_selector "[data-admin--media--drop-target=overlay]", visible: :visible
    dispatch_file_drop("tiny.png")
    await_frames # the drop handler has run: no tile was made, no upload started
    assert_no_selector "li[data-upload-tile]"
    assert_equal 1, Media::Asset.count

    dispatch_file_drag("dragenter", "tiny.png")
    assert_selector "[data-admin--media--drop-target=overlay]", visible: :visible
    page.driver.browser.keyboard.type(:escape)
  end

  # Task 8 M-5: no wait for the promoted visit (`click_tile` waits for it).
  test "typing into Alt the moment the panel exists is saved and stays in the field" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    asset = create_media_asset(filename: "tiny.png").tap { |a| a.update!(title: "Quick one") }
    sign_in_via_form(users(:one))
    visit "/cs-studio/media"
    await_admin_controllers

    find("#media-asset-#{asset.id} a").click
    find("#media-panel #media-alt").set("Typed at once")
    assert_selector "#media-save-status", text: /SAVED/, wait: 8
    assert_equal "Typed at once", asset.reload.alt(locale: :en)
    assert_equal "Typed at once", find("#media-alt").value
    assert_title(/\AQuick one · Media/)
  end

  # Ledger C-M10 and Task 8's × fallback.
  test "a language tab in the panel keeps the focus at the panel; × with the tile not listed goes to the search" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    with_locales(%w[en de], default: "en")
    asset = create_media_asset(filename: "tiny.png").tap { |a| a.update!(title: "Tabbed") }
    sign_in_via_form(users(:one))
    visit "/cs-studio/media"
    await_admin_controllers
    click_tile(asset)

    within("#media-panel") { click_link "Deutsch" }
    assert_current_path(/locale=de/)
    assert_eventually(message: "focus never came back to the panel") { page.evaluate_script("document.activeElement.id") == "media-panel" }

    visit "/cs-studio/media?q=no-such-image&selected=#{asset.id}"
    await_admin_controllers
    assert_no_selector "#media-asset-#{asset.id}"
    find("#media-panel a[aria-label='Close panel']").click
    assert_no_selector "#media-panel"
    assert_eventually(message: "focus fell to the body") { page.evaluate_script("document.activeElement.name") == "q" }
  end

  test "an upload that finishes while the editor types in the panel leaves the panel and the text alone, and the counts follow" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    existing = create_media_asset(filename: "wide.png").tap { |asset| asset.update!(title: "Existing") }
    sign_in_via_form(users(:one))
    visit "/cs-studio/media"
    await_admin_controllers
    click_tile(existing)
    assert_selector "#media-count-all", text: "1"
    hold_uploads

    fill_in "Alt", with: "Typing while uploading"
    page.execute_script("document.getElementById('media-panel').dataset.same = 'yes'")
    dispatch_file_drop("tiny.png")
    assert_selector "[data-upload-tile]", text: "Uploading…"
    release_uploads

    assert_selector ".admin-media-grid li[id^=media-asset-] a", text: "tiny", wait: 10
    assert_selector "#media-count-all", text: "2"
    assert_selector "#media-count-missing_alt", text: "2"
    assert_selector "#media-panel[data-same=yes]"
    assert_field "Alt", with: "Typing while uploading"
    assert_alt_eventually(existing, :en, "Typing while uploading")
  end

  test "a file still going up when another tile is chosen keeps its progress tile in the new grid, and becomes real when it finishes" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    existing = create_media_asset(filename: "wide.png").tap { |asset| asset.update!(title: "Existing") }
    sign_in_via_form(users(:one))
    visit "/cs-studio/media"
    await_admin_controllers
    hold_uploads

    dispatch_file_drop("tiny.png")
    assert_selector "[data-upload-tile]", text: "Uploading…"
    click_tile(existing)
    assert_selector "[data-upload-tile]", text: "tiny.png"

    release_uploads
    assert_selector ".admin-media-grid li[id^=media-asset-] a", text: "tiny", wait: 10
    assert_no_selector "[data-upload-tile]"
    assert_selector "#media-panel"
  end

  # The Media screen carries the editors' `turbo-cache-control: no-cache`: without
  # it Back restores the cached panel (a form with the base it had when it was
  # cached, and a tile with the NO ALT it had), so the next edit would be told the
  # image "also changed elsewhere" although only this tab touched it.
  test "Back after typing an alt text and choosing another tile shows the saved state, and the next edit is a plain save" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    first = create_media_asset(filename: "tiny.png").tap { |asset| asset.update!(title: "First image") }
    second = create_media_asset(filename: "wide.png").tap { |asset| asset.update!(title: "Second image") }
    sign_in_via_form(users(:one))

    visit "/cs-studio/media"
    await_admin_controllers
    click_tile(first)

    fill_in "Alt", with: "Typed just before leaving"
    click_tile(second) # held by the write queue until the save is out
    assert_selector "#media-panel #media-title[value='Second image']"
    assert_equal "Typed just before leaving", first.reload.alt(locale: :en)

    page.go_back
    assert_selector "#media-panel #media-title[value='First image']", wait: 5
    assert_no_selector "#media-asset-#{first.id}", text: "NO ALT"
    await_admin_controllers

    fill_in "Title", with: "First image, renamed"
    assert_selector "#media-save-status", text: /\A(● )?SAVED( · NOT PUBLISHED)? \d{2}:\d{2}\z/, wait: 5
    assert_equal "First image, renamed", first.reload.title
  end

  test "by keyboard: choosing a tile moves focus into the panel, and closing it returns focus to that tile; a plain load steals none" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    asset = create_media_asset.tap { |record| record.update!(title: "Keyboard image") }
    sign_in_via_form(users(:one))

    visit "/cs-studio/media?selected=#{asset.id}"
    await_admin_controllers
    assert_selector "#media-panel"
    await_frames # a focus move into the panel would be made by `connect()` or the frame's load, both done by now
    assert_not_equal "media-panel", active_element_id, "a plain page load must not move focus into the panel"

    visit "/cs-studio/media"
    await_admin_controllers
    # The keyboard alone: the tile is focused by script and Enter goes to the
    # page, whatever has the focus (`press_enter`). `node.send_keys(:enter)` is
    # NOT that -- Cuprite clicks the node with the mouse first and types
    # afterwards, so the tile was activated twice within a few milliseconds
    # (click, then Enter on the link that was still there), two frame
    # navigations to one URL of which Turbo promotes neither: no `turbo:load`
    # at all, and a test whose outcome depended on which of the two won.
    page.execute_script("document.querySelector('#media-asset-#{asset.id} a').focus()")
    click_frame_link { press_enter }

    assert_eventually(message: "focus never reached the panel") { active_element_id == "media-panel" }

    page.execute_script("document.querySelector(\"a[aria-label='Close panel']\").focus()")
    click_frame_link { press_enter }

    assert_no_selector "#media-panel", wait: 5
    assert_eventually(message: "focus never returned to the tile") do
      page.evaluate_script("document.activeElement.closest('#media-asset-#{asset.id}') !== null")
    end
  end

  # Turbo's snapshot clones progress tiles without listeners; Back must not bring
  # one back as a ghost. The Media index is no-cache now, so these two flows were
  # already covered by that (they pass without the `reattach` change); the third
  # test pins `reattach`'s own sweep for any page that does get restored.
  test "Back after choosing a tile during an upload shows no leftover progress tile" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    existing = create_media_asset(filename: "wide.png").tap { |asset| asset.update!(title: "Existing") }
    sign_in_via_form(users(:one))
    visit "/cs-studio/media"
    await_admin_controllers
    hold_uploads
    dispatch_file_drop("tiny.png")
    assert_selector "[data-upload-tile]", text: "Uploading…"
    click_tile(existing)
    release_uploads
    assert_selector ".admin-media-grid li[id^=media-asset-] a", text: "tiny", wait: 10

    page.go_back
    assert_no_selector "#media-panel", wait: 5
    await_admin_controllers
    assert_no_selector "[data-upload-tile]"
  end

  test "Back after choosing a tile with a refused tile showing leaves exactly one, and its Dismiss works" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    existing = create_media_asset(filename: "wide.png").tap { |asset| asset.update!(title: "Existing") }
    sign_in_via_form(users(:one))
    visit "/cs-studio/media"
    await_admin_controllers
    dispatch_file_drop("fake.png")
    assert_selector "[data-upload-tile]", text: /PNG, JPEG, GIF, or WEBP/, wait: 10
    click_tile(existing)
    assert_selector "[data-upload-tile]", count: 1

    page.go_back
    assert_no_selector "#media-panel", wait: 5
    await_admin_controllers
    assert_selector "[data-upload-tile]", count: 1
    find("[data-upload-tile] button", text: "Dismiss").click
    assert_no_selector "[data-upload-tile]"
  end

  test "a restored grid's ghost progress tiles are removed when the queue re-attaches" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    visit "/cs-studio/media"
    await_admin_controllers
    # A clone, as Turbo's snapshot would leave: no listeners, no live entry.
    page.execute_script(<<~JS)
      const ghost = document.createElement("li")
      ghost.dataset.uploadTile = ""
      ghost.id = "ghost-tile"
      document.querySelector(".admin-media-grid").prepend(ghost)
    JS
    assert_selector "#ghost-tile", visible: :all
    dispatch_file_drop("fake.png")
    assert_selector "[data-upload-tile]", text: /PNG, JPEG/, wait: 10
    assert_no_selector "#ghost-tile", visible: :all
    assert_selector "[data-upload-tile]", count: 1
  end

  # Notes on an image (notes spec §4.4): this screen has no drawer, so the
  # panel shows the notes frame in place, below "Used on" and outside the
  # image's own autosaving form.
  test "the panel takes a note on the image while its fields autosave beside it" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    asset = create_media_asset
    sign_in_via_form(users(:one))
    visit "/cs-studio/media"
    await_admin_controllers
    click_tile(asset)

    assert_selector "#media-panel #media-notes #notes-list"
    assert_no_selector "#media-notes [data-admin--notes--drawer-target=total]"
    # A link inside the notes frame: never promoted to a visit, clicked plainly.
    find("#media-notes a[data-note-new-link]").click
    find("#media-notes #notes-new textarea[name=body]").send_keys("Crop the left edge")
    within("#media-notes #notes-new") { press "Add note" }

    # The thread opens in place, where the list was; the header follows.
    assert_selector "#media-notes [data-note-thread]", text: "Crop the left edge"
    assert_selector "#media-notes h3", text: /NOTES\s+·\s+1 OPEN/i
    assert_equal [ asset, "media" ], Notes::Thread.last.then { |thread| [ thread.subject, thread.origin_view ] }
    assert_selector "#media-panel #media-title"
    assert_writes_settled
    # No drawer was opened for it, and the note wrote nothing of the image.
    assert_no_selector "#notes-drawer", visible: :all

    # The image's own form still saves, and the tile it draws again has the chip.
    fill_in "Title", with: "Left edge"
    assert_selector "#media-save-status", text: /SAVED/, wait: 5
    assert_equal "Left edge", asset.reload.title
    assert_selector "#media-asset-#{asset.id} [data-notes-chip]", text: "1"
    assert_selector "#media-notes [data-note-thread]", text: "Crop the left edge"

    # Back to the list, in place.
    find("#media-notes a[data-note-back]").click
    assert_selector "#media-notes #notes-list a[data-note-row]", text: "Crop the left edge"
  end

  test "a link to an image with a thread opens the panel on that thread, and the tile's chip is accent for the person addressed" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    asset = create_media_asset
    thread = as(users(:two)) { Notes::Start.call(asset, body: "For @[#{users(:one).id}]: too dark") }.record
    sign_in_via_form(users(:one))

    visit "/cs-studio/media"
    await_admin_controllers
    assert_selector "#media-asset-#{asset.id} [data-notes-chip][data-unread]", text: "1"
    # On the image, 6px from its top right corner, on the surface colour.
    box = page.evaluate_script(<<~JS)
      (() => {
        const chip = document.querySelector("#media-asset-#{asset.id} [data-notes-chip]").getBoundingClientRect()
        const image = document.querySelector("#media-asset-#{asset.id} img").getBoundingClientRect()
        return [ Math.round(chip.top - image.top), Math.round(image.right - chip.right), Math.round(chip.height) ]
      })()
    JS
    assert_equal [ 6, 6, 20 ], box

    visit "/cs-studio/media?selected=#{asset.id}&thread=#{thread.id}"
    await_admin_controllers

    assert_selector "#media-panel #media-notes #note-thread-#{thread.id}", text: "too dark"
  end

  test "a link to a thread that is gone opens the panel on the image's notes, with a sentence and no error" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    asset = create_media_asset
    kept, gone = as(users(:two)) { [ "Keep the sky", "Too dark" ].map { |body| Notes::Start.call(asset, body: body).record } }
    stale = gone.id
    gone.destroy!
    sign_in_via_form(users(:one))

    visit "/cs-studio/media?selected=#{asset.id}&thread=#{stale}"
    await_admin_controllers

    # The JavaScript error collector fails this test on "Content missing".
    assert_selector "#media-panel #media-notes #notes-list [role=status]", text: "This note is gone"
    assert_selector "#media-notes a#note-row-#{kept.id}", text: "Keep the sky"
    assert_no_text "Content missing"
  end

  private

  def active_element_id = page.evaluate_script("document.activeElement && document.activeElement.id")

  # Holds every upload's request in the page until `release_uploads`, so a test
  # sees the progress tiles instead of whatever the timing gives it.
  def hold_uploads
    page.execute_script(<<~JS)
      const send = XMLHttpRequest.prototype.send
      window.__uploadsHeld = new Promise((release) => { window.__releaseUploads = release })
      XMLHttpRequest.prototype.send = function (body) { window.__uploadsHeld.then(() => send.call(this, body)) }
    JS
  end

  def release_uploads
    page.execute_script("window.__releaseUploads()")
  end

  # A `DataTransfer` carrying real `File`s built from fixture bytes, in the page.
  def files_script(*names)
    builders = names.map do |name|
      bytes = Base64.strict_encode64(file_fixture(name).binread)
      %(data.items.add(new File([Uint8Array.from(atob("#{bytes}"), (c) => c.charCodeAt(0))], "#{name}", { type: "image/png" })))
    end
    "const data = new DataTransfer(); #{builders.join("; ")};"
  end

  def dispatch_file_drag(type, name, related: false)
    page.execute_script("#{files_script(name)} document.body.dispatchEvent(new DragEvent('#{type}', { dataTransfer: data, bubbles: true, cancelable: true, relatedTarget: #{related ? "document.body" : "null"} }))")
  end

  def dispatch_file_drop(*names)
    page.execute_script("#{files_script(*names)} document.querySelector('h1').dispatchEvent(new DragEvent('drop', { dataTransfer: data, bubbles: true, cancelable: true }))")
  end

  # Enter, to whatever has the focus -- no click first (see the keyboard test).
  def press_enter = page.driver.browser.keyboard.type(:Enter)

  # Clicks a tile and waits until the panel is open AND Turbo has finished with
  # the click (`click_frame_link`, which says why): a test that clicked or typed
  # before that would have its visit superseded (a language tab) or its text
  # replaced (a field).
  def click_tile(asset)
    click_frame_link { find("#media-asset-#{asset.id} a").click }
    assert_selector "#media-panel", wait: 5
    await_admin_controllers
  end

  # Same "poll the record, not the status text" reasoning `Admin
  # ::GroupsSystemTest#assert_speakers_eventually` gives its own: the
  # status line's own "Saved HH:MM" text already proved a save landed, but
  # only reading the field back off the record proves it landed with
  # *this* value, in *this* locale.
  def assert_alt_eventually(asset, locale, value)
    assert_eventually(wait: 5, message: -> { "expected alt(locale: #{locale}) to become #{value.inspect}, got #{asset.reload.alt(locale: locale).inspect}" }) do
      asset.reload.alt(locale: locale) == value
    end
  end
end
