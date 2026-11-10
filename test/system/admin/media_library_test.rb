require "application_system_test_case"

# The Media module's own grid and the chosen image's rail: a real multi-file
# upload through the file input (`admin--media--upload`), then opening one of
# the uploaded images and setting its German alt text; the panel's live effect
# on the tile and the segment counts; and the rail at the library's widths,
# with its tabs, its Close and Escape.
class Admin::MediaLibrarySystemTest < ApplicationSystemTestCase
  test "uploading two files by the file input, opening one, and setting a German alt text persists" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))

    visit_screen "/cs-studio/media"

    # A real, single multi-file selection on the visible file input --
    # `admin--media--upload#filesSelected` fires one POST per file, one at a time
    # and nothing reloads.
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

  test "uploading by the file input into a library that already has an image, whose drop zone is hidden, adds the tile" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    existing = create_media_asset(filename: "wide.png").tap { |asset| asset.update!(title: "Existing") }
    sign_in_via_form(users(:one))
    visit_screen "/cs-studio/media"
    assert_selector "#media-asset-#{existing.id}"

    attach_file("media-upload-input", file_fixture("tiny.png").to_s, visible: :all)
    assert_selector "#media-count-all", text: "2"
  end

  test "choosing a tile opens the panel and advances the URL; typing an alt text takes No alt off the tile and drops the Missing alt count" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    with_locales(%w[en de], default: "en")
    bare = create_media_asset(filename: "tiny.png").tap { |asset| asset.update!(title: "Bare image") }
    described = create_media_asset(filename: "wide.png").tap { |asset| asset.update!(title: "Described image") }
    assert Media::Save.call(described, translations: { "en" => { alt: "A wide view" } }).ok?
    sign_in_via_form(users(:one))

    visit_screen "/cs-studio/media"
    assert_selector "#media-count-missing_alt", text: "1"
    assert_selector "#media-asset-#{bare.id}", text: "No alt"
    assert_no_selector "#media-panel"

    click_tile(bare)

    assert_current_path(/\?selected=#{bare.id}\z/)
    assert_selector "#media-asset-#{bare.id} a[aria-current='true']"

    fill_in "Alt", with: "A bare wall"
    assert_selector "#media-save-status", text: /SAVED/, wait: 5

    assert_no_selector "#media-asset-#{bare.id}", text: "No alt", wait: 5
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

    visit_screen "/cs-studio/media?selected=#{asset.id}"
    within("nav[aria-label='Languages']") { press "Deutsch" }
    assert_selector "nav[aria-label='Languages'] [aria-current='true']", text: /deutsch/i
    assert_selector "#media-panel [data-original-for='alt']"

    width = page.evaluate_script(%(document.querySelector("#media-panel form.admin-translation-form").clientWidth))
    assert_operator width, :<, 824, "the premise: the panel's form is narrower than 824px (was #{width})"
    original_top = page.evaluate_script(%(document.querySelector("#media-panel [data-original-for='alt']").getBoundingClientRect().top))
    field_top = page.evaluate_script(%(document.querySelector("#media-alt").getBoundingClientRect().top))
    assert_operator original_top, :<, field_top - 4, "the original should sit above the field when stacked"
  end

  # A tile's look is `.admin-tile`'s: elevation 1 at rest, 2 under the
  # pointer, and the chosen one keeps 1 with the accent outline 2px out. The
  # figures are read against the tokens resolved in the same page.
  test "a tile rises under the pointer, and the chosen one has the accent outline 2px out" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    chosen = create_media_asset(filename: "tiny.png")
    other = create_media_asset(filename: "wide.png")
    sign_in_via_form(users(:one))

    visit_screen "/cs-studio/media?selected=#{chosen.id}"
    find("h1").hover
    shadow_1, shadow_2, accent = token_values("box-shadow: var(--cs-shadow-1)", "box-shadow: var(--cs-shadow-2)", "color: var(--cs-accent)")
    assert_not_equal shadow_1, shadow_2, "the premise: the two elevations differ"

    assert_equal [ shadow_1, "none" ], tile_look(other).values_at("shadow", "outlineStyle")
    assert_equal({ "shadow" => shadow_1, "outlineStyle" => "solid", "outlineWidth" => "2px", "outlineOffset" => "2px", "outlineColor" => accent, "borderWidth" => "0px" },
      tile_look(chosen))

    find("#media-asset-#{other.id} a").hover
    assert_eventually(message: -> { "the hovered tile's shadow is #{tile_look(other)["shadow"]}" }) { tile_look(other)["shadow"] == shadow_2 }
    assert_equal "none", tile_look(other)["outlineStyle"]
  end

  # Drop images anywhere on the screen. A real OS drag cannot be
  # driven from here, so the page itself builds the `DataTransfer` and fires the
  # same events a drag would (`dragenter`, then `drop`).
  test "dropping files anywhere shows the overlay, then a progress tile for each and the real tile after it, with no reload" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    visit_screen "/cs-studio/media"
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
    visit_screen "/cs-studio/media"
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
    visit_screen "/cs-studio/media"

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

  # A tile's thumbnail dragged within the page carries `Files` too.
  test "a drag that starts in the page never shows the overlay and uploads nothing; a drag from outside afterwards still does" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    asset = create_media_asset(filename: "tiny.png")
    sign_in_via_form(users(:one))
    visit_screen "/cs-studio/media"

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

  # No wait for the promoted visit (`click_tile` waits for it).
  test "typing into Alt the moment the panel exists is saved and stays in the field" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    asset = create_media_asset(filename: "tiny.png").tap { |a| a.update!(title: "Quick one") }
    sign_in_via_form(users(:one))
    visit_screen "/cs-studio/media"

    find("#media-asset-#{asset.id} a").click
    find("#media-panel #media-alt").set("Typed at once")
    assert_selector "#media-save-status", text: /SAVED/, wait: 8
    assert_equal "Typed at once", asset.reload.alt(locale: :en)
    assert_equal "Typed at once", find("#media-alt").value
    assert_title(/\AQuick one · Media/)
  end

  # A language tab keeps the focus in the panel, and Close falls back to the search.
  test "a language tab in the panel keeps the focus at the panel; Close with the tile not listed goes to the search" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    with_locales(%w[en de], default: "en")
    asset = create_media_asset(filename: "tiny.png").tap { |a| a.update!(title: "Tabbed") }
    sign_in_via_form(users(:one))
    visit_screen "/cs-studio/media"
    click_tile(asset)

    within("#media-panel") { click_link "Deutsch" }
    assert_current_path(/locale=de/)
    assert_eventually(message: "focus never came back to the panel") { page.evaluate_script("document.activeElement.id") == "media-panel" }

    visit_screen "/cs-studio/media?q=no-such-image&selected=#{asset.id}"
    assert_no_selector "#media-asset-#{asset.id}"
    find("#media-rail a[aria-label='Close panel']").click
    assert_no_selector "#media-panel"
    assert_eventually(message: "focus fell to the body") { page.evaluate_script("document.activeElement.name") == "q" }
  end

  test "an upload that finishes while the editor types in the panel leaves the panel and the text alone, and the counts follow" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    existing = create_media_asset(filename: "wide.png").tap { |asset| asset.update!(title: "Existing") }
    sign_in_via_form(users(:one))
    visit_screen "/cs-studio/media"
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
    visit_screen "/cs-studio/media"
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
  # cached, and a tile with the No alt it had), so the next edit would be told the
  # image "also changed elsewhere" although only this tab touched it.
  test "Back after typing an alt text and choosing another tile shows the saved state, and the next edit is a plain save" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    first = create_media_asset(filename: "tiny.png").tap { |asset| asset.update!(title: "First image") }
    second = create_media_asset(filename: "wide.png").tap { |asset| asset.update!(title: "Second image") }
    sign_in_via_form(users(:one))

    visit_screen "/cs-studio/media"
    click_tile(first)

    fill_in "Alt", with: "Typed just before leaving"
    click_tile(second) # held by the write queue until the save is out
    assert_selector "#media-panel #media-title[value='Second image']"
    assert_equal "Typed just before leaving", first.reload.alt(locale: :en)

    page.go_back
    assert_selector "#media-panel #media-title[value='First image']", wait: 5
    assert_no_selector "#media-asset-#{first.id}", text: "No alt"
    await_admin_controllers

    fill_in "Title", with: "First image, renamed"
    assert_selector "#media-save-status", text: /\A(● )?SAVED( · NOT PUBLISHED)? \d{2}:\d{2}\z/, wait: 5
    assert_equal "First image, renamed", first.reload.title
  end

  test "by keyboard: choosing a tile moves focus into the panel, and closing it returns focus to that tile; a plain load steals none" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    asset = create_media_asset.tap { |record| record.update!(title: "Keyboard image") }
    sign_in_via_form(users(:one))

    visit_screen "/cs-studio/media?selected=#{asset.id}"
    assert_selector "#media-panel"
    await_frames # a focus move into the panel would be made by `connect()` or the frame's load, both done by now
    assert_not_equal "media-panel", active_element_id, "a plain page load must not move focus into the panel"

    visit_screen "/cs-studio/media"
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
    visit_screen "/cs-studio/media"
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
    visit_screen "/cs-studio/media"
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
    visit_screen "/cs-studio/media"
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

  # Notes on an image: this screen has no drawer, so the
  # panel shows the notes frame in place, below "Used on" and outside the
  # image's own autosaving form.
  test "the panel takes a note on the image while its fields autosave beside it" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    asset = create_media_asset
    sign_in_via_form(users(:one))
    visit_screen "/cs-studio/media"
    click_tile(asset)

    assert_selector "#media-rail #media-notes #notes-list"
    assert_no_selector "#media-notes [data-admin--notes--drawer-target=total]"
    # With no thread the field for a note is ready under the empty line.
    assert_selector "#media-notes #notes-new [data-notes-empty]", text: "No notes on this image yet."
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

    visit_screen "/cs-studio/media"
    assert_selector "#media-asset-#{asset.id} [data-notes-chip][data-unread]", text: "1 new"
    # On the image, 6px from its top right corner, on the surface colour.
    box = page.evaluate_script(<<~JS)
      (() => {
        const chip = document.querySelector("#media-asset-#{asset.id} [data-notes-chip]").getBoundingClientRect()
        const image = document.querySelector("#media-asset-#{asset.id} img").getBoundingClientRect()
        return [ Math.round(chip.top - image.top), Math.round(image.right - chip.right), Math.round(chip.height) ]
      })()
    JS
    assert_equal [ 6, 6, 20 ], box

    visit_screen "/cs-studio/media?selected=#{asset.id}&thread=#{thread.id}"

    assert_selector "#media-rail #media-notes #note-thread-#{thread.id}", text: "too dark"
  end

  test "a link to a thread that is gone opens the panel on the image's notes, with a sentence and no error" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    asset = create_media_asset
    kept, gone = as(users(:two)) { [ "Keep the sky", "Too dark" ].map { |body| Notes::Start.call(asset, body: body).record } }
    stale = gone.id
    gone.destroy!
    sign_in_via_form(users(:one))

    visit_screen "/cs-studio/media?selected=#{asset.id}&thread=#{stale}"

    # The JavaScript error collector fails this test on "Content missing".
    assert_selector "#media-rail #media-notes #notes-list [role=status]", text: "This note is gone"
    assert_selector "#media-notes a#note-row-#{kept.id}", text: "Keep the sky"
    assert_no_text "Content missing"
  end

  # Review Focus 1: Escape belongs to the innermost thing that takes it.
  test "Escape closes the rail and puts the focus on the tile; Escape in the alt field, in the notes' composer or in the trash dialog does not, and the alt text typed is saved" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    asset = create_media_asset.tap { |record| record.update!(title: "Escape image") }
    sign_in_via_form(users(:one))
    visit_screen "/cs-studio/media"
    click_tile(asset)

    find("#media-alt").send_keys("Kept while Escape is pressed", :escape)
    assert_selector "#media-rail #media-panel"
    assert_equal "Kept while Escape is pressed", find("#media-alt").value
    assert_alt_eventually(asset, :en, "Kept while Escape is pressed")
    assert_writes_settled

    find("#media-notes #notes-new textarea[name=body]").send_keys("Half a note", :escape)
    assert_selector "#media-rail #media-panel"

    within("#media-panel") { press "Move to trash…" }
    assert_selector "dialog#delete-media-#{asset.id}[open]"
    keyboard.type(:escape)
    assert_no_selector "dialog#delete-media-#{asset.id}[open]"
    assert_selector "#media-rail #media-panel"

    page.execute_script("document.getElementById('media-panel').focus()")
    click_frame_link { keyboard.type(:escape) }
    assert_no_selector "#media-rail", wait: 5
    assert_current_path("/cs-studio/media")
    assert_eventually(message: "focus never returned to the tile") do
      page.evaluate_script("document.activeElement.closest('#media-asset-#{asset.id}') !== null")
    end
    assert_alt_eventually(asset, :en, "Kept while Escape is pressed")
  end

  # Review Focus 2: the library's own width decides, not the window's.
  test "the library docks the rail at 1200px of its own width, keeps the 340px card from 760px and stacks under the grid below; the notes frame is in the page once" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    asset = create_media_asset.tap { |record| record.update!(title: "Wide image") }
    sign_in_via_form(users(:one))

    at_library(1200, "/cs-studio/media?selected=#{asset.id}") do
      assert_rail_docked
      rail = box("#media-rail")
      grid = box(".admin-media-library__main")
      assert_in_delta 360, rail[2] - rail[0], 1, "docked, the rail is the rail's width"
      assert_in_delta grid[2] + 28, rail[0], 1, "and stands the rail's gap right of the grid"
      assert_selector "#media-rail [role=tablist]", visible: :visible
      assert_selector "#media-rail-panel-image", visible: :visible
      assert_selector "#media-rail-panel-notes", visible: :hidden
      assert_equal 1, page.evaluate_script("document.querySelectorAll('turbo-frame#notes').length")
      close = box("#media-rail > a[aria-label='Close panel']")
      assert_operator rail[2] - close[2], :<=, 16, "Close stands at the rail's right"
      assert_operator close[1] - rail[1], :<=, 16, "and at its top"
      assert_equal rail_ground, page.evaluate_script("getComputedStyle(document.getElementById('media-rail')).backgroundColor")
    end

    at_library(1199, "/cs-studio/media?selected=#{asset.id}") do
      assert_rail_docked(false)
      rail = box("#media-rail")
      assert_in_delta 340, rail[2] - rail[0], 1, "below the threshold the card is 340px"
      assert_selector "#media-rail [role=tablist]", visible: :hidden
      assert_selector "#media-rail-panel-image", visible: :visible
      assert_selector "#media-rail-panel-notes #media-notes h3", visible: :visible, text: /NOTES/i
      assert_equal 1, page.evaluate_script("document.querySelectorAll('turbo-frame#notes').length")
      assert_operator box("#media-rail-panel-notes")[1], :>, box("#media-rail-panel-image")[3], "the notes stand under the image's panel"
    end

    at_window(760) do
      visit_screen "/cs-studio/media?selected=#{asset.id}"
      assert_operator library_width, :<, 760
      assert_operator box("#media-rail")[1], :>=, box(".admin-media-library__main")[3], "a narrow library stacks the rail under the grid"
      assert_equal 1, page.evaluate_script("document.querySelectorAll('turbo-frame#notes').length")
    end
  end

  test "a thread link opens the Notes tab where the rail docks and the Notes section where it does not; choosing another tile keeps the tab" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    asset = create_media_asset.tap { |record| record.update!(title: "Threaded") }
    other = create_media_asset.tap { |record| record.update!(title: "Another") }
    thread = as(users(:two)) { Notes::Start.call(asset, body: "Too dark here") }.record
    sign_in_via_form(users(:one))

    at_library(1200, "/cs-studio/media?selected=#{asset.id}&thread=#{thread.id}") do
      assert_rail_docked
      assert_selector "#media-rail-tab-notes[aria-selected=true]"
      assert_selector "#media-rail-panel-notes #note-thread-#{thread.id}", visible: :visible, text: "Too dark here"
      assert_selector "#media-rail-panel-image", visible: :hidden

      click_frame_link { find("#media-asset-#{other.id} a").click }
      assert_current_path(/selected=#{other.id}/)
      assert_selector "#media-panel-title", visible: :all, text: "Another"
      assert_selector "#media-rail-tab-notes[aria-selected=true]"
      assert_selector "#media-rail-panel-notes", visible: :visible
      assert_selector "#media-rail-panel-image", visible: :hidden
      assert_eventually(message: "the focus fell to the body") { page.evaluate_script("document.activeElement.id") == "media-rail-tab-notes" }
    end

    at_library(1199, "/cs-studio/media?selected=#{asset.id}&thread=#{thread.id}") do
      assert_rail_docked(false)
      assert_selector "#media-rail-panel-notes #note-thread-#{thread.id}", visible: :visible, text: "Too dark here"
      assert_selector "#media-rail-panel-image #media-panel", visible: :visible
    end
  end

  test "Image and Notes are tabs where the rail docks: arrows move between them, Home and End go to the ends, and the Notes tab's bubble says 2 new while unread" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    asset = create_media_asset.tap { |record| record.update!(title: "Tabbed rail") }
    as(users(:two)) { 2.times { |i| Notes::Start.call(asset, body: "For @[#{users(:one).id}]: look #{i}") } }
    sign_in_via_form(users(:one))

    at_library(1300, "/cs-studio/media?selected=#{asset.id}") do
      assert_rail_docked
      image_tab, notes_tab = "#media-rail-tab-image", "#media-rail-tab-notes"
      assert_selector "#{image_tab}[aria-selected=true][tabindex='0']", text: "Image"
      assert_selector "#{notes_tab} [data-tab-count][data-unread]", text: "2 new", exact_text: true
      bubble = page.evaluate_script("(() => { const style = getComputedStyle(document.querySelector('#{notes_tab} [data-tab-count]')); return [ style.backgroundColor, style.color ] })()")
      assert_equal token_colors("var(--cs-accent)", "var(--cs-on-accent)"), bubble, "unread, the bubble is the accent's"

      page.execute_script("document.querySelector('#{image_tab}').focus()")
      keyboard.type(:right)
      assert_selector "#{notes_tab}[aria-selected=true][tabindex='0']"
      assert focus_is_on(notes_tab)
      assert_selector "#media-rail-panel-notes", visible: :visible
      assert_selector "#media-rail-panel-image", visible: :hidden
      keyboard.type(:right)
      assert_selector "#{image_tab}[aria-selected=true]"
      assert focus_is_on(image_tab)
      keyboard.type(:end)
      assert_selector "#{notes_tab}[aria-selected=true]"
      assert focus_is_on(notes_tab)
      keyboard.type(:home)
      assert_selector "#{image_tab}[aria-selected=true]"
      assert focus_is_on(image_tab)
      keyboard.type(:left)
      assert_selector "#{notes_tab}[aria-selected=true]"
      assert focus_is_on(notes_tab)
    end
  end

  private

  def keyboard = page.driver.browser.keyboard

  def focus_is_on(selector) = page.evaluate_script("document.activeElement === document.querySelector(#{selector.to_json})")

  # `[left, top, right, bottom]` of the first element the selector finds.
  def box(selector)
    page.evaluate_script("(() => { const box = document.querySelector(#{selector.to_json}).getBoundingClientRect(); return [ box.left, box.top, box.right, box.bottom ] })()")
  end

  def library_width = page.evaluate_script("document.getElementById('media-library').getBoundingClientRect().width")

  def assert_rail_docked(docked = true)
    assert_eventually(message: "the rail is #{docked ? "not " : ""}docked") { page.evaluate_script("document.getElementById('media-rail').hasAttribute('data-rail-docked')") == docked }
  end

  def rail_ground = token_colors("var(--cs-rail)").first

  # Each colour's computed value on a probe inside the content frame.
  def token_colors(*values)
    page.evaluate_script(<<~JS)
      #{values.to_json}.map((value) => {
        const probe = document.createElement("div")
        probe.style.color = value
        document.querySelector("#content").append(probe)
        const color = getComputedStyle(probe).color
        probe.remove()
        return color
      })
    JS
  end

  # The window sized so that the library (`#media-library`, the rail's
  # container) is `width` wide, measured on the page itself: the sidebar,
  # the content's padding and the scrollbar stand between the two.
  def at_library(width, path)
    at_window(width + 400) do
      visit_screen path
      2.times do
        current = page.current_window.size
        page.current_window.resize_to(current.first + (width - library_width).round, current.last)
        await_frames
      end
      assert_in_delta width, library_width, 0.5, "the library is #{width}px wide"
      yield
    end
  end

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

  # Each declaration's computed value on a probe inside the content frame,
  # where the screen's own tokens apply.
  def token_values(*declarations)
    page.evaluate_script(<<~JS)
      #{declarations.to_json}.map((declaration) => {
        const probe = document.createElement("div")
        probe.style.cssText = declaration
        document.querySelector("#content").append(probe)
        const style = getComputedStyle(probe)
        const value = declaration.startsWith("color") ? style.color : style.boxShadow
        probe.remove()
        return value
      })
    JS
  end

  def tile_look(asset)
    page.evaluate_script(<<~JS)
      (() => {
        const style = getComputedStyle(document.querySelector("#media-asset-#{asset.id} a"))
        return { shadow: style.boxShadow, outlineStyle: style.outlineStyle, outlineWidth: style.outlineWidth, outlineOffset: style.outlineOffset, outlineColor: style.outlineColor, borderWidth: style.borderTopWidth }
      })()
    JS
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
