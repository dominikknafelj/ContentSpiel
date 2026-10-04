require "application_system_test_case"

# The Media module's own grid and side panel (media library design spec
# §6, Task 7; round 3 Task 8): a real multi-file upload through the file
# input (`admin--media-upload`), then opening one of the uploaded images and
# setting its German alt text; and the panel's live effect on the tile and the
# segment counts.
class Admin::MediaLibrarySystemTest < ApplicationSystemTestCase
  test "uploading two files by the file input, opening one, and setting a German alt text persists" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))

    visit "/cs-studio/media"
    await_admin_controllers

    # A real, single multi-file selection on the visible file input --
    # `admin--media-upload#filesSelected` fires one POST per file, one at a time
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
    # (`data-turbo-frame="_top"`, `Admin::LanguageTabsComponent`'s own
    # comment) to actually land before typing -- alt/caption have no
    # read-only "original" hint the way a translated column with one would
    # (`Admin::LanguagesSystemTest`'s own comment on why *that* test polls
    # `[data-original-for]` first), so this polls the switcher's own
    # current-locale marker instead; text matched case-insensitively since
    # the switcher's own CSS renders it visually uppercase ("DEUTSCH")
    # while the DOM text is "Deutsch".
    assert_selector "nav[aria-label='Languages'] [aria-current='true']", text: /deutsch/i

    fill_in "Alt", with: "Ein Sonnenuntergang"
    assert_selector "#media-save-status", text: /\A(● )?SAVED( TO SITE)? \d{2}:\d{2}\z/, wait: 5

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
    assert_operator width, :<, 880, "the premise: the panel's form is narrower than 880px (was #{width})"
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
    assert_selector "[data-admin--media-drop-target=overlay]", text: "Drop images to upload", visible: :visible
    dispatch_file_drop("tiny.png")

    assert_no_selector "[data-admin--media-drop-target=overlay]", visible: :visible
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
    assert_no_selector "[data-admin--media-drop-target=overlay]", visible: :visible

    dispatch_file_drag("dragenter", "tiny.png")
    assert_selector "[data-admin--media-drop-target=overlay]", visible: :visible
    # Entering and leaving a child (the counted enter/leave) does not flicker it...
    dispatch_file_drag("dragenter", "tiny.png")
    dispatch_file_drag("dragleave", "tiny.png", related: true)
    assert_selector "[data-admin--media-drop-target=overlay]", visible: :visible
    # ...and Escape ends the drag.
    page.driver.browser.keyboard.type(:escape)
    assert_no_selector "[data-admin--media-drop-target=overlay]", visible: :visible
    assert_equal 0, Media::Asset.count
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

  private

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

  # Clicks a tile and waits until the panel is open AND Turbo has finished with
  # the click. A tile is a link into the `content` frame with `data-turbo-action
  # ="advance"`, which Turbo promotes to a page visit once the frame has loaded:
  # a few dozen ms after the panel's DOM appears it fires `turbo:visit` and
  # re-renders the body. A test that clicked or typed in that gap would have its
  # visit superseded (a language tab) or its text replaced (a field) -- a gap no
  # person lives in, but a scripted browser does.
  def click_tile(asset)
    page.execute_script("window.__tileVisitDone = false; document.addEventListener('turbo:load', () => { window.__tileVisitDone = true }, { once: true })")
    find("#media-asset-#{asset.id} a").click
    assert_selector "#media-panel", wait: 5
    assert_eventually(message: "the tile's promoted visit never finished") { page.evaluate_script("window.__tileVisitDone") }
    await_admin_controllers
  end

  # Same "poll the record, not the status text" reasoning `Admin
  # ::GroupsSystemTest#assert_speakers_eventually` gives its own: the
  # status line's own "Saved HH:MM" text already proved a save landed, but
  # only reading the field back off the record proves it landed with
  # *this* value, in *this* locale.
  def assert_alt_eventually(asset, locale, value)
    deadline = Time.current + 5.seconds

    loop do
      current = asset.reload.alt(locale: locale)
      break if current == value

      raise Minitest::Assertion, "expected alt(locale: #{locale}) to become #{value.inspect}, got #{current.inspect}" if Time.current > deadline

      sleep 0.1
    end
  end
end
